module systolic_array #(
  parameter N = 8,
  parameter DATA_WIDTH = 8,
  parameter ACC_WIDTH = 2 * DATA_WIDTH + $clog2(N)
) (
  input logic clk, rst, start, valid_in,
  input logic signed [DATA_WIDTH-1:0] row_in [0:N-1],
  input logic signed [DATA_WIDTH-1:0] column_in [0:N-1],
  output logic signed [ACC_WIDTH-1:0] acc_output [0:N-1][0:N-1],
  output logic busy, done
);
  localparam ADDR_WIDTH = (N > 1) ? $clog2(N) : 1;
  logic [$clog2(3*N + 1)-1:0] phase;
  logic [N*DATA_WIDTH-1:0] a_write_data, b_write_data;
  logic signed [DATA_WIDTH-1:0] row_data [0:N-1], column_data [0:N-1];

  for (genvar i = 0; i < N; i++) begin : pack_inputs
    assign a_write_data[i*DATA_WIDTH +: DATA_WIDTH] = row_in[i];
    assign b_write_data[i*DATA_WIDTH +: DATA_WIDTH] = column_in[i];
  end

  matrix_buffer #(.N(N), .DATA_WIDTH(DATA_WIDTH)) operands (
    .clk(clk), .clear(rst || (start && !busy)),
    .wr_a_en(busy && valid_in && int'(phase) < N),
    .wr_b_en(busy && valid_in && int'(phase) < N),
    .wr_addr(ADDR_WIDTH'(phase)), .wr_a_data(a_write_data), .wr_b_data(b_write_data),
    .rd_en(busy && valid_in), .phase(phase),
    .row_out(row_data), .column_out(column_data)
  );

  systolic_array_compute #(.N(N), .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) compute (
    .clk(clk), .rst(rst), .start(start), .valid_in(valid_in),
    .row_in(row_data), .column_in(column_data),
    .acc_output(acc_output), .busy(busy), .done(done), .phase(phase)
  );
endmodule
