module Multiply_Accumulate_Unit #(parameter DATA_WIDTH=16) (
  input logic clk, rst, valid_in,
  input logic signed [DATA_WIDTH-1:0] a_in, b_in,
  input logic signed [DATA_WIDTH*2-1:0] acc_in,
  output logic signed [DATA_WIDTH-1:0] a_out, b_out,
  output logic signed [DATA_WIDTH*2-1:0] acc_out
);
  always_ff @(posedge clk) begin
    if (rst) begin
      a_out <= 'b0;
      b_out <= 'b0;
      acc_out <= 'b0;
    end
    if (valid_in) begin
      acc_out <= acc_in + a_in * b_in;
      a_out <= a_in;
      b_out <= b_in;
    end
  end
endmodule
