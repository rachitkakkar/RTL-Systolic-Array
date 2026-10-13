module instrumentation #(
  parameter N = 8,
  parameter DATA_WIDTH = 8,
  parameter ACC_WIDTH = 2 * DATA_WIDTH + $clog2(N),
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
  logic start, busy, done;
  localparam ADDR_WIDTH = (N > 1) ? $clog2(N) : 1;
  logic [$clog2(3*N + 1)-1:0] phase;
  logic wr_a_en, wr_b_en;
  logic [ADDR_WIDTH-1:0] wr_addr;
  logic signed [DATA_WIDTH-1:0] row_in [0:N-1];
  logic signed [DATA_WIDTH-1:0] column_in [0:N-1];
  logic signed [ACC_WIDTH-1:0] acc_output [0:N-1][0:N-1];

  // logic ping_pong_sel;
  // logic send_C_end;
  // Sending C ends at the same time m_axis_tlast is asserted, so I'll just set it as an alias
  // assign send_C_end = m_axis_tlast;

  systolic_array_compute #(
    .N(N),
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
  ) sys_array_inst (
    .clk(clk),
    .rst(~rstn),
    .start(start),
    .busy(busy),
    .done(done),
    .valid_in(valid_in),
    .row_in(row_in),
    .column_in(column_in),
    .acc_output(acc_output),
    .phase(phase)
  );

  typedef enum logic [2:0] {
    IDLE,
    RECV_A,
    RECV_B,
    START_COMPUTE,
    COMPUTE,
    SEND_C
  } state_t;

  state_t state, next_state;

  logic [$clog2(N+1)-1:0] recv_cnt;
  logic [$clog2(N+1)-1:0] send_cnt;

  // Load the sole operand buffer directly from accepted AXI beats.
  assign wr_a_en = s_axis_tvalid && s_axis_tready && (state == IDLE || state == RECV_A);
  assign wr_b_en = s_axis_tvalid && s_axis_tready && state == RECV_B;
  assign wr_addr = (state == IDLE) ? '0 : ADDR_WIDTH'(recv_cnt);

  matrix_buffer #(.N(N), .DATA_WIDTH(DATA_WIDTH)) operands (
    .clk(clk), .clear(!rstn || start),
    .wr_a_en(wr_a_en), .wr_b_en(wr_b_en), .wr_addr(wr_addr),
    .wr_a_data(s_axis_tdata[N*DATA_WIDTH-1:0]),
    .wr_b_data(s_axis_tdata[N*DATA_WIDTH-1:0]),
    .rd_en(busy && valid_in), .phase(phase),
    .row_out(row_in), .column_out(column_in)
  );

  always_ff @(posedge clk) begin
    if (!rstn) begin
      state <= IDLE;
      recv_cnt <= '0;
      send_cnt <= '0;
      // ping_pong_sel <= '0;
    end else begin
      case (state)
        IDLE: begin
          recv_cnt <= '0;
          send_cnt <= '0;
          if (s_axis_tvalid && s_axis_tready) begin
            state <= RECV_A;
            recv_cnt <= 1;
          end
        end

        RECV_A: begin
          if (s_axis_tvalid && s_axis_tready) begin
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
            if (recv_cnt == N - 1) begin
              state <= START_COMPUTE;
              recv_cnt <= '0;
            end else begin
              recv_cnt <= recv_cnt + 1;
            end
          end
        end

        START_COMPUTE: begin
          if (!busy) state <= COMPUTE;
        end

        COMPUTE: begin
          if (done) begin
            state <= SEND_C;
          end
        end

        SEND_C: begin
          if (m_axis_tready && m_axis_tvalid) begin
            // // Swap accumulation registers (ping-pong buffering)
            // ping_pong_sel <= ~ping_pong_sel;

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

  // always_ff @(posedge clk) begin
  //   if (send_C_start && m_axis_tready && m_axis_tvalid) begin
      
  //   end
  // end

  // Combinational Outputs
  always_comb begin
    s_axis_tready = 1'b0;
    m_axis_tvalid = 1'b0;
    m_axis_tlast = 1'b0;
    valid_in = 1'b0;
    start = 1'b0;
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
      START_COMPUTE: begin
        start = !busy;
      end
      COMPUTE: begin
        valid_in = 1'b1;
      end
      SEND_C: begin
        m_axis_tvalid = 1'b1;
        // send_C_start = 1'b1;
        if (send_cnt == N - 1) m_axis_tlast = 1'b1;
        for (int i = 0; i < N; i++) begin
          m_axis_tdata[i * (2*DATA_WIDTH) +: (2*DATA_WIDTH)] = acc_output[send_cnt][i];
        end
      end
      default: ; // Just to avoid Warning-CASEINCOMPLETE in Verilator
    endcase
  end

endmodule