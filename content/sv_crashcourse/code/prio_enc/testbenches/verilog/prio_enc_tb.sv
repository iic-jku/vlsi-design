// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Self-checking SystemVerilog testbench for prio_enc. It
// applies all values of req and compares the outputs with a model.

`timescale 1ns / 1ps

module prio_enc_tb;

  localparam int unsigned N             = 8;
  localparam int unsigned W             = $clog2(N);
  localparam real         CLK_PERIOD_NS = 20.0;  // 50 MHz

  logic         clk   = 1'b0;
  logic         rst_n = 1'b0;  // reset is active from time 0
  logic [N-1:0] req   = '0;
  logic [W-1:0] idx;
  logic         valid;

  // Device under test (DUT)
  prio_enc #(
    .N(N)
  ) dut (
    .clk_i  (clk),
    .rst_ni (rst_n),
    .req_i  (req),
    .idx_o  (idx),
    .valid_o(valid)
  );

  // Reference model: the index of the lowest set bit
  function automatic logic [W-1:0] lowest_set_bit(input logic [N-1:0] r);
    for (int i = 0; i < N; i++) begin
      if (r[i]) return W'(i);
    end
    return '0;
  endfunction

  // Clock generation
  always #(CLK_PERIOD_NS / 2) clk = ~clk;

  // Stimulus and checks on the falling edge. The outputs are registered,
  // so they belong to the value of req applied one clock cycle earlier.
  // idx is only checked while valid is high.
  initial begin
    $dumpfile("prio_enc_tb.vcd");
    $dumpvars(0, prio_enc_tb);

    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    for (int r = 0; r < 2**N; r++) begin
      req = N'(r);
      @(negedge clk);
      if (valid !== (req != '0)) begin
        $fatal(1, "FAIL: req = %b, valid = %b", req, valid);
      end
      if (valid && idx !== lowest_set_bit(req)) begin
        $fatal(1, "FAIL: req = %b, idx = %0d", req, idx);
      end
    end

    $display("PASS: prio_enc_tb");
    $finish;
  end

endmodule
