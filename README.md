# RTL-Systolic-Array

A parameterizable hardware implementation of a 2D Systolic Array in SystemVerilog, designed primarily for matrix multiplication acceleration.

This project is currently a **work in progress**.

## Overview

A systolic array computes matrix multiplication ($C = A \times B$) by pipelining the data flow through a mesh of identically structured Processing Elements (PEs). In this design, matrix $A$ rows stream horizontally, matrix $B$ columns stream vertically, and partial sums accumulate within each PE or are passed along.

### Key Components

- **`systolic_array.sv`**: The top-level array module. It handles data buffering and the necessary time-skewing logic so that matrix elements arrive at the correct Processing Element at the right clock cycle. Features parameterized array dimension (`N`) and precision (`DATA_WIDTH`).
- **`multiply_accumulate_unit.sv`**: The core Processing Element (PE). It performs a synchronous multiply-accumulate operation (`acc_out <= acc_in + in_top * in_side`) and pass-through forwarding of the `top` and `side` data to adjacent PEs.
- **`uart_rx.sv`**: A 16x oversampled UART receiver state machine with a default BAUD rate of 115.2 kps. This module is intended to serve as the communication bridge, allowing a host PC to stream matrices to the FPGA/accelerator.

## Verification & Simulation

The project uses **Verilator** for simulation and linting.
Testbenches are located in the `tb/` directory:
- `tb_systolic_array.sv`: Defines a SystemVerilog `interface` (`sys_if`) and a basic object-oriented testbench scaffold (e.g., generator, mailbox) to drive the matrix inputs.
- `tb_uart_rx.sv`: Testbench for validating the UART receiver logic.

Other testbenches are expected to be added in the future.

The Verilator build configuration is specified in `verilator.f`, and past runs are avaliable in the `waveforms/` directory for debugging.

To run the UART testbench:
```
verilator -f verilator.f
./obj_dir/Vtb_uart_rx
```

## Parameterization

The core array can be configured at instantiation:
```systemverilog
Systolic_Array #(
  .N(8),               // Dimension of the NxN array
  .DATA_WIDTH(8)       // Bit-width for matrix inputs
) array_inst ( ... );
```
*Note: The accumulator width scales automatically to `2 * DATA_WIDTH` to prevent overflow during standard integer operations.*
