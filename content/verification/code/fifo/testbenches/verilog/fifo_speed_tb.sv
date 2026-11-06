// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Runs the same stimulus in every simulator, to compare
// their speed. A xorshift generator drives the FIFO for +CYCLES=<n>
// clock cycles, because $urandom differs between the simulators. A
// reference model checks the outputs, and a checksum shows that two
// runs saw the same stimulus. COPIES adds FIFOs for a larger design,
// and -DDUT=fifo_sdf selects the timing simulation.

`timescale 1ns / 1ps

`ifndef DUT
  `define DUT fifo
`endif

module fifo_speed_tb #(
  parameter int unsigned COPIES = 1
);

  localparam real         CLK_PERIOD_NS = 20.0;  // 50 MHz
  localparam int unsigned DEPTH         = 4;

  logic              clk   = 1'b0;
  logic              rst_n = 1'b0;
  logic              push  = 1'b0;
  logic              pop   = 1'b0;
  logic [7:0]        din   = 8'h00;
  logic [31:0]       x     = 32'h2545F491;
  wire  [7:0]        dout;
  wire               full, empty;
  wire  [COPIES-1:0] parity;

  // Device under test (DUT)
  `DUT dut (
    .clk_i  (clk),
    .rst_ni (rst_n),
    .push_i (push),
    .data_i (din),
    .pop_i  (pop),
    .data_o (dout),
    .full_o (full),
    .empty_o(empty)
  );

  assign parity[0] = ^{dout, full, empty};

  // Every copy has its own stimulus, and its outputs reach the
  // checksum, so that no simulator can drop the copy.
  for (genvar g = 1; g < COPIES; g++) begin : gen_copy
    localparam int unsigned R = (g % 31) + 1;
    wire [31:0] xr = {x[R-1:0], x[31:R]} ^ 32'(g);
    wire [7:0]  dout_c;
    wire        full_c, empty_c;

    fifo u_copy (
      .clk_i  (clk),
      .rst_ni (rst_n),
      .push_i (xr[0]),
      .data_i (xr[15:8]),
      .pop_i  (xr[1]),
      .data_o (dout_c),
      .full_o (full_c),
      .empty_o(empty_c)
    );

    assign parity[g] = ^{dout_c, full_c, empty_c};
  end

  always #(CLK_PERIOD_NS / 2) clk = ~clk;

  // Reference model
  logic [7:0]  model [DEPTH];
  int unsigned wr = 0, rd = 0, n = 0;
  int unsigned cycles = 0, pops = 0, sum = 0;
  logic        do_push, do_pop;

  initial begin
    if (!$value$plusargs("CYCLES=%d", cycles)) cycles = 1000000;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    // Inputs change and outputs are checked on the falling edge
    for (int unsigned i = 0; i < cycles; i++) begin
      @(negedge clk);
      if (empty !== (n == 0) || full !== (n == DEPTH)) begin
        $fatal(1, "cycle %0d: wrong flags", i);
      end
      if (n != 0 && dout !== model[rd]) begin
        $fatal(1, "cycle %0d: data_o = %h", i, dout);
      end
      // The storage of every FIFO is written after 1000 cycles, and
      // only then does Icarus Verilog show no x in the parity
      if (i >= 1000) sum = (sum * 31) + 32'(^parity);
      x    = x ^ (x << 13);
      x    = x ^ (x >> 17);
      x    = x ^ (x << 5);
      push = x[0];
      pop  = x[1];
      din  = x[15:8];
      // What the next rising edge does, decided from the old state
      do_push = push && (n != DEPTH);
      do_pop  = pop && (n != 0);
      if (do_pop) begin
        sum  = (sum * 31) + 32'(model[rd]);
        pops = pops + 1;
        rd   = (rd + 1) % DEPTH;
        n    = n - 1;
      end
      if (do_push) begin
        model[wr] = din;
        wr        = (wr + 1) % DEPTH;
        n         = n + 1;
      end
    end
    $display("cycles=%0d pops=%0d checksum=%h", cycles, pops, sum);
    $finish;
  end

endmodule
