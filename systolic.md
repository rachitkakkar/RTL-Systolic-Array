Guide I found online:
* Upon closer inspection, it appears it could be written by AI (very GPT like), but it was still helpful

Here’s a practical, Verilog-first guide to building a systolic architecture on [FPGA](https://www.ampheo.com/c/fpgas-field-programmable-gate-array). We’ll do a matrix-multiply (C = A×B) because it’s the canonical example, but the pattern applies to FIR, conv, etc.
![sm1-2](https://hackmd.io/_uploads/ryU1t-MyWx.png)

**1) Core idea (in 20 seconds)**

* Arrange identical processing elements (PEs) in a grid.
* Stream A’s rows left→right and B’s columns top→bottom.
* Each PE multiplies its local A and B values, accumulates, and forwards them to its neighbor.
* After a fixed latency, each PE holds one element of C.

Latency (for an N×N tile): ≈ pipeline depth + 2N−2 cycles. Throughput: one C element per PE per cycle once full.

**2) Choose numeric format**

Use fixed-point (e.g., Q1.15 or Q8.8) for small FPGAs; use [DSP](https://www.ampheo.com/c/dsp-digital-signal-processors) blocks for multipliers.

`localparam AW=16, BW=16, CW=32; // A,B 16-bit; accumulator 32-bit`

**3) A tiny PE (multiply-accumulate + pass-through)**

Each cycle:

* take A_in, B_in
* acc <= acc + A_in * B_in
* pass A to the right, B to the bottom

```
module pe_mac #(
  parameter AW=16, BW=16, CW=32
)(
  input  wire              clk,
  input  wire              rst,
  input  wire              vld_in,         // data valid (simple global enable)
  input  wire signed [AW-1:0] a_in,
  input  wire signed [BW-1:0] b_in,
  input  wire signed [CW-1:0] acc_in,      // optional external init (usually 0)
  output reg  signed [AW-1:0] a_out,
  output reg  signed [BW-1:0] b_out,
  output reg  signed [CW-1:0] acc_out
);
  always @(posedge clk) begin
    if (rst) begin
      a_out  <= '0; b_out <= '0; acc_out <= '0;
    end else if (vld_in) begin
      a_out  <= a_in;
      b_out  <= b_in;
      acc_out <= acc_in + $signed(a_in) * $signed(b_in); // uses DSP slice
    end
  end
endmodule
```


* In a classic systolic array we keep acc inside the PE and only output when finished.
* Above we expose acc_in/acc_out so we can daisy-chain or clear easily. For a “pure” systolic PE, replace acc_in with an internal register plus a clear signal per output tile.

**4) 2D mesh (N×N) with generate**

* Left edge receives A stream (one element per row, staggered).
* Top edge receives B stream (one element per column, staggered).
* Bottom-right corner finishes last.

```
module systolic_matmul #(
  parameter N = 4,
  parameter AW=16, BW=16, CW=32
)(
  input  wire                   clk,
  input  wire                   rst,
  input  wire                   vld_in,
  // Stream into left edge: N elements per “phase”, one per row
  input  wire signed [AW-1:0]   a_in   [0:N-1],
  // Stream into top edge: N elements per phase, one per column
  input  wire signed [BW-1:0]   b_in   [0:N-1],
  // Read out partial/full sums from all PEs
  output wire signed [CW-1:0]   c_out  [0:N-1][0:N-1]
);
  // Wires between PEs
  wire signed [AW-1:0] a_bus [0:N][0:N-1];
  wire signed [BW-1:0] b_bus [0:N-1][0:N];
  wire signed [CW-1:0] acc_bus [0:N-1][0:N-1];

  // Inject edges (left/top). Stage the edges one row/col per cycle outside.
  genvar i,j;
  generate
    // Left edge inputs
    for (i=0; i<N; i=i+1) begin : LEFT_IN
      assign a_bus[0][i] = a_in[i];
    end
    // Top edge inputs
    for (j=0; j<N; j=j+1) begin : TOP_IN
      assign b_bus[j][0] = b_in[j];
    end

    // PEs
    for (i=0; i<N; i=i+1) begin : ROW
      for (j=0; j<N; j=j+1) begin : COL
        wire signed [AW-1:0] a_here = a_bus[j][i];     // note index order
        wire signed [BW-1:0] b_here = b_bus[i][j];
        wire signed [CW-1:0] acc_in = (j==0) ? '0 : acc_bus[i][j-1]; // optional chain

        pe_mac #(.AW(AW),.BW(BW),.CW(CW)) U (
          .clk(clk), .rst(rst),
          .vld_in(vld_in),
          .a_in(a_here),
          .b_in(b_here),
          .acc_in(acc_in),
          .a_out(a_bus[j+1][i]),     // pass A right
          .b_out(b_bus[i][j+1]),     // pass B down
          .acc_out(acc_bus[i][j])    // running sum
        );

        assign c_out[i][j] = acc_bus[i][j]; // tap (valid when computation done)
      end
    end
  endgenerate
endmodule
```


**Feeding & scheduling:**
You must skew the input streams so that A[i,k] reaches row i and B[k,j] reaches column j on the same cycle. Easiest: before the array, add per-row/per-column shift registers (SRLs/BRAM FIFOs) to delay tokens. For an N×N tile:

* Delay A row i by i cycles; delay B column j by j cycles.
* Then feed k=0..K−1 pairs across K cycles for inner dimension K.
* After K + (i+j) cycles, c_out[i][j] is valid.

**5) Edge logic: simple feeder (concept)**

Below is a minimalist feeder that applies the required stagger using per-row/col shift-registers. In practice you’ll use BRAM FIFOs (AXI-Stream) and a controller FSM.

```
// Concept: stagger inputs so data "wavefront" moves diagonally.
module stagger_edges #(
  parameter N=4, AW=16, BW=16
)(
  input  wire                 clk, rst, vld_in,
  input  wire [AW-1:0]        a_row [0:N-1], // k-th elements of each A row
  input  wire [BW-1:0]        b_col [0:N-1], // k-th elements of each B column
  output reg  [AW-1:0]        a_left[0:N-1], // to systolic left edge
  output reg  [BW-1:0]        b_top [0:N-1]  // to systolic top edge
);
  integer i;
  always @(posedge clk) begin
    if (rst) begin
      for (i=0;i<N;i=i+1) begin a_left[i]<='0; b_top[i]<='0; end
    end else if (vld_in) begin
      // In real designs: implement i-cycle delays per index i.
      // Here we just register once for illustration.
      for (i=0;i<N;i=i+1) begin
        a_left[i] <= a_row[i];  // add i-deep SRL/FIFO on each lane
        b_top[i]  <= b_col[i];  // add i-deep SRL/FIFO on each lane
      end
    end
  end
endmodule
```


Production tip: Implement the i-cycle delays with SRL16/32 (on [Xilinx](https://www.vemeko.com/product/#xilinx)) or small BRAM FIFOs; synthesis maps them efficiently. This is where the “systolic” timing alignment really happens.

**6) Handshake & streaming**

Prefer AXI-Stream-style valid/ready per edge:

* Each PE can just accept one sample per cycle (II=1).
* Put FIFOs at array boundaries to bridge to DDR/host.
* For multi-tile matrices, use double buffering (ping-pong BRAMs) and DMA.

**7) Meeting timing & fitting the fabric**

* Map multiplies to [DSPs](https://www.ampheoelec.de/c/dsp-digital-signal-processors); 16×16→32 fits perfectly on most DSP48/ALMs.
* Pipeline: register every PE output (already done) and also edge delays.
* Use floorplanning (optional) to place rows/cols; systolic meshes route cleanly.
* Balance II=1 against resource use (unroll less if you run out of DSP/BRAM).

**8) Verification checklist**

1. Unit test PE against a software MAC.
2. Drive a 2×2 or 3×3 array with tiny matrices, hand-computed results.
3. Sweep random matrices; compare to a Python/NumPy golden model (fixed-point).
4. Add valid/ready and assert that no data is dropped (SystemVerilog assertions help).

**9) Adapting to other kernels**

* FIR / 1D conv: Use a linear systolic chain; shift input samples right, taps downward, accumulate per PE.
* 2D conv: Slide input tiles; reuse line buffers, forward feature maps right/down, weights remain stationary or stream once per output tile.
* BNN/INT8: Replace multiply with XNOR+popcount (BNN) or int8×int8→int32 (INT8).

**10) Minimal 1D “systolic” dot-product (good first build)**
```
module systolic_dot #(
  parameter N=8, W=16, ACCW=32
)(
  input  wire                 clk, rst, vld_in,
  input  wire signed [W-1:0]  x_in,   // stream of vector X
  input  wire signed [W-1:0]  w_in,   // stream of vector W
  output wire signed [ACCW-1:0] y_out // valid after N cycles
);
  wire signed [W-1:0]  x_bus [0:N];
  wire signed [W-1:0]  w_bus [0:N];
  wire signed [ACCW-1:0] acc_bus [0:N];

  assign x_bus[0]=x_in; assign w_bus[0]=w_in; assign acc_bus[0]='0;

  genvar i;
  generate for (i=0;i<N;i=i+1) begin : CHAIN
    pe_mac #(.AW(W),.BW(W),.CW(ACCW)) U (
      .clk(clk), .rst(rst), .vld_in(vld_in),
      .a_in(x_bus[i]), .b_in(w_bus[i]),
      .acc_in(acc_bus[i]),
      .a_out(x_bus[i+1]), .b_out(w_bus[i+1]), .acc_out(acc_bus[i+1])
    );
  end endgenerate

  assign y_out = acc_bus[N];
endmodule
```


Feed the two vectors element-wise for N cycles; after the pipeline fills, y_out holds the dot product.

**Final tips**

* Start with a small N (e.g., 4×4) at II=1, verify, then scale.
* Use fixed-point analysis (range, overflow) and saturating adds if needed.
* For large matrices: tile into blocks that fit on-chip; orchestrate tiles with a simple controller FSM + DMA.
* Keep your clock modest (e.g., 100–200 MHz) but sustain one sample per cycle—that’s where systolic shines.
