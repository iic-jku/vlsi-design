// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Two flip-flops in a row, as in a shift register. The
// clock reaches ff1 directly and ff2 through four buffers.

module shift (
  input  clk_i,
  input  d_i,
  output q_o
);

  wire q1, ck1, ck2, ck3, ck4;

  sg13cmos5l_dfrbpq_1 ff1 (.CLK(clk_i), .D(d_i), .RESET_B(1'b1),
    .Q(q1));

  // An unbalanced clock tree: four buffers to ff2
  sg13cmos5l_buf_1 cb1 (.A(clk_i), .X(ck1));
  sg13cmos5l_buf_1 cb2 (.A(ck1), .X(ck2));
  sg13cmos5l_buf_1 cb3 (.A(ck2), .X(ck3));
  sg13cmos5l_buf_1 cb4 (.A(ck3), .X(ck4));

  sg13cmos5l_dfrbpq_1 ff2 (.CLK(ck4), .D(q1), .RESET_B(1'b1),
    .Q(q_o));

endmodule
