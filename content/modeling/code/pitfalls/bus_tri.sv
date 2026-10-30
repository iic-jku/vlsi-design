// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: An internal tri-state bus with two drivers, an FPGA
// and board-level habit. Do not use this on chip, write a
// multiplexer.

`default_nettype none

module bus_tri (
  input  logic       sel_a_i,
  input  logic [7:0] a_i,
  input  logic [7:0] b_i,
  output logic [7:0] y_o
);

  tri [7:0] bus;

  assign bus = sel_a_i  ? a_i : 8'bz;  // driver A
  assign bus = !sel_a_i ? b_i : 8'bz;  // driver B
  assign y_o = bus;

endmodule

`default_nettype wire
