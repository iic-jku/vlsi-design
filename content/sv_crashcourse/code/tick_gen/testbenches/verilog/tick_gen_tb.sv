// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Self-checking SystemVerilog testbench for tick_gen.

`timescale 1ns / 1ps

module tick_gen_tb;

  localparam int unsigned DIV           = 5;
  localparam real         CLK_PERIOD_NS = 20.0;  // 50 MHz

  logic clk   = 1'b0;
  logic rst_n = 1'b0;  // reset is active from time 0
  logic en    = 1'b0;
  logic tick;

  // Device under test (DUT)
  tick_gen #(
    .DIV(DIV)
  ) dut (
    .clk_i (clk),
    .rst_ni(rst_n),
    .en_i  (en),
    .tick_o(tick)
  );

  // Clock generation
  always #(CLK_PERIOD_NS / 2) clk = ~clk;

  // Stimulus and checks. Inputs change and outputs are sampled on the falling
  // edge, so they never race with the rising edge on which the DUT acts.
  initial begin
    $dumpfile("tick_gen_tb.vcd");
    $dumpvars(0, tick_gen_tb);

    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    // Disabled: no tick at all
    repeat (3 * DIV) begin
      @(negedge clk);
      if (tick !== 1'b0) $fatal(1, "FAIL: tick while disabled");
    end

    // Enabled: exactly one tick every DIV clock cycles
    en = 1'b1;
    for (int cycle = 1; cycle <= 4 * DIV; cycle++) begin
      @(negedge clk);
      if (tick !== (cycle % DIV == 0)) begin
        $fatal(1, "FAIL: cycle %0d, tick = %b", cycle, tick);
      end
    end

    $display("PASS: tick_gen_tb");
    $finish;
  end

endmodule
