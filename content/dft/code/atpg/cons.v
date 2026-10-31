// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: A small gate-level netlist of SG13CMOS5L cells for
// test generation by hand. Fault needs a clock and a reset input, so
// the netlist has two that nothing uses.

module cons (
  input  wire clk_i,   // unused
  input  wire rst_ni,  // unused
  input  wire a_i,
  input  wire b_i,
  input  wire c_i,
  output wire y_o
);

  wire a_n, ab, anc, bc;

  sg13cmos5l_inv_1  u_inv (.A(a_i), .Y(a_n));
  sg13cmos5l_and2_1 u_ab  (.A(a_i), .B(b_i), .X(ab));
  sg13cmos5l_and2_1 u_anc (.A(a_n), .B(c_i), .X(anc));
  sg13cmos5l_and2_1 u_bc  (.A(b_i), .B(c_i), .X(bc));
  sg13cmos5l_or3_1  u_or  (.A(ab), .B(anc), .C(bc), .X(y_o));

endmodule
