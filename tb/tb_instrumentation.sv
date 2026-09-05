// SystemVerilog testbench for instrumentation (AXI4-Stream interface)
// Verifies hardware output against a Python-generated golden model
`timescale 1ns/1ps

interface axis_if #(parameter S_AXIS_DATA_WIDTH = 64, parameter M_AXIS_DATA_WIDTH = 128) (input logic clk);
  logic rstn;
  
  // Slave AXI-Stream
  logic [S_AXIS_DATA_WIDTH-1:0] s_axis_tdata;
  logic s_axis_tvalid;
  logic s_axis_tready;
  logic s_axis_tlast;

  // Master AXI-Stream
  logic [M_AXIS_DATA_WIDTH-1:0] m_axis_tdata;
  logic m_axis_tvalid;
  logic m_axis_tready;
  logic m_axis_tlast;
endinterface

class generator;
  mailbox #(logic [63:0]) m_A;
  mailbox #(logic [63:0]) m_B;
  int N;

  logic [7:0] A_flat [0:63]; // N*N max 
  logic [7:0] B_flat [0:63];
  
  function new(mailbox #(logic [63:0]) m_A, mailbox #(logic [63:0]) m_B, int N);
    this.m_A = m_A;
    this.m_B = m_B;
    this.N = N;
  endfunction

  task run();
    // Load hex files produced by golden-model.py
    $readmemh("tb/matrix_a.hex", A_flat);
    $readmemh("tb/matrix_b.hex", B_flat);
    $display("[GEN] Loaded matrix_a.hex and matrix_b.hex");

    // Pack each row into a single 64-bit AXI word
    for (int row = 0; row < N; row++) begin
      logic [63:0] A_word = '0;
      for (int col = 0; col < N; col++) begin
        A_word[col*8 +: 8] = A_flat[row*N + col];
      end
      m_A.put(A_word);
    end

    for (int row = 0; row < N; row++) begin
      logic [63:0] B_word = '0;
      for (int col = 0; col < N; col++) begin
        B_word[col*8 +: 8] = B_flat[row*N + col];
      end
      m_B.put(B_word);
    end
  endtask
endclass

// Drive the AXI-Stream slave interface
class driver;
  mailbox #(logic [63:0]) m_A;
  mailbox #(logic [63:0]) m_B;
  virtual axis_if vif;
  int N;

  function new(mailbox #(logic [63:0]) m_A, mailbox #(logic [63:0]) m_B, virtual axis_if vif, int N);
    this.m_A = m_A;
    this.m_B = m_B;
    this.vif = vif;
    this.N = N;
  endfunction

  task run();
    vif.s_axis_tvalid <= 0;
    vif.s_axis_tdata <= '0;
    vif.s_axis_tlast <= 0;
    
    wait(vif.rstn == 1'b1);
    @(posedge vif.clk);

    // Stream Matrix A rows
    for (int i = 0; i < N; i++) begin
      logic [63:0] A_row;
      m_A.get(A_row);
      vif.s_axis_tvalid <= 1;
      vif.s_axis_tdata <= A_row;
      do begin
        @(posedge vif.clk);
      end while (!vif.s_axis_tready);
    end
    vif.s_axis_tvalid <= 0;
    
    // Stream Matrix B rows
    for (int i = 0; i < N; i++) begin
      logic [63:0] B_row;
      m_B.get(B_row);
      vif.s_axis_tvalid <= 1;
      vif.s_axis_tdata <= B_row;
      do begin
        @(posedge vif.clk);
      end while (!vif.s_axis_tready);
    end
    vif.s_axis_tvalid <= 0;
    $display("[DRIVER] All data sent.");
  endtask
endclass

// Watches the AXI-Stream master interface for output rows
class monitor;
  virtual axis_if vif;
  mailbox #(logic [127:0]) m_C;
  int N;

  function new(virtual axis_if vif, mailbox #(logic [127:0]) m_C, int N);
    this.vif = vif;
    this.m_C = m_C;
    this.N = N;
  endfunction

  task run();
    vif.m_axis_tready <= 1;
    for (int i = 0; i < N; i++) begin
      do begin
        @(posedge vif.clk);
      end while (!(vif.m_axis_tvalid && vif.m_axis_tready));
      m_C.put(vif.m_axis_tdata);
    end
  endtask
endclass

// Compares hardware output against the Python golden model (gold_result.hex)
class scoreboard;
  mailbox #(logic [127:0]) m_C;
  int N;

  logic [15:0] gold_flat [0:63]; // N*N max
  int pass_count;
  int fail_count;

  function new(mailbox #(logic [127:0]) m_C, int N);
    this.m_C = m_C;
    this.N = N;
    this.pass_count = 0;
    this.fail_count = 0;
  endfunction

  task run();
    logic [127:0] act_row;

    $readmemh("tb/gold_result.hex", gold_flat);
    $display("[SCOREBOARD] Loaded gold_result.hex");
    
    for (int row = 0; row < N; row++) begin
      m_C.get(act_row);
      for (int col = 0; col < N; col++) begin
        logic signed [15:0] act_val;
        logic signed [15:0] exp_val;

        act_val = act_row[col*16 +: 16];
        exp_val = gold_flat[row*N + col];

        if (act_val !== exp_val) begin
          $display("[SCOREBOARD][FAIL] C[%0d][%0d] Expected %0d, Got %0d", row, col, exp_val, act_val);
          fail_count++;
        end else begin
          $display("[SCOREBOARD][PASS] C[%0d][%0d] = %0d", row, col, act_val);
          pass_count++;
        end
      end
    end

    $display("[SCOREBOARD] --- Summary: %0d PASS, %0d FAIL ---", pass_count, fail_count);
  endtask
endclass

class environment;
  generator g;
  driver d;
  monitor m;
  scoreboard s;
  
  mailbox #(logic [63:0]) m_A;
  mailbox #(logic [63:0]) m_B;
  mailbox #(logic [127:0]) m_C;

  virtual axis_if vif;
  int N;

  function new(virtual axis_if vif, int N);
    this.vif = vif;
    this.N = N;
    m_A = new();
    m_B = new();
    m_C = new();
    
    g = new(m_A, m_B, N);
    d = new(m_A, m_B, vif, N);
    m = new(vif, m_C, N);
    s = new(m_C, N);
  endfunction

  task run();
    fork
      g.run();
      d.run();
      m.run();
    join_none

    fork
      begin
        s.run();
      end
      begin
        #50000;
        $display("[TB] Timeout!");
      end
    join_any
    disable fork;
  endtask
endclass

module tb_instrumentation;
  parameter N = 8;
  parameter DATA_WIDTH = 8;
  parameter S_AXIS_DATA_WIDTH = N * DATA_WIDTH;
  parameter M_AXIS_DATA_WIDTH = N * 2 * DATA_WIDTH;

  logic clk;
  axis_if #(S_AXIS_DATA_WIDTH, M_AXIS_DATA_WIDTH) vif(clk);

  instrumentation #(
    .N(N),
    .DATA_WIDTH(DATA_WIDTH),
    .S_AXIS_DATA_WIDTH(S_AXIS_DATA_WIDTH),
    .M_AXIS_DATA_WIDTH(M_AXIS_DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rstn(vif.rstn),
    .s_axis_tdata(vif.s_axis_tdata),
    .s_axis_tvalid(vif.s_axis_tvalid),
    .s_axis_tready(vif.s_axis_tready),
    .s_axis_tlast(vif.s_axis_tlast),
    .m_axis_tdata(vif.m_axis_tdata),
    .m_axis_tvalid(vif.m_axis_tvalid),
    .m_axis_tready(vif.m_axis_tready),
    .m_axis_tlast(vif.m_axis_tlast)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  environment env;

  initial begin
    $dumpfile("instrumentation.vcd");
    $dumpvars(0, tb_instrumentation);

    vif.rstn = 0;
    #20 vif.rstn = 1;

    env = new(vif, N);
    env.run();

    #200;
    $display("[TB] Simulation completed.");
    $finish;
  end
endmodule
