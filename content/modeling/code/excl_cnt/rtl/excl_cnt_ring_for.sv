// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Exclusive counter, architecture 2 written differently:
// a for loop instead of the concatenation, and the clear written last
// so that it overrides the rotation. Same function as excl_cnt_ring.

`default_nettype none

module excl_cnt_ring_for (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       clr_i,
  input  logic       en_i,
  output logic [7:0] q_o
);

  logic [7:0] q_d, q_q;

  // Register process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      q_q <= 8'b0000_0001;
    end else begin
      q_q <= q_d;
    end
  end

  // Combinational process: the last assignment wins, so clr_i has
  // priority although it is written after the rotation
  always_comb begin
    q_d = q_q;
    if (en_i) begin
      q_d[0] = q_q[7];
      for (int i = 1; i < 8; i++) begin
        q_d[i] = q_q[i-1];
      end
    end
    if (clr_i) begin
      q_d = 8'b0000_0001;
    end
  end

  assign q_o = q_q;

endmodule

`default_nettype wire
