// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Testbench of the netlist of cg_reg for the power
// analysis. New random data in every cycle, en_i high in one of
// EVERY cycles. Writes the activity of the netlist to cg_reg.vcd.

`timescale 1ns / 10ps

module tb_cg_reg;

  parameter int EVERY  = 16;    // en_i is high in 1 of EVERY cycles
  parameter int CYCLES = 1600;  // simulated clock cycles

  logic        clk = 1'b0, rst_n = 1'b0, en = 1'b0;
  logic [31:0] data = '0, q, model = '0;
  int          errors = 0;

  cg_reg dut (.clk_i(clk), .rst_ni(rst_n), .en_i(en),
              .data_i(data), .data_o(q));

  always #2 clk = ~clk;  // 4 ns, 250 MHz

  initial begin
    $dumpfile("cg_reg.vcd");
    $dumpvars(0, dut);
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    for (int i = 0; i < CYCLES; i++) begin
      @(negedge clk);
      data = $urandom;
      en   = (i % EVERY == 0);
      @(posedge clk);
      if (en) model = data;
      #1;
      if (q !== model) errors++;
    end
    $display("%0d cycles, en_i in 1 of %0d, %0d errors",
             CYCLES, EVERY, errors);
    $finish;
  end

endmodule
