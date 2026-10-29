// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Small ALU with a registered result (corrected version).

`default_nettype none

module lint_me (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic [1:0] op_i,
  input  logic [7:0] a_i,
  input  logic [7:0] b_i,
  output logic [7:0] result_o,
  output logic       zero_o
);

  logic [7:0] alu;
  logic [7:0] result_q;

  // Result register
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      result_q <= 8'h00;
    end else begin
      result_q <= alu;
    end
  end

  // ALU: 00 add, 01 subtract, 10 AND, 11 OR
  always_comb begin
    unique case (op_i)
      2'b00:   alu = a_i + b_i;
      2'b01:   alu = a_i - b_i;
      2'b10:   alu = a_i & b_i;
      default: alu = a_i | b_i;  // 2'b11
    endcase
  end

  assign result_o = result_q;
  assign zero_o   = (result_q == 8'h00);

endmodule

`default_nettype wire
