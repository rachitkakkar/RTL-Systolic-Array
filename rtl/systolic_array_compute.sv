module systolic_array_compute #(
  parameter N = 8,
  parameter DATA_WIDTH = 8,
  parameter ACC_WIDTH = 2 * DATA_WIDTH + $clog2(N)
) (
  input logic clk, rst, start, valid_in,
  input logic signed [DATA_WIDTH-1:0] row_in [0:N-1], 
  input logic signed [DATA_WIDTH-1:0] column_in [0:N-1],
  output logic signed [ACC_WIDTH-1:0] acc_output [0:N-1][0:N-1],
  output logic busy, done,
  output logic [$clog2(3*N + 1)-1:0] phase
);

  localparam COUNTER_WIDTH = $clog2(3*N + 1);
  logic [COUNTER_WIDTH-1:0] clk_counter;
  logic job_clear, advance;
  assign phase = clk_counter;

  // start is accepted only while idle, on a separate cycle from the first row.
  // valid_in enables every pipeline step, including zero-padding/drain cycles.
  assign job_clear = start && !busy;
  assign advance = busy && valid_in;

  // Clock counter
  always_ff @(posedge clk) begin
    if (rst) begin
      clk_counter <= 'b0;
      busy <= 1'b0;
      done <= 1'b0;
    end
    else begin
      done <= 1'b0;
      if (job_clear) begin
        clk_counter <= '0;
        busy <= 1'b1;
      end else if (advance) begin
        if (clk_counter == COUNTER_WIDTH'(3*N-1)) begin
          busy <= 1'b0;
          done <= 1'b1;
        end else begin
          clk_counter <= clk_counter + 1'b1;
        end
      end
    end
  end

  // top_wires[row][col] -> vertical flow
  // side_wires[row][col] -> horizontal flow
  logic signed [DATA_WIDTH-1:0] top_pass_through_wires [0:N][0:N-1];
  logic signed [DATA_WIDTH-1:0] side_pass_through_wires [0:N-1][0:N];
  
  genvar i, j;
  generate
    for (i = 0; i < N; i++) begin : inputs_gen
      assign top_pass_through_wires[0][i] = column_in[i];
      assign side_pass_through_wires[i][0] = row_in[i];
    end

    for (i = 0; i < N; i++) begin : row_gen
      for (j = 0; j < N; j++) begin : col_gen
        
        multiply_accumulate_unit #(.DATA_WIDTH(DATA_WIDTH)) PE (
          .clk      (clk),
          .rst      (rst || job_clear),
          .valid_in (advance),
          // Data coming IN from previous PE or boundary
          .in_top   (top_pass_through_wires[i][j]),
          .in_side  (side_pass_through_wires[i][j]),
          .acc_in   (acc_output[i][j]),
          // Data going OUT to the next PE in the chain
          .out_top  (top_pass_through_wires[i+1][j]),
          .out_side (side_pass_through_wires[i][j+1]),
          // The accumulated result within this specific PE
          .acc_out  (acc_output[i][j])
        );
        
      end
    end
  endgenerate
endmodule
