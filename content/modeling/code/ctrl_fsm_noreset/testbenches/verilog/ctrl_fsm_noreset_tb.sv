// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Prints the first eight clock cycles of
// ctrl_fsm_noreset. start_i is high in cycle 2 and last_i in cycle 4.
// Compile with -DGL for the gate-level netlist, which has no state_q
// to print.

`timescale 1ns / 1ps

module ctrl_fsm_noreset_tb;

  localparam real CLK_PERIOD_NS = 20.0;  // 50 MHz

  // Clock starts high: cycle 0 is printed before any rising edge
  logic clk   = 1'b1;
  logic start = 1'b0;
  logic last  = 1'b0;
  logic busy, done;

  // Device under test (DUT), no reset input
  ctrl_fsm_noreset dut (
    .clk_i  (clk),
    .start_i(start),
    .last_i (last),
    .busy_o (busy),
    .done_o (done)
  );

  always #(CLK_PERIOD_NS / 2) clk = ~clk;

  // Inputs change and outputs are printed on the falling edge
  initial begin
    for (int cycle = 0; cycle < 8; cycle++) begin
      @(negedge clk);
      start = (cycle == 2);
      last  = (cycle == 4);
`ifdef GL
      $display("cycle %0d: busy_o=%b done_o=%b", cycle, busy, done);
`else
      $display("cycle %0d: state_q=%b busy_o=%b done_o=%b",
               cycle, dut.state_q, busy, done);
`endif
    end
    $finish;
  end

endmodule
