// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: A netlist with a single flip-flop of SG13CMOS5L, to
// look at its timing parameters with OpenSTA.

module one_ff (
  input  clk_i,
  input  rst_ni,
  input  d_i,
  output q_o
);

  sg13cmos5l_dfrbpq_1 u1 (
    .CLK    (clk_i),
    .D      (d_i),
    .RESET_B(rst_ni),
    .Q      (q_o)
  );

endmodule
