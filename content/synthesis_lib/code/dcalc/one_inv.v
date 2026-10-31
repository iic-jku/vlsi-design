// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: A netlist with a single inverter of SG13CMOS5L, to
// look at its delay calculation with OpenSTA.

module one_inv (
  input  a,
  output y
);

  sg13cmos5l_inv_1 u1 (.A(a), .Y(y));

endmodule
