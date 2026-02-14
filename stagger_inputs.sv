module Stagger_Inputs #(
  parameter N = 8,
  parameter DATA_WIDTH = 16,
  parameter BUS_WIDTH = (2 * DATA_WIDTH * N)
) (
  input logic clk, rst,
  
  // Read from BRAM FIFO
  output logic fifo_clk,
  output logic fifo_rd_en,
  input logic fifo_empty, // For backpressure
  input logic [BUS_WIDTH-1:0] fifo_data,

  // To systolic array
  output logic signed [DATA_WIDTH-1:0] skewed_top_row[N-1:0],
  output logic signed [DATA_WIDTH-1:0] skewed_bottom_row[N-1:0],
  output logic in_valid
);

// Buffer of storage for matricies
logic signed [DATA_WIDTH-1:0] A_matrix[N-1:0][N-1:0];
logic [DATA_WIDTH-1:0] B_matrix[N-1:0][N-1:0];

// State machine for reading from FIFO and feeding systolic array
typdef enum logic [2:0] {
  IDLE,
  ASSERT_READ,
  LOAD_DATA,
  INJECT
} state_t;
state_t current_state;
logic [$clog2(2*N):0] clk_counter;
logic [$clog2(N):0] load_counter;
logic [$clog2(N):0] inject_counter;

always_ff @(posedge clk) begin
  if (rst) begin
    current_state <= IDLE;
    clock_counter <= 'b0;
    
    for (int i = 0; i < N; i++) begin
      for (int j = 0; j < N; j++) begin
        A_matrix[i][j] <= 'b0;
        B_matrix[i][j] <= 'b0;
      end
    end
  end else begin
    if (in_valid) begin
      if (clock_counter == 2*N-1)
        clock_counter <= 0; // Start next computation after 2*N-1 clock cycles
      else
        clock_counter <= clock_counter + 1;
    end
    case (current_state) 
      IDLE: begin
        if (!fifo_empty)
          state_t <= ASSERT_READ;
      end
      ASSERT_READ: begin
        fifo_rd_en <= 'b1;
        state_t <= LOAD_DATA;
      end
      LOAD_DATA: begin // TODO: load data
        for (int i = 0; i < N; i++) begin
         // A_matrix[i][load_counter] <= fifo_data[]
        end
      end
      INJECT: begin
      end
  end
end


endmodule
