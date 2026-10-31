// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Testbench of rst_sync. Asserts rst_ni between clock
// edges and releases it 0.2 ns before a rising edge, then checks
// when rst_no follows.

`timescale 1ns / 1ps

module tb_rst_sync;

  logic    clk = 1'b0, rst_n = 1'b1, rst_sync_n;
  realtime t_rel, t_out;
  int      errors = 0;

  rst_sync dut (.clk_i(clk), .rst_ni(rst_n), .rst_no(rst_sync_n));

  always #5 clk = ~clk;  // rising edges at 5, 15, 25, ... ns

  initial begin
    #42 rst_n = 1'b0;    // between two edges
    #0.1;
    if (rst_sync_n !== 1'b0) errors++;
    $display("%0.1f ns: rst_ni low, rst_no = %b", $realtime,
             rst_sync_n);
    #22.7 rst_n = 1'b1;  // 0.2 ns before the edge at 65 ns
    t_rel = $realtime;
    @(posedge rst_sync_n) t_out = $realtime;
    $display("%0.1f ns: rst_ni high, rst_no high at %0.1f ns", t_rel,
             t_out);
    if (t_out != 75.0) errors++;  // second rising edge after release
    $display("%0d errors", errors);
    $finish;
  end

endmodule
