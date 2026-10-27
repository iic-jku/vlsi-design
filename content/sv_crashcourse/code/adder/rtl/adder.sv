// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Unsigned adder with a parameterized width and a carry bit.

`default_nettype none

module adder #(
  parameter int unsigned WIDTH = 8
) (
  input  logic [WIDTH-1:0] a_i,
  input  logic [WIDTH-1:0] b_i,
  output logic [WIDTH:0]   sum_o
);

  assign sum_o = {1'b0, a_i} + {1'b0, b_i};

endmodule

`default_nettype wire
