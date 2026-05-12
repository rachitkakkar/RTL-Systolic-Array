// This testbench verifies the UART reciever with 8 data bits/1 byte (i.e. 10 bit frames)
// It has not yet been modified to use a DATA_WIDTH parameter like the RTL
`timescale 1ns/10ps

interface uart_rx_if;
  logic clk;
  logic rst;
  logic rx_line;
  logic valid;
  logic signed [7:0] data_out;
endinterface

class generator;
  mailbox #(logic [7:0]) messages;
  function new(mailbox #(logic [7:0]) messages);
    this.messages = messages;
  endfunction

  task run();
    byte ch[12] = {"U", "A", "R", "T", " ", "M", "E", "S", "S", "A", "G", "E"};
    for (int i = 0; i < $size(ch); i++) begin
      $display("[TRANSMIT] Character: %s (%0h)", ch[i], ch[i]);
      messages.put(ch[i]); // Send to driver
      #1000;
    end
  endtask
endclass

class driver;
  mailbox #(logic [7:0]) messages;
  virtual uart_rx_if uart_rx;

  function new(mailbox #(logic [7:0]) messages, virtual uart_rx_if uart_rx);
    this.messages = messages;
    this.uart_rx = uart_rx;
  endfunction

  // 1 second = 1,000,000,000 ns
  // 1,000,000,000 / 115,200 = 8680.5 ns
  localparam BIT_PERIOD = 8681;

  task send_byte(input [7:0] data);
      integer i;
      begin
          uart_rx.rx_line = 0;     // Start bit
          // $display("Current time = %t", $realtime);
          #(BIT_PERIOD);           // Wait for one bit time
          // $display("Current time after = %t", $realtime);
          
          for (i = 0; i < 8; i = i + 1) begin
              uart_rx.rx_line = data[i];        // Data bits (LSB first)
              #(BIT_PERIOD);
          end
          
          uart_rx.rx_line = 1;                  // Stop bit
          #(BIT_PERIOD);
      end
  endtask

  task run();
    logic [7:0] data;

    for (int i = 0; i < 12; i++) begin
      messages.get(data); // Get next byte from generator
      send_byte(data);
    end
  endtask
endclass

class monitor;
  mailbox #(logic [7:0]) recieved;
  virtual uart_rx_if uart_rx;

  function new(mailbox #(logic [7:0]) recieved, virtual uart_rx_if uart_rx);
    this.recieved = recieved;
    this.uart_rx = uart_rx;
  endfunction

  task run();
    int bytes_recived = 0;

    while (bytes_recived < 12) begin
      @(posedge uart_rx.clk);

      if (uart_rx.valid) begin
        logic [7:0] rx_data;
        rx_data = uart_rx.data_out;
        $display("[MONITOR] Recieved Character: %s (%0h)", rx_data, rx_data);
        recieved.put(rx_data);
        bytes_recived++;
      end
    end
  endtask
endclass

class scoreboard;
  mailbox #(logic [7:0]) recieved;

  function new(mailbox #(logic [7:0]) recieved);
    this.recieved = recieved;
  endfunction

  task run();
    logic [7:0] rx_data;
    byte expected_ch[12] = {"U", "A", "R", "T", " ", "M", "E", "S", "S", "A", "G", "E"};
    for (int i = 0; i < $size(expected_ch); i++) begin
      recieved.get(rx_data); // Get received byte
      if (rx_data !== expected_ch[i])
        $display("[SCOREBOARD][FAIL] Expected %s, Got %s", expected_ch[i], rx_data);
      else
        $display("[SCOREBOARD][PASS] Received %s", rx_data);
    end
  endtask
endclass

class environment;
  generator g;
  driver d;
  monitor m;
  scoreboard s;

  mailbox #(logic [7:0]) messages = new();
  mailbox #(logic [7:0]) recieved = new();

  virtual uart_rx_if uart_rx;

  function new(virtual uart_rx_if uart_rx);
    this.uart_rx = uart_rx;
    g = new(messages);
    d = new(messages, uart_rx);
    m = new(recieved, uart_rx);
    s = new(recieved);
  endfunction

  task run();
    fork
      g.run();   // Produce transactions
      d.run();   // Drive DUT
      m.run();   // Monitor RX output
      s.run();   // Check results
    join
  endtask
endclass

module tb_uart_rx;
  uart_rx_if uart_rx();
  uart_rx dut (
    .clk     (uart_rx.clk),
    .rst     (uart_rx.rst),
    .rx_line (uart_rx.rx_line),
    .valid   (uart_rx.valid),
    .data_out(uart_rx.data_out)
  ) ;

  // Clock Generation (100 MHz)
  initial uart_rx.clk = 0;
  always #5 uart_rx.clk = ~uart_rx.clk;

  environment env;

  initial begin
    // Initialize dump file
    $dumpfile("uart_rx.vcd");
    $dumpvars(0, tb_uart_rx);

    // Initialize interface
    uart_rx.rst = 1;
    uart_rx.rx_line = 1;

    #100;
    uart_rx.rst = 0;
    #100;

    // Start environment
    env = new(uart_rx);
    env.run();

    $display("[TB] Simulation completed.");
    $finish;
  end
endmodule