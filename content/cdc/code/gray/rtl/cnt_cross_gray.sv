// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: The counter of cnt_cross_bin, crossing in Gray code.
// Only one bit changes per count, so domain B sees either the old or
// the new value, never a mix.

`default_nettype none

module cnt_cross_gray #(
  parameter int unsigned W = 4
) (
  input  logic         clk_a_i,
  input  logic         rst_a_ni,
  input  logic         clk_b_i,
  input  logic         rst_b_ni,
  output logic [W-1:0] cnt_b_o
);

  logic [W-1:0] cnt_a_q, gray_a_q, gray_b;

  // Domain A: the counter and its Gray code in a register, so that
  // no logic glitch reaches the synchronizer
  always_ff @(posedge clk_a_i or negedge rst_a_ni) begin
    if (!rst_a_ni) begin
      cnt_a_q  <= '0;
      gray_a_q <= '0;
    end else begin
      cnt_a_q  <= cnt_a_q + 1'b1;
      gray_a_q <= cnt_a_q ^ (cnt_a_q >> 1);
    end
  end

  // Into domain B, then back to binary
  sync_2ff #(.WIDTH(W)) u_sync (
    .clk_i (clk_b_i),
    .rst_ni(rst_b_ni),
    .d_i   (gray_a_q),
    .q_o   (gray_b)
  );

  always_comb begin
    for (int i = 0; i < W; i++) begin
      cnt_b_o[i] = ^(gray_b >> i);
    end
  end

endmodule

`default_nettype wire
