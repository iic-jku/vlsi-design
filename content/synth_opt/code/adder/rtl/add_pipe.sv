// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: The adder of add_reg in two pipeline stages. Stage 1
// adds the lower halves, stage 2 the upper halves with the carry of
// stage 1. The sum appears one clock cycle later than in add_reg.

`default_nettype none

module add_pipe #(
  parameter int unsigned WIDTH = 32  // even
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [WIDTH-1:0] a_i,
  input  logic [WIDTH-1:0] b_i,
  output logic [WIDTH:0]   sum_o
);

  localparam int unsigned H = WIDTH / 2;

  logic [WIDTH-1:0] a_q, b_q;
  logic [H:0]       lo_q;            // lower sum and its carry
  logic [H-1:0]     a_hi_q, b_hi_q;  // upper halves, one stage later
  logic [H:0]       hi;

  // Register process: input register, pipeline register, output
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      a_q    <= '0;
      b_q    <= '0;
      lo_q   <= '0;
      a_hi_q <= '0;
      b_hi_q <= '0;
      sum_o  <= '0;
    end else begin
      a_q    <= a_i;
      b_q    <= b_i;
      lo_q   <= a_q[H-1:0] + b_q[H-1:0];
      a_hi_q <= a_q[WIDTH-1:H];
      b_hi_q <= b_q[WIDTH-1:H];
      sum_o  <= {hi, lo_q[H-1:0]};
    end
  end

  // Stage 2: the upper halves and the carry of the lower half
  assign hi = a_hi_q + b_hi_q + lo_q[H];

endmodule

`default_nettype wire
