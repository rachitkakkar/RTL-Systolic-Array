# RTL-Systolic-Array

A parameterizable hardware implementation of a 2D Systolic Array in SystemVerilog, designed primarily for matrix multiplication acceleration.

This project features a high-performance **AXI4-Stream** instrumentation bridge to stream input matrices and extract the computed results efficiently. This specific protocol was chosen because it is non-memory mapped, which is ideal for this application (where matrix data is transmitted in bursts).

## Overview

A systolic array computes matrix multiplication ($C = A \times B$) by pipelining the data flow through a mesh of identically structured Processing Elements (PEs). Essentially, this turns matrix multiplication from $O(n^3)$ to $O(n)$ by rolling-out two dimensions into hardware. In this particular *output-stationary* design, matrix $A$ rows stream horizontally, matrix $B$ columns stream vertically, and partial sums accumulate within each PE or are passed along.

### Key Components

- **`systolic_array.sv`**: The top-level array module. It handles data buffering and the necessary time-skewing logic so that matrix elements arrive at the correct Processing Element at the right clock cycle. Features parameterized array dimension (`N`) and precision (`DATA_WIDTH`).
- **`multiply_accumulate_unit.sv`**: The core Processing Element (PE). It performs a synchronous multiply-accumulate operation (`acc_out <= acc_in + in_top * in_side`) and pass-through forwarding of the `top` and `side` data to adjacent PEs.
- **`instrumentation.sv`**: The top-level state machine. It implements an AXI4-Stream interface (Master and Slave) wrapping the systolic array. This state machine manages the streaming of Matrix A and Matrix B into internal buffers, handles the ready/valid handshakes, drives the array for computation, and streams the resulting Matrix C out.
- **`uart_rx.sv`** (unused): A 16x oversampled UART receiver state machine with a default BAUD rate of 115.2 kps. This module was originally intended to serve as the communication bridge, allowing a host PC to stream matrices to the FPGA/accelerator. However, I later switched to an AXI4-Stream interface to improve perfromance.

These components can be found in the `rtl` directory.

### Architecture

**Top-Level Block Diagram**

To come

**Controller FSM**

To come

## Verification & Simulation

### File Structure and Build Instructions

The project uses **Verilator** for simulation and linting.
Testbenches are located in the `tb/` directory:
- `tb_systolic_array.sv`: Defines a SystemVerilog `interface` (`sys_if`) and a basic object-oriented testbench scaffold (e.g., generator, mailbox) to drive the matrix inputs.
- `tb_instrumentation.sv`: The generator produces test matrices, the driver controls the AXI handshakes, and the scoreboard verifies the output against mathematical expectations.
- `tb_uart_rx.sv`: Testbench for validating the UART receiver logic.

Other testbenches are expected to be added in the future.

The Verilator build configuration is specified in `verilator.f`, and past runs are avaliable in the `waveforms/` directory for debugging.

**Note: The first two testbenches were developed with the help of AI assistance**

To run the instrumentation testbench:
```bash
verilator -f verilator.f
./obj_dir/Vtb_instrumentation
```

Everything has been tested on MacOS, but it should be cross-platform.

### Waveforms

**tb_instrumentation.sv**


**tb_uart_rx.sv (unused)**

![UART Testbench Waveform](waveforms/UART3.png)

### Scoreboard Console Result

**tb_instrumentation.sv**

**tb_systolic_array.sv**

**tb_uart_rx.sv (unused)**

## Parameterization

The core array and AXI bridge can be configured at instantiation:
```systemverilog
instrumentation #(
  .N(8),               // Dimension of the NxN array
  .DATA_WIDTH(8)       // Bit-width for matrix inputs
) inst_module ( ... );
```

*Note: The accumulator width automatically scales to `2 * DATA_WIDTH` to prevent overflow during standard integer operations, and the AXI data widths are derived directly from the array dimensions.*