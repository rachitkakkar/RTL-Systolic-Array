// TODO: figure out acc output wires
module Systolic_Array #(
  parameter N = 8,
  parameter DATA_WIDTH = 16
) (
  input logic clk, rst, valid_in,
  input logic signed [DATA_WIDTH-1:0] top_matrix_in [0:DATA_WIDTH-1], 
  input logic signed [DATA_WIDTH-1:0] side_matrix_in [0:DATA_WIDTH-1]
);
  logic signed [DATA_WIDTH-1:0] top_pass_through_wires [0:DATA_WIDTH][0:DATA_WIDTH-1];
  logic signed [DATA_WIDTH-1:0] side_pass_through_wires [0:DATA_WIDTH-1][0:DATA_WIDTH];
  logic signed [DATA_WIDTH*2-1:0] acc_output_wires[0:DATA_WIDTH-1][0:DATA_WIDTH];
  
  genvar i, j;
  generate
    for (i = 0; i < N; i++) begin
      assign top_pass_through_wires[0][i] = top_matrix_in[i];
    end

    for (i = 0; i < N; i++) begin
      assign side_pass_through_wires[i][0] = side_matrix_in[i];
    end

    for (i = 0; i < N; i++) begin
      for (j = 0; j < N; j++) begin
        if (j == 0) begin
          assign acc_output_wires[i][j] = 'b0;
        end
        Multiply_Accumulate_Unit PE(
          clk,
          rst,
          valid_in,
          top_pass_through_wires[i][j],
          side_pass_through_wires[i][j],
          top_pass_through_wires[i+1][j],
          side_pass_through_wires[i][j+1],
          acc_output_wires[i][j+1]
        );
      end
    end
  endgenerate
endmodule
