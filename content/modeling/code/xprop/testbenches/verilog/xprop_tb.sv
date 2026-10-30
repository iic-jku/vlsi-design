// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Three ways to describe a 2:1 multiplexer, plus an AND
// gate, simulated with an unknown select. Shows how if, case, ?:, and
// & treat x.

`timescale 1ns / 1ps

module xprop_tb;

  logic sel, a, b;
  logic y_if, y_case, y_cond, y_and;

  always_comb begin
    if (sel) y_if = b;
    else     y_if = a;
  end

  always_comb begin
    case (sel)
      1'b0:    y_case = a;
      1'b1:    y_case = b;
      default: y_case = 1'bx;  // only for this demonstration
    endcase
  end

  assign y_cond = sel ? b : a;
  assign y_and  = sel & a;

  initial begin
    sel = 1'bx;
    {a, b} = 2'b01;
    #1 $display("sel=x a=0 b=1: if=%b case=%b ?:=%b and=%b",
                y_if, y_case, y_cond, y_and);
    {a, b} = 2'b11;
    #1 $display("sel=x a=1 b=1: if=%b case=%b ?:=%b and=%b",
                y_if, y_case, y_cond, y_and);
    $finish;
  end

endmodule
