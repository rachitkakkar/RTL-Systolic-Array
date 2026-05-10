module UART_Rx #(
    parameter BAUD_RATE = 115200, 
    parameter CLK_SPEED = 100000000, // 100 MHz
    parameter DATA_WIDTH = 16
) (
    input logic clk,
    input logic rst,
    input logic rx,
    output logic signed [DATA_WIDTH-1] output,
    output logic valid
);

    localparam int clocks_per_bit = CLK_SPEED / BAUD_RATE;
    logic [2:0] bit_idx = 'b0;
    logic [$clog2(clocks_per_bit)-1:0] clk_counter = 'b0;

    typedef enum {  
        IDLE,
        START,
        DATA,
        STOP
    } state_t;
    state_t current = IDLE;

    logic [7:0] frame_shift_reg; 

    always_ff @(posedge clk) begin
        if (rst) begin
            clk_counter <= 'b0;
            bit_idx <= 'b0;
            valid <= 0;
        end
        else if (current == IDLE) begin
            if (clk_counter == (clocks_per_bit / 2) - 1) begin
                if (rx == 'b0) begin
                    current <= START;
                end
            end
            
            if (clk_counter == clocks_per_bit - 1) begin
                clk_counter <= 'b0;
            end
            else
                clk_counter <= clk_counter + 1;
        end
        else if (current == START) begin
            if (clk_counter == clocks_per_bit - 1) begin // Sample each bit at center
                current <= DATA;
                clk_counter <= 'b0;
                bit_idx <= 'b0;
            end
            else
                clk_counter <= clk_counter + 1;
        end
        else if (current == DATA) begin
            if (clk_counter == (clocks_per_bit / 2) - 1) begin
                frame_shift_reg <= {rx, frame_shift_reg[7:1]};                
                if (bit_idx == 3'b111) begin
                    bit_idx <= 'b0;
                    current <= STOP;
                end 
                else
                    bit_idx <= bit_idx + 1;
            end
            else if (clk_counter == clocks_per_bit - 1) begin
                clk_counter <= 'b0;
            end
            else
                clk_counter <= clk_counter + 1;
        end
    end
endmodule