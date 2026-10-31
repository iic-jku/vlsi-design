// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Testbench of cnt_cross_bin and cnt_cross_gray with two
// unrelated clocks. Domain A counts every 10 ns, domain B samples
// every 13.7 ns, so its count must advance by 0 to 2 per cycle.
// DUT selects the module.

`timescale 1ns / 1ps
`ifndef DUT
  `define DUT cnt_cross_gray
`endif

module tb_cnt_cross;

  localparam int W = 4;

  logic         clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
  logic [W-1:0] cnt_b, prev;
  int           cycles = 0, errors = 0;

  `DUT #(.W(W)) dut (.clk_a_i(clk_a), .rst_a_ni(rst_n),
                     .clk_b_i(clk_b), .rst_b_ni(rst_n),
                     .cnt_b_o(cnt_b));

  always #5    clk_a = ~clk_a;
  always #6.85 clk_b = ~clk_b;

  initial begin
    #23 rst_n = 1'b1;
    @(posedge clk_b) prev = cnt_b;
    repeat (5000) begin
      @(posedge clk_b) #1;
      cycles++;
      if (W'(cnt_b - prev) > 2) begin
        errors++;
        if (errors <= 3)
          $display("%0.1f ns: count %0d after %0d", $realtime, cnt_b,
                   prev);
      end
      prev = cnt_b;
    end
    $display("%0d cycles of domain B, %0d errors", cycles, errors);
    $finish;
  end

endmodule
