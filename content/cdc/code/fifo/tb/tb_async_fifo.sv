// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Testbench of async_fifo with a 10 ns write and a
// 14.3 ns read clock. Random pushes and pops, a scoreboard checks
// that every popped word is the oldest pushed one.

`timescale 1ns / 1ps

module tb_async_fifo;

  logic       wclk = 1'b0, rclk = 1'b0, rst_n = 1'b0;
  logic       push = 1'b0, pop = 1'b0, full, empty;
  logic [7:0] wdata = '0, rdata, sb[$];
  int         pushed = 0, popped = 0, errors = 0;

  async_fifo #(.WIDTH(8), .DEPTH(4)) dut (
    .wclk_i(wclk), .wrst_ni(rst_n), .push_i(push), .data_i(wdata),
    .full_o(full), .rclk_i(rclk), .rrst_ni(rst_n), .pop_i(pop),
    .data_o(rdata), .empty_o(empty));

  always #5    wclk = ~wclk;
  always #7.15 rclk = ~rclk;

  // Write side: push random words, record the accepted ones
  always @(posedge wclk) begin
    if (rst_n && push && !full) begin
      sb.push_back(wdata);
      pushed++;
    end
    #1;
    push  = ($urandom_range(3) != 0);
    wdata = $urandom;
  end

  // Read side: pop at random, compare with the oldest pushed word
  always @(posedge rclk) begin
    if (rst_n && pop && !empty) begin
      if (sb.size() == 0 || rdata !== sb[0]) errors++;
      if (sb.size() != 0) void'(sb.pop_front());
      popped++;
    end
    #1;
    pop = ($urandom_range(3) != 0);
  end

  initial begin
    #23 rst_n = 1'b1;
    #200000;
    $display("%0d pushed, %0d popped, %0d errors", pushed, popped,
             errors);
    $finish;
  end

endmodule
