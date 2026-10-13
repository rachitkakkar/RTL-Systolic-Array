// One copy of each operand, banked by column for N concurrent reads.
// Write ports accept packed rows; read ports return skewed array boundaries.
module matrix_buffer #(
  parameter N = 8,
  parameter DATA_WIDTH = 8,
  parameter ADDR_WIDTH = (N > 1) ? $clog2(N) : 1,
  parameter PHASE_WIDTH = $clog2(3*N + 1)
) (
  input logic clk, clear,
  input logic wr_a_en, wr_b_en,
  input logic [ADDR_WIDTH-1:0] wr_addr,
  input logic [N*DATA_WIDTH-1:0] wr_a_data, wr_b_data,
  input logic rd_en,
  input logic [PHASE_WIDTH-1:0] phase,
  output logic signed [DATA_WIDTH-1:0] row_out [0:N-1],
  output logic signed [DATA_WIDTH-1:0] column_out [0:N-1]
);
  logic [DATA_WIDTH-1:0] a_data [0:N-1], b_data [0:N-1];
  logic [DATA_WIDTH-1:0] a_forward [0:N-1], b_forward [0:N-1];
  logic [N-1:0] a_bypass, b_bypass;
  logic [PHASE_WIDTH-1:0] read_phase;
  logic read_valid;

  always_ff @(posedge clk) begin
    if (clear) begin
      read_valid <= 0;
      read_phase <= '0;
    end else if (rd_en) begin
      read_valid <= 1;
      read_phase <= phase;
    end
  end

  for (genvar bank = 0; bank < N; bank++) begin : banks
    logic bank_rd_en;
    logic [ADDR_WIDTH-1:0] rd_addr;
    // At phase t, A bank k reads row t-k; B bank j reads row t-j.
    assign bank_rd_en = rd_en && !clear && int'(phase) >= bank && int'(phase) < bank+N;
    assign rd_addr = ADDR_WIDTH'(int'(phase) - bank);

    ram #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(N)) a_ram (
      .clk(clk), .wr_en(wr_a_en && !clear), .wr_addr(wr_addr),
      .wr_data(wr_a_data[bank*DATA_WIDTH +: DATA_WIDTH]),
      .rd_en(bank_rd_en), .rd_addr(rd_addr), .rd_data(a_data[bank])
    );
    ram #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(N)) b_ram (
      .clk(clk), .wr_en(wr_b_en && !clear), .wr_addr(wr_addr),
      .wr_data(wr_b_data[bank*DATA_WIDTH +: DATA_WIDTH]),
      .rd_en(bank_rd_en), .rd_addr(rd_addr), .rd_data(b_data[bank])
    );

    // The standalone array loads and reads together. Forward the incoming
    // row on collisions so it keeps the original first-N-cycles interface.
    always_ff @(posedge clk) begin
      if (clear) begin
        a_bypass[bank] <= 0;
        b_bypass[bank] <= 0;
      end else if (rd_en) begin
        a_bypass[bank] <= bank_rd_en && wr_a_en && rd_addr == wr_addr;
        b_bypass[bank] <= bank_rd_en && wr_b_en && rd_addr == wr_addr;
        a_forward[bank] <= wr_a_data[bank*DATA_WIDTH +: DATA_WIDTH];
        b_forward[bank] <= wr_b_data[bank*DATA_WIDTH +: DATA_WIDTH];
      end
    end
  end

  always_comb begin
    for (int lane = 0; lane < N; lane++) begin
      automatic int k = int'(read_phase) - lane;
      row_out[lane] = '0;
      column_out[lane] = '0;
      if (read_valid && k >= 0 && k < N) begin
        row_out[lane] = a_bypass[k] ? a_forward[k] : a_data[k];
        column_out[lane] = b_bypass[lane] ? b_forward[lane] : b_data[lane];
      end
    end
  end
endmodule
