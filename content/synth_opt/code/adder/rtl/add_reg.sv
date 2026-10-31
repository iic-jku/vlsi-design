// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: An adder between an input and an output register. The
// operator + leaves the adder architecture to the synthesis tool.

`default_nettype none

module add_reg #(
  parameter int unsigned WIDTH = 32
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [WIDTH-1:0] a_i,
  input  logic [WIDTH-1:0] b_i,
  output logic [WIDTH:0]   sum_o
);

  logic [WIDTH-1:0] a_q, b_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      a_q   <= '0;
      b_q   <= '0;
      sum_o <= '0;
    end else begin
      a_q   <= a_i;
      b_q   <= b_i;
      sum_o <= a_q + b_q;
    end
  end

endmodule

`default_nettype wire
