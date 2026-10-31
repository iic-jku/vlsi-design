// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: A counter in clock domain A, read in clock domain B
// through one synchronizer per bit. The binary count changes several
// bits at once, so domain B can see values the counter never had.

`default_nettype none

module cnt_cross_bin #(
  parameter int unsigned W = 4
) (
  input  logic         clk_a_i,
  input  logic         rst_a_ni,
  input  logic         clk_b_i,
  input  logic         rst_b_ni,
  output logic [W-1:0] cnt_b_o   // the count in domain B
);

  logic [W-1:0] cnt_a_q;

  // Domain A: the counter increments in every cycle
  always_ff @(posedge clk_a_i or negedge rst_a_ni) begin
    if (!rst_a_ni) begin
      cnt_a_q <= '0;
    end else begin
      cnt_a_q <= cnt_a_q + 1'b1;
    end
  end

  // Into domain B
  sync_2ff #(.WIDTH(W)) u_sync (
    .clk_i (clk_b_i),
    .rst_ni(rst_b_ni),
    .d_i   (cnt_a_q),
    .q_o   (cnt_b_o)
  );

endmodule

`default_nettype wire
