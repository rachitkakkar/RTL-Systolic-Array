// SystemVerilog UVM-like testbench for systolic_array
`timescale 1ns/1ps

interface sys_if #(parameter N = 8, parameter DATA_WIDTH = 8) (input logic clk);
  logic rst;
  logic valid_in;
  logic signed [DATA_WIDTH-1:0] row_in [0:N-1];
  logic signed [DATA_WIDTH-1:0] column_in [0:N-1];
  logic signed [(2*DATA_WIDTH)-1:0] acc_output [0:N-1][0:N-1];
  logic valid_out;
endinterface

class generator;
  mailbox #(logic signed [7:0]) m_A;
  mailbox #(logic signed [7:0]) m_B;
  int N;

  function new(mailbox #(logic signed [7:0]) m_A, mailbox #(logic signed [7:0]) m_B, int N);
    this.m_A = m_A;
    this.m_B = m_B;
    this.N = N;
  endfunction

  task run();
    // Generate a simple identity matrix A and some matrix B
    for (int i = 0; i < N; i++) begin
      for (int j = 0; j < N; j++) begin
        if (i == j) m_A.put(1);
        else m_A.put(0);

        m_B.put(i + j + 1); // Simple pattern
      end
    end
  endtask
endclass

class driver;
  mailbox #(logic signed [7:0]) m_A;
  mailbox #(logic signed [7:0]) m_B;
  virtual sys_if vif;
  int N;

  function new(mailbox #(logic signed [7:0]) m_A, mailbox #(logic signed [7:0]) m_B, virtual sys_if vif, int N);
    this.m_A = m_A;
    this.m_B = m_B;
    this.vif = vif;
    this.N = N;
  endfunction

  task run();
    vif.valid_in <= 0;
    wait(vif.rst == 1'b0);
    @(posedge vif.clk);

    for (int cycle = 0; cycle < N; cycle++) begin
      vif.valid_in <= 1;
      for (int i = 0; i < N; i++) begin
        logic signed [7:0] valA, valB;
        m_A.get(valA);
        m_B.get(valB);
        vif.row_in[i] <= valA;
        vif.column_in[i] <= valB;
      end
      @(posedge vif.clk);
    end
  endtask
endclass

class monitor;
  virtual sys_if vif;
  mailbox #(logic signed [15:0]) m_C;
  int N;

  function new(virtual sys_if vif, mailbox #(logic signed [15:0]) m_C, int N);
    this.vif = vif;
    this.m_C = m_C;
    this.N = N;
  endfunction

  task run();
    @(posedge vif.valid_out);
    vif.valid_in <= 0;
    for (int i = 0; i < N; i++) begin
      for (int j = 0; j < N; j++) begin
        m_C.put(vif.acc_output[i][j]);
      end
    end
  endtask
endclass

class scoreboard;
  mailbox #(logic signed [15:0]) m_C;
  int N;

  function new(mailbox #(logic signed [15:0]) m_C, int N);
    this.m_C = m_C;
    this.N = N;
  endfunction

  task run();
    logic signed [15:0] act_C;
    int expected_C [0:7][0:7];

    // Compute expected (A is identity, B is pattern)
    // C = A * B -> C = B
    for (int i = 0; i < N; i++) begin
      for (int j = 0; j < N; j++) begin
        expected_C[i][j] = i + j + 1;
      end
    end

    for (int i = 0; i < N; i++) begin
      for (int j = 0; j < N; j++) begin
        m_C.get(act_C);
        if (act_C !== expected_C[i][j]) begin
          $display("[SCOREBOARD][FAIL] C[%0d][%0d] Expected %0d, Got %0d", i, j, expected_C[i][j], act_C);
        end else begin
          $display("[SCOREBOARD][PASS] C[%0d][%0d] = %0d", i, j, act_C);
        end
      end
    end
  endtask
endclass

class environment;
  generator g;
  driver d;
  monitor m;
  scoreboard s;
  
  mailbox #(logic signed [7:0]) m_A;
  mailbox #(logic signed [7:0]) m_B;
  mailbox #(logic signed [15:0]) m_C;

  virtual sys_if vif;
  int N;

  function new(virtual sys_if vif, int N);
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
        $display("[TB] Scoreboard finished!");
      end
      begin
        #10000;
        $display("[TB] Timeout!");
      end
    join_any
    disable fork;
  endtask
endclass

module tb_systolic_array;
  parameter N = 8;
  parameter DATA_WIDTH = 8;

  logic clk;
  sys_if #(N, DATA_WIDTH) vif(clk);

  systolic_array #(
    .N(N),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk),
    .rst(vif.rst),
    .valid_in(vif.valid_in),
    .row_in(vif.row_in),
    .column_in(vif.column_in),
    .acc_output(vif.acc_output),
    .valid_out(vif.valid_out)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  environment env;

  initial begin
    $dumpfile("sys_array.vcd");
    $dumpvars(0, tb_systolic_array);

    vif.rst = 1;
    vif.valid_in = 0;
    #20 vif.rst = 0;

    env = new(vif, N);
    env.run();

    #100;
    $display("[TB] Simulation completed.");
    $finish;
  end
endmodule
