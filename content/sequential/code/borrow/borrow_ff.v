// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: The path of borrow_latch.v with a flip-flop on the
// falling clock edge instead of the latch.

module borrow_ff (
  input  clk_i,
  input  d_i,
  output q_o
);

  wire [6:0] a;
  wire [2:0] b;
  wire       clk_n;

  sg13cmos5l_dfrbpq_1 ff1 (.CLK(clk_i), .D(d_i), .RESET_B(1'b1),
    .Q(a[0]));
  sg13cmos5l_dlygate4sd3_1 da1 (.A(a[0]), .X(a[1]));
  sg13cmos5l_dlygate4sd3_1 da2 (.A(a[1]), .X(a[2]));
  sg13cmos5l_dlygate4sd3_1 da3 (.A(a[2]), .X(a[3]));
  sg13cmos5l_dlygate4sd3_1 da4 (.A(a[3]), .X(a[4]));
  sg13cmos5l_dlygate4sd3_1 da5 (.A(a[4]), .X(a[5]));
  sg13cmos5l_dlygate4sd3_1 da6 (.A(a[5]), .X(a[6]));

  sg13cmos5l_inv_1 ci (.A(clk_i), .Y(clk_n));
  sg13cmos5l_dfrbpq_1 mid (.CLK(clk_n), .D(a[6]), .RESET_B(1'b1),
    .Q(b[0]));

  sg13cmos5l_dlygate4sd3_1 db1 (.A(b[0]), .X(b[1]));
  sg13cmos5l_dlygate4sd3_1 db2 (.A(b[1]), .X(b[2]));
  sg13cmos5l_dfrbpq_1 ff2 (.CLK(clk_i), .D(b[2]), .RESET_B(1'b1),
    .Q(q_o));

endmodule
