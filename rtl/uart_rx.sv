`timescale 1ns/10ps

module uart_rx #(parameter DATA_WIDTH = 8) (
  input logic clk,
  input logic rst,
  input logic rx_line,
  output logic valid,
  output logic signed [DATA_WIDTH-1:0] data_out
);

  parameter int BAUD_RATE = 115200;
  parameter int CLOCK_RATE = 100000000;
  parameter int SAMPLES = 16;

  localparam CLOCKS_PER_SAMPLE = CLOCK_RATE / (BAUD_RATE * SAMPLES);
  localparam MIDDLE_SAMPLE_POINT = SAMPLES / 2;
  // localparam SAMPLING_WINDOW = CLOCKS_PER_SAMPLE * SAMPLES;

  typedef enum {
    IDLE,
    START,
    DATA,
    STOP
  } state_t;

  state_t current;
  logic [$clog2(CLOCKS_PER_SAMPLE)-1:0] clk_counter;
  logic [$clog2(SAMPLES)-1:0] sample_cnt;
  logic signed [DATA_WIDTH-1:0] frame_shift_reg;
  logic [$clog2(DATA_WIDTH):0] bit_cnt;

  // Sequential output/behavior
  always_ff @(posedge clk) begin
    if (rst) begin // Synchronous reset
      clk_counter <= 0;
      sample_cnt <= 0;
      bit_cnt <= 0;
      current <= IDLE;
      valid <= 0;
    end
    else begin
      case (current)
        IDLE: begin
          if (!rx_line) begin // Detect first falling edge
            current <= START;
            clk_counter <= 'b0;
            sample_cnt <= 'b0;
            valid <= 'b0;
          end
        end
        START: begin
          if (clk_counter >= CLOCKS_PER_SAMPLE-1) begin
            clk_counter <= 'b0;
            if (sample_cnt >= SAMPLES-1) begin // Wait one bit time before moving onto data state
              current <= DATA;
              sample_cnt <= 'b0;
              bit_cnt <= 'b0;
            end
            else
              sample_cnt <= sample_cnt + 1;
          end
          else
            clk_counter <= clk_counter + 1;
          if (sample_cnt == MIDDLE_SAMPLE_POINT && clk_counter == 'b0) begin // Check low in the middle
            if (rx_line) // If high, not full start bit -- rather noise to be rejected
              current <= IDLE;
          end
        end
        DATA: begin
          if (clk_counter >= CLOCKS_PER_SAMPLE-1) begin
            clk_counter <= 'b0;
            if (sample_cnt >= SAMPLES-1) begin
              if (bit_cnt == DATA_WIDTH) begin // Done with data bits
                current <= STOP;
              end
              sample_cnt <= 'b0; // Next bit
            end
            else
              sample_cnt <= sample_cnt + 1;
          end
          else
            clk_counter <= clk_counter + 1;
          if (sample_cnt == MIDDLE_SAMPLE_POINT && clk_counter == 'b0) begin // Sample in the middle
            frame_shift_reg[bit_cnt] <= rx_line;
            bit_cnt <= bit_cnt + 1;
          end
        end
        STOP: begin
          if (clk_counter >= CLOCKS_PER_SAMPLE-1) begin
            clk_counter <= 'b0;
            sample_cnt <= sample_cnt + 1;
          end
          else
            clk_counter <= clk_counter + 1;
          if (sample_cnt == MIDDLE_SAMPLE_POINT && clk_counter == 'b0) begin // Check high in the middle
            if (rx_line) begin
              valid <= 1'b1;
              data_out <= frame_shift_reg;
            end
          end
          else
            valid <= 1'b0; // Pull valid low after one clock cycle
          if (sample_cnt >= SAMPLES-1) begin // Wait one bit time before moving onto IDLE state
            current <= IDLE;
          end
        end
      endcase
    end
  end
endmodule