// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Two products, of which sel_i selects one. The two
// multiplications are never needed in the same cycle.

`default_nettype none

module mul_sel (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        sel_i,
  input  logic [15:0] a_i,
  input  logic [15:0] b_i,
  input  logic [15:0] c_i,
  input  logic [15:0] d_i,
  output logic [31:0] p_o
);

  logic        sel_q;
  logic [15:0] a_q, b_q, c_q, d_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sel_q <= 1'b0;
      a_q   <= '0;
      b_q   <= '0;
      c_q   <= '0;
      d_q   <= '0;
      p_o   <= '0;
    end else begin
      sel_q <= sel_i;
      a_q   <= a_i;
      b_q   <= b_i;
      c_q   <= c_i;
      d_q   <= d_i;
      p_o   <= sel_q ? a_q * b_q : c_q * d_q;
    end
  end

endmodule

`default_nettype wire
