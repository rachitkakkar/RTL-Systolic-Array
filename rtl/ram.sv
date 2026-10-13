// Simple dual-port RAM: one write port and one synchronous read port.
// Reads hold their output when rd_en is low. A same-address read/write
// returns the old word (read-first). Contents are not cleared on reset.
module ram #(
  parameter DATA_WIDTH = 8,
  parameter DEPTH = 64,
  parameter ADDR_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
  input logic clk,
  input logic wr_en,
  input logic [ADDR_WIDTH-1:0] wr_addr,
  input logic [DATA_WIDTH-1:0] wr_data,
  input logic rd_en,
  input logic [ADDR_WIDTH-1:0] rd_addr,
  output logic [DATA_WIDTH-1:0] rd_data
);
  logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];

  always_ff @(posedge clk) begin
    if (wr_en) memory[wr_addr] <= wr_data;
    if (rd_en) rd_data <= memory[rd_addr];
  end
endmodule
