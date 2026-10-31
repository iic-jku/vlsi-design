// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Testbench of pulse_sync: one-cycle pulses from a
// 10 ns domain into a 14.3 ns domain, five cycles apart. Counts the
// pulses that arrive through pulse_sync and through a plain
// sync_2ff with an edge detector behind it.

`timescale 1ns / 1ps

module tb_pulse_sync;

  logic clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0, pulse_a = 1'b0;
  logic pulse_b, plain_b, plain_b_q = 1'b0;
  int   sent = 0, got = 0, got_plain = 0;

  pulse_sync dut (.clk_a_i(clk_a), .rst_a_ni(rst_n),
                  .pulse_a_i(pulse_a), .clk_b_i(clk_b),
                  .rst_b_ni(rst_n), .pulse_b_o(pulse_b));

  // The plain way: synchronize the pulse itself
  sync_2ff u_plain (.clk_i(clk_b), .rst_ni(rst_n), .d_i(pulse_a),
                    .q_o(plain_b));

  always #5    clk_a = ~clk_a;
  always #7.15 clk_b = ~clk_b;

  initial begin
    #23 rst_n = 1'b1;
    repeat (1000) begin
      @(posedge clk_a) pulse_a <= 1'b1;
      sent++;
      @(posedge clk_a) pulse_a <= 1'b0;
      repeat (3) @(posedge clk_a);
    end
    repeat (10) @(posedge clk_b);
    $display("%0d pulses sent, %0d through pulse_sync, %0d plain",
             sent, got, got_plain);
    $finish;
  end

  always @(posedge clk_b) begin
    if (pulse_b) got++;
    if (plain_b && !plain_b_q) got_plain++;
    plain_b_q <= plain_b;
  end

endmodule
