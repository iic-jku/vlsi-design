// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Self-checking SystemVerilog testbench for pwm,
// testing all duty values of a 4-bit PWM.

`timescale 1ns / 1ps

module pwm_tb;

  localparam int unsigned WIDTH         = 4;
  localparam int unsigned PERIOD        = 2 ** WIDTH;
  localparam real         CLK_PERIOD_NS = 20.0;  // 50 MHz

  logic             clk   = 1'b0;
  logic             rst_n = 1'b0;
  logic [WIDTH-1:0] duty  = '0;
  logic             pwm_out;
  int unsigned      high_cycles;

  pwm #(
    .WIDTH(WIDTH)
  ) dut (
    .clk_i (clk),
    .rst_ni(rst_n),
    .duty_i(duty),
    .pwm_o (pwm_out)
  );

  always #(CLK_PERIOD_NS / 2) clk = ~clk;

  initial begin
    $dumpfile("pwm_tb.vcd");
    $dumpvars(0, pwm_tb);

    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    for (int d = 0; d < PERIOD; d++) begin
      duty = WIDTH'(d);
      repeat (2) @(negedge clk);  // the new duty reaches pwm_o

      // Any PERIOD consecutive cycles contain exactly d high cycles
      high_cycles = 0;
      repeat (PERIOD) begin
        @(negedge clk);
        if ($isunknown(pwm_out)) $fatal(1, "FAIL: pwm_o is X or Z");
        if (pwm_out) high_cycles++;
      end
      if (high_cycles != d) begin
        $fatal(1, "FAIL: duty %0d gives %0d high cycles", d,
               high_cycles);
      end
    end

    $display("PASS: pwm_tb");
    $finish;
  end

endmodule
