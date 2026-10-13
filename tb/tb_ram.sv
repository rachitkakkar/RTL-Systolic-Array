// Disclaimer: The following unit test is AI-generated for convenience
// RAM unit test using the project's generator/driver/monitor/scoreboard style.
`timescale 1ns/1ps

interface ram_if(input logic clk);
  logic active = 0;
  logic wr_en = 0, rd_en = 0;
  logic [2:0] wr_addr = 0, rd_addr = 0;
  logic [15:0] wr_data = 0, rd_data;
endinterface

class transaction;
  bit wr_en, rd_en;
  logic [2:0] wr_addr, rd_addr;
  logic [15:0] wr_data;
endclass

class generator;
  mailbox #(transaction) stimulus, expected;

  function new(mailbox #(transaction) stimulus, mailbox #(transaction) expected);
    this.stimulus = stimulus;
    this.expected = expected;
  endfunction

  task send(bit wr_en, bit rd_en, logic [2:0] wr_addr, rd_addr, logic [15:0] data);
    transaction t = new();
    t.wr_en = wr_en;
    t.rd_en = rd_en;
    t.wr_addr = wr_addr;
    t.rd_addr = rd_addr;
    t.wr_data = data;
    stimulus.put(t);
    expected.put(t);
  endtask

  task run();
    // Write before reading: uninitialized RAM contents are intentionally undefined.
    for (int i = 0; i < 5; i++) send(1, 0, 3'(i), 0, 16'(16'h100 + i));
    for (int i = 0; i < 5; i++) send(0, 1, 0, 3'(i), 0);
    send(1, 1, 2, 2, 16'hffff); // Same address: read old data.
    send(0, 1, 0, 2, 0);        // Following read gets the new data.
    send(0, 0, 2, 0, 16'hdead); // Disabled write and read.
    send(0, 1, 0, 2, 0);        // Disabled write must not change memory.
    send(1, 0, 0, 4, 16'habcd); // Write while read output holds.
    send(0, 1, 0, 0, 0);
    send(1, 1, 4, 1, 16'hfedc); // Independent read and write addresses.
    send(0, 1, 0, 4, 0);
  endtask
endclass

class driver;
  mailbox #(transaction) stimulus;
  virtual ram_if vif;

  function new(mailbox #(transaction) stimulus, virtual ram_if vif);
    this.stimulus = stimulus;
    this.vif = vif;
  endfunction

  task run();
    repeat (18) begin
      transaction t;
      stimulus.get(t);
      @(negedge vif.clk);
      vif.active = 1;
      vif.wr_en = t.wr_en;
      vif.rd_en = t.rd_en;
      vif.wr_addr = t.wr_addr;
      vif.rd_addr = t.rd_addr;
      vif.wr_data = t.wr_data;
      @(posedge vif.clk);
    end
    @(negedge vif.clk);
    vif.wr_en = 0;
    vif.rd_en = 0;
    vif.active = 0;
  endtask
endclass

class monitor;
  mailbox #(logic [15:0]) results;
  virtual ram_if vif;

  function new(virtual ram_if vif, mailbox #(logic [15:0]) results);
    this.vif = vif;
    this.results = results;
  endfunction

  task run();
    logic [15:0] sampled_data;
    bit have_read = 0;
    wait(vif.active);
    repeat (18) begin
      @(posedge vif.clk);
      #1; // Observe the registered read result after nonblocking assignments.
      sampled_data = vif.rd_data;
      results.put(sampled_data);
      if (vif.rd_en) have_read = 1;
      @(negedge vif.clk); #1;
      if (have_read && vif.rd_data !== sampled_data)
        $fatal(1, "Read output changed before the next rising edge");
    end
  endtask
endclass

class scoreboard;
  mailbox #(transaction) expected;
  mailbox #(logic [15:0]) results;
  logic [15:0] reference_memory [0:4];
  logic [15:0] held_data;
  bit have_read = 0;

  function new(mailbox #(transaction) expected, mailbox #(logic [15:0]) results);
    this.expected = expected;
    this.results = results;
  endfunction

  task run();
    repeat (18) begin
      transaction t;
      logic [15:0] actual;
      expected.get(t);
      results.get(actual);
      // Read precedes write in the model to check read-first collisions.
      if (t.rd_en) begin
        held_data = reference_memory[t.rd_addr];
        have_read = 1;
      end
      if (t.wr_en) reference_memory[t.wr_addr] = t.wr_data;
      if (have_read && actual !== held_data)
        $fatal(1, "[SCOREBOARD][FAIL] Expected %h, got %h", held_data, actual);
    end
    $display("[SCOREBOARD][PASS] RAM writes, synchronous reads, enables, and read-first collisions");
  endtask
endclass

class environment;
  generator g;
  driver d;
  monitor m;
  scoreboard s;
  mailbox #(transaction) stimulus, expected;
  mailbox #(logic [15:0]) results;

  function new(virtual ram_if vif);
    stimulus = new();
    expected = new();
    results = new();
    g = new(stimulus, expected);
    d = new(stimulus, vif);
    m = new(vif, results);
    s = new(expected, results);
  endfunction

  task run();
    fork
      g.run();
      d.run();
      m.run();
      s.run();
    join
  endtask
endclass

module tb_ram;
  logic clk = 0;
  always #5 clk = ~clk;
  ram_if vif(clk);
  environment env;

  ram #(.DATA_WIDTH(16), .DEPTH(5)) dut (
    .clk(clk),
    .wr_en(vif.wr_en), .wr_addr(vif.wr_addr), .wr_data(vif.wr_data),
    .rd_en(vif.rd_en), .rd_addr(vif.rd_addr), .rd_data(vif.rd_data)
  );

  initial begin
    env = new(vif);
    env.run();
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "[TB] RAM test timed out");
  end
endmodule
