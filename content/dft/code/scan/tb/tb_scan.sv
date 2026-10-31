// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Scan test of a netlist with the ports of bs_reg
// (WIDTH = 8) and one scan chain. The chain test shifts 0011...
// through the chain and checks what comes out. The scan test loads
// patterns, captures, and compares the unloaded responses with those
// of a fault-free copy of the same netlist. Defines: TOP (default
// bs_reg), LEN (chain length, default 21), PATTERNS (file of
// scan_patterns.py, default: random patterns), NPAT (number of
// patterns, default 32), TEST_MODE (the netlist has the input
// test_mode_i, held at 1), FAULT and SA (a net of the netlist and its
// stuck-at value).

`timescale 1ns / 1ps

`ifndef TOP
`define TOP bs_reg
`endif
`ifndef LEN
`define LEN 21
`endif
`ifndef NPAT
`define NPAT 32
`endif

module tb_scan;

  localparam int L    = `LEN;   // length of the scan chain
  localparam int NPAT = `NPAT;  // number of scan patterns

  logic          clk = 1'b0, rst_n = 1'b0, se = 1'b0, si = 1'b0;
  logic [7:0]    data = '0;
  logic [2:0]    shamt = '0;
  logic [1:0]    mode = '0;
  logic [7:0]    q, q_gold;
  logic          so, so_gold;
  logic [L+12:0] mem [NPAT];  // chain bits, data, shamt, mode
  int            chain_err = 0, scan_err = 0;

  `TOP dut (
    .clk_i(clk), .rst_ni(rst_n), .data_i(data), .shamt_i(shamt),
    .mode_i(mode), .data_o(q),
`ifdef TEST_MODE
    .test_mode_i(1'b1),
`endif
    .scan_enable_0(se), .scan_in_0(si), .scan_out_0(so)
  );

  `TOP gold (
    .clk_i(clk), .rst_ni(rst_n), .data_i(data), .shamt_i(shamt),
    .mode_i(mode), .data_o(q_gold),
`ifdef TEST_MODE
    .test_mode_i(1'b1),
`endif
    .scan_enable_0(se), .scan_in_0(si), .scan_out_0(so_gold)
  );

`ifdef FAULT
  initial force dut.`FAULT = `SA;  // the defect
`endif

  always #50 clk = ~clk;  // 10 MHz test clock

  // All inputs change and all outputs are compared at falling edges
  initial begin
`ifdef PATTERNS
    $readmemb(`PATTERNS, mem);
`else
    foreach (mem[p]) mem[p] = {$urandom, $urandom};
`endif
    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    // Chain test: bit i leaves the chain L cycles after it entered
    for (int i = 0; i < 2 * L; i++) begin
      @(negedge clk);
      se = 1'b1;
      if (i >= L && so !== ((i - L) % 4 >= 2)) chain_err++;
      si = (i % 4 >= 2);
    end

    // Scan test: load a pattern while the last response shifts out,
    // then one capture cycle with the inputs of the pattern
    for (int p = 0; p <= NPAT; p++) begin
      for (int i = 0; i < L; i++) begin
        @(negedge clk);
        se = 1'b1;
        if (p > 0 && so !== so_gold) scan_err++;
        if (p < NPAT) si = mem[p][L+12-i];
      end
      if (p < NPAT) begin
        @(negedge clk);
        se = 1'b0;
        {data, shamt, mode} = mem[p][12:0];
        #1 if (q !== q_gold) scan_err++;
      end
    end

    $display("chain test: %0d of %0d bits wrong", chain_err, L);
    $display("scan test: %0d patterns, %0d bits differ", NPAT,
             scan_err);
    $finish;
  end

endmodule
