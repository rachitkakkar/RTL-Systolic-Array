module instrumentation #(
  parameter N = 8,
  parameter DATA_WIDTH = 8,
  parameter S_AXIS_DATA_WIDTH = N * DATA_WIDTH,
  parameter M_AXIS_DATA_WIDTH = N * 2 * DATA_WIDTH
)(
  input logic clk,
  input logic rstn,
  
  // AXI4-Stream Slave Interface (Input Matrices)
  input logic [S_AXIS_DATA_WIDTH-1:0] s_axis_tdata,
  input logic s_axis_tvalid,
  output logic s_axis_tready,
  input logic s_axis_tlast, // Optional

  // AXI4-Stream Master Interface (Output Matrix)
  output logic [M_AXIS_DATA_WIDTH-1:0] m_axis_tdata,
  output logic m_axis_tvalid,
  input logic m_axis_tready,
  output logic m_axis_tlast
);

  logic valid_in;
  logic signed [DATA_WIDTH-1:0] row_in [0:N-1];
  logic signed [DATA_WIDTH-1:0] column_in [0:N-1];
  logic signed [(2*DATA_WIDTH)-1:0] acc_output [0:N-1][0:N-1];
  logic valid_out;

  systolic_array #(
    .N(N),
    .DATA_WIDTH(DATA_WIDTH)
  ) sys_array_inst (
    .clk(clk),
    .rst(~rstn),
    .valid_in(valid_in),
    .row_in(row_in),
    .column_in(column_in),
    .acc_output(acc_output),
    .valid_out(valid_out)
  );

  typedef enum logic [2:0] {
    IDLE,
    RECV_A,
    RECV_B,
    COMPUTE,
    SEND_C
  } state_t;

  state_t state, next_state;

  // Buffers for A and B
  logic [S_AXIS_DATA_WIDTH-1:0] A_matrix [0:N-1];
  logic [S_AXIS_DATA_WIDTH-1:0] B_matrix [0:N-1];

  logic [$clog2(N+1)-1:0] recv_cnt;
  logic [$clog2(N+1)-1:0] send_cnt;
  logic [$clog2(N+1)-1:0] feed_cnt;

  // Unpack logic for array inputs
  always_comb begin
    for (int i = 0; i < N; i++) begin
      row_in[i] = A_matrix[feed_cnt][i*DATA_WIDTH +: DATA_WIDTH];
      column_in[i] = B_matrix[feed_cnt][i*DATA_WIDTH +: DATA_WIDTH];
    end
  end

  always_ff @(posedge clk) begin
    if (!rstn) begin
      state <= IDLE;
      recv_cnt <= '0;
      send_cnt <= '0;
      feed_cnt <= '0;
    end else begin
      case (state)
        IDLE: begin
          recv_cnt <= '0;
          send_cnt <= '0;
          feed_cnt <= '0;
          if (s_axis_tvalid) begin
            state <= RECV_A;
            A_matrix[0] <= s_axis_tdata;
            recv_cnt <= 1;
          end
        end

        RECV_A: begin
          if (s_axis_tvalid && s_axis_tready) begin
            A_matrix[recv_cnt] <= s_axis_tdata;
            if (recv_cnt == N - 1) begin
              state <= RECV_B;
              recv_cnt <= '0;
            end else begin
              recv_cnt <= recv_cnt + 1;
            end
          end
        end

        RECV_B: begin
          if (s_axis_tvalid && s_axis_tready) begin
            B_matrix[recv_cnt] <= s_axis_tdata;
            if (recv_cnt == N - 1) begin
              state <= COMPUTE;
              recv_cnt <= '0;
              feed_cnt <= '0;
            end else begin
              recv_cnt <= recv_cnt + 1;
            end
          end
        end

        COMPUTE: begin
          if (feed_cnt < N) begin
            feed_cnt <= feed_cnt + 1;
          end
          if (valid_out) begin
            state <= SEND_C;
          end
        end

        SEND_C: begin
          if (m_axis_tready && m_axis_tvalid) begin
            if (send_cnt == N - 1) begin
              state <= IDLE;
            end else begin
              send_cnt <= send_cnt + 1;
            end
          end
        end
        
        default: state <= IDLE;
      endcase
    end
  end

  // Combinational Outputs
  always_comb begin
    s_axis_tready = 1'b0;
    m_axis_tvalid = 1'b0;
    m_axis_tlast = 1'b0;
    valid_in = 1'b0;
    m_axis_tdata = '0;

    case (state)
      IDLE: begin
        s_axis_tready = 1'b1;
      end
      RECV_A: begin
        s_axis_tready = 1'b1;
      end
      RECV_B: begin
        s_axis_tready = 1'b1;
      end
      COMPUTE: begin
        valid_in = 1'b1;
      end
      SEND_C: begin
        m_axis_tvalid = 1'b1;
        if (send_cnt == N - 1) m_axis_tlast = 1'b1;
        for (int i = 0; i < N; i++) begin
          m_axis_tdata[i * (2*DATA_WIDTH) +: (2*DATA_WIDTH)] = acc_output[send_cnt][i];
        end
      end
      default: ; // Just it avoid Warning-CASEINCOMPLETE in Verilator
    endcase
  end

endmodule