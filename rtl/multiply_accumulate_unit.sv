module Multiply_Accumulate_Unit #(parameter DATA_WIDTH = 16) (
  input logic clk, rst, valid_in,
  input logic signed [DATA_WIDTH-1:0] in_top, in_side,
  input logic signed [DATA_WIDTH*2-1:0] acc_in,
  output logic signed [DATA_WIDTH-1:0] out_top, out_side,
  output logic signed [DATA_WIDTH*2-1:0] acc_out
);
  always_ff @(posedge clk) begin
    if (rst) begin
      out_top <= 'b0;
      out_side <= 'b0;
      acc_out <= 'b0;
    end
    else if (valid_in) begin
      acc_out <= acc_in + in_top * in_side;
      out_top <= in_top;
      out_side <= in_side;
    end
  end
endmodule
