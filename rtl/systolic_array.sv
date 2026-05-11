module Systolic_Array #(
  parameter N = 8,
  parameter DATA_WIDTH = 8
) (
  input logic clk, rst, valid_in,
  input logic signed [DATA_WIDTH-1:0] row_in [0:N-1], 
  input logic signed [DATA_WIDTH-1:0] column_in [0:N-1],
  output logic signed [(2*DATA_WIDTH)-1:0] acc_output [0:N-1][0:N-1],
  output logic valid_out
);
  
  logic [$clog2(2*N):0] clk_counter;

  // Clock counter
  always_ff @(posedge clk) begin
    if (rst) begin
      clk_counter <= 'b0;
      valid_out <= 'b0;
    end
    else begin
      if (clk_counter == 2*N-1) // Assert valid out when computation is done
        valid_out <= 'b1;
      else begin
        if (valid_in)
          clk_counter <= clk_counter + 1;
      end
    end
  end

  // Buffer of storage for matricies
  logic signed [DATA_WIDTH-1:0] A_matrix[N-1:0][N-1:0];
  logic signed [DATA_WIDTH-1:0] B_matrix[N-1:0][N-1:0];

  // Load matricies into buffer
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < N; i++) begin
        for (int j = 0; j < N; j++) begin
          A_matrix[i][j] <= 'b0;
          B_matrix[i][j] <= 'b0;
        end
      end
    end
    else begin
      if (valid_in && clk_counter < N) begin
        for (int i = 0; i < N; i++) begin
          A_matrix[clk_counter][i] <= row_in[i];
          B_matrix[clk_counter][i] <= column_in[i];
        end
      end
    end
  end

  // Pass-through wires: N+1 boundaries to connect N PEs
  logic signed [DATA_WIDTH-1:0] top_matrix_in [0:N-1];
  logic signed [DATA_WIDTH-1:0] side_matrix_in [0:N-1];

  // Skew the data to feed the PEs
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < N; i++) begin
        top_matrix_in[i] <= 'b0;
        side_matrix_in[i] <= 'b0;
      end
    end
    else begin
      if (valid_in) begin
        for (int i = 0; i < N; i = i + 1) begin
          int data_idx = clk_counter - i;

          // Matrix A (rows skewed by 'i' cycles) and Matrix B (columns skewed by 'i' cycles)
          if (data_idx >= 0 && data_idx < N) begin
            top_matrix_in[i] <= B_matrix[data_idx][i];
            side_matrix_in[i] <= A_matrix[i][data_idx];
          end else begin
            // Don't send data yet, buffer with zeroes
            top_matrix_in[i] <= 'b0;
            side_matrix_in[i] <= 'b0;
          end
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
      assign top_pass_through_wires[0][i] = top_matrix_in[i];
      assign side_pass_through_wires[i][0] = side_matrix_in[i];
    end

    for (i = 0; i < N; i++) begin : row_gen
      for (j = 0; j < N; j++) begin : col_gen
        
        Multiply_Accumulate_Unit PE (
          .clk      (clk),
          .rst      (rst),
          .valid_in       (valid_in),
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