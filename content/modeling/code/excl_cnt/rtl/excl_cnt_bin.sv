// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Exclusive counter, architecture 1: a 3-bit binary
// counter and a decoder. Exactly one of the eight bits of q_o is
// high. clr_i (synchronous, priority over en_i) and the reset select
// q_o[0], en_i moves the high bit up by one and wraps from q_o[7] to
// q_o[0].

`default_nettype none

module excl_cnt_bin (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       clr_i,
  input  logic       en_i,
  output logic [7:0] q_o
);

  logic [2:0] cnt_d, cnt_q;

  // Register process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cnt_q <= '0;
    end else begin
      cnt_q <= cnt_d;
    end
  end

  // Combinational process: the 3-bit counter wraps by itself
  always_comb begin
    cnt_d = cnt_q;
    if (clr_i) begin
      cnt_d = '0;
    end else if (en_i) begin
      cnt_d = cnt_q + 3'd1;
    end
  end

  // Decoder: the outputs come from combinational logic
  assign q_o = 8'b0000_0001 << cnt_q;

endmodule

`default_nettype wire
