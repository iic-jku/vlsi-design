// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: A 16-bit register on a clock that a flip-flop divides
// from clk_i by two, fed by a register on clk_i, to show that clock
// tree synthesis does not balance a divided clock against its source.

`default_nettype none

module div_mix (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [15:0] a_i,
  output logic [15:0] a_o,
  output logic [15:0] b_o
);

  logic        div_q;
  logic [15:0] a_q;

  // Divider: div_q toggles on every rising edge of clk_i
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) div_q <= 1'b0;
    else         div_q <= ~div_q;
  end

  // Register process: a_q on clk_i, b_o on the divided clock
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) a_q <= '0;
    else         a_q <= a_i;
  end

  always_ff @(posedge div_q or negedge rst_ni) begin
    if (!rst_ni) b_o <= '0;
    else         b_o <= a_q;
  end

  assign a_o = a_q;

endmodule

`default_nettype wire
