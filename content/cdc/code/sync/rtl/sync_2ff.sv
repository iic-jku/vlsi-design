// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Two-flip-flop synchronizer. Brings WIDTH independent
// single-bit signals from another clock domain into the domain of
// clk_i. Each bit may arrive one cycle later than the others, so a
// bus must change only one bit at a time (Gray code).

`default_nettype none

module sync_2ff #(
  parameter int unsigned WIDTH = 1
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [WIDTH-1:0] d_i,   // from the other clock domain
  output logic [WIDTH-1:0] q_o
);

  logic [WIDTH-1:0] meta_q;  // may be metastable, never use it

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      meta_q <= '0;
      q_o    <= '0;
    end else begin
      meta_q <= d_i;
      q_o    <= meta_q;
    end
  end

endmodule

`default_nettype wire
