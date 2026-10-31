// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Pulse synchronizer. A one-cycle pulse in domain A
// toggles a level, the level crosses through sync_2ff, and a change
// of the level gives a one-cycle pulse in domain B. Two pulses in A
// must be more than about 1.5 periods of clk_b_i apart.

`default_nettype none

module pulse_sync (
  input  logic clk_a_i,
  input  logic rst_a_ni,
  input  logic pulse_a_i,  // one-cycle pulses in domain A
  input  logic clk_b_i,
  input  logic rst_b_ni,
  output logic pulse_b_o   // one-cycle pulses in domain B
);

  logic tgl_a_q, tgl_b, tgl_b_q;

  // Domain A: every pulse toggles the level
  always_ff @(posedge clk_a_i or negedge rst_a_ni) begin
    if (!rst_a_ni) begin
      tgl_a_q <= 1'b0;
    end else if (pulse_a_i) begin
      tgl_a_q <= ~tgl_a_q;
    end
  end

  sync_2ff u_sync (
    .clk_i (clk_b_i),
    .rst_ni(rst_b_ni),
    .d_i   (tgl_a_q),
    .q_o   (tgl_b)
  );

  // Domain B: every change of the level is a pulse
  always_ff @(posedge clk_b_i or negedge rst_b_ni) begin
    if (!rst_b_ni) begin
      tgl_b_q <= 1'b0;
    end else begin
      tgl_b_q <= tgl_b;
    end
  end

  assign pulse_b_o = tgl_b ^ tgl_b_q;

endmodule

`default_nettype wire
