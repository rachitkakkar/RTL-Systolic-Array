// This testbench verifies the Systolic Array with an 8 by 8 array of 8-bit signed integers
`timescale 1ns/10ps

`define DATA_WIDTH 8
`define N 8

interface sys_if;
  logic clk; 
  logic rst;
  logic valid_in;
  logic signed [`DATA_WIDTH-1:0] row_in [0:`N-1];
  logic signed [`DATA_WIDTH-1:0] column_in [0:`N-1];
  logic signed [(2*`DATA_WIDTH)-1:0] acc_output [0:`N-1][0:`N-1];
  logic valid_out;
endinterface

class generator;
  mailbox #(logic signed [`DATA_WIDTH-1:0]) rows;
  mailbox #(logic signed [`DATA_WIDTH-1:0]) cols;
endclass