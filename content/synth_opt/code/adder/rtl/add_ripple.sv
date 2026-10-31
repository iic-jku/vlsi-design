// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: The adder of add_reg as a ripple-carry adder, written
// out as a chain of full adders.

`default_nettype none

module add_ripple #(
  parameter int unsigned WIDTH = 32
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [WIDTH-1:0] a_i,
  input  logic [WIDTH-1:0] b_i,
  output logic [WIDTH:0]   sum_o
);

  logic [WIDTH-1:0] a_q, b_q, s;
  logic [WIDTH:0]   c;  // c[i] is the carry into bit i

  // Register process: the input and the output register
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      a_q   <= '0;
      b_q   <= '0;
      sum_o <= '0;
    end else begin
      a_q   <= a_i;
      b_q   <= b_i;
      sum_o <= {c[WIDTH], s};
    end
  end

  // One full adder per bit, the carry ripples from bit 0 upwards
  assign c[0] = 1'b0;
  for (genvar i = 0; i < WIDTH; i++) begin : g_fa
    assign s[i]   = a_q[i] ^ b_q[i] ^ c[i];
    assign c[i+1] = (a_q[i] & b_q[i]) | (c[i] & (a_q[i] ^ b_q[i]));
  end

endmodule

`default_nettype wire
