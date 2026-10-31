// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Two 16-bit registers on one clock, the first behind an
// integrated clock gate, to show how clock tree synthesis balances
// the gated against the ungated flip-flops.

`default_nettype none

module cg_mix (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        en_i,
  input  logic [15:0] a_i,
  input  logic [15:0] b_i,
  output logic [15:0] a_o,
  output logic [15:0] b_o
);

  logic gclk;

  // Clock gate of the library, instantiated by hand
  sg13cmos5l_lgcp_1 u_icg (.CLK(clk_i), .GATE(en_i), .GCLK(gclk));

  // Register process: a_o behind the clock gate, b_o on clk_i
  always_ff @(posedge gclk or negedge rst_ni) begin
    if (!rst_ni) a_o <= '0;
    else         a_o <= a_i;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) b_o <= '0;
    else         b_o <= b_i;
  end

endmodule

`default_nettype wire
