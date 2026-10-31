// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Self-checking testbench of add_pipe: random operands
// in every cycle, and the sum must appear three clock edges later.

`timescale 1ns / 10ps

module tb_add_pipe;

  localparam int LAT = 3;  // clock edges from a_i, b_i to sum_o

  logic        clk = 1'b0, rst_n = 1'b0;
  logic [31:0] a = '0, b = '0;
  logic [32:0] sum, expected[$];
  int          errors = 0;

  add_pipe dut (.clk_i(clk), .rst_ni(rst_n), .a_i(a), .b_i(b),
                .sum_o(sum));

  always #2 clk = ~clk;

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    // the reset values before the first sum
    repeat (LAT) expected.push_back('0);
    for (int i = 0; i < 1000; i++) begin
      @(negedge clk);
      if (sum !== expected.pop_front()) errors++;
      a = $urandom;
      b = $urandom;
      if (i == 0) begin
        a = '1;  // the longest carry chain
        b = 32'd1;
      end
      expected.push_back(33'(a) + 33'(b));
    end
    $display("1000 sums, %0d errors", errors);
    $finish;
  end

endmodule
