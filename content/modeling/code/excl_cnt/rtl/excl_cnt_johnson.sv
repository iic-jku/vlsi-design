// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Exclusive counter, architecture 3: a 4-bit Johnson
// counter (twisted ring) and a decoder of 2-input gates, same
// behavior as excl_cnt_bin. The Johnson counter passes through the
// eight states 0000, 0001, 0011, 0111, 1111, 1110, 1100, 1000.

`default_nettype none

module excl_cnt_johnson (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       clr_i,
  input  logic       en_i,
  output logic [7:0] q_o
);

  logic [3:0] s_d, s_q;

  // Register process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      s_q <= '0;
    end else begin
      s_q <= s_d;
    end
  end

  // Combinational process: shift left, feed back the inverted MSB
  always_comb begin
    s_d = s_q;
    if (clr_i) begin
      s_d = '0;
    end else if (en_i) begin
      s_d = {s_q[2:0], ~s_q[3]};
    end
  end

  // Decoder: every state differs from its neighbors in one bit, so
  // two adjacent bits identify it
  assign q_o[0] = ~s_q[3] & ~s_q[0];  // 0000
  assign q_o[1] =  s_q[0] & ~s_q[1];  // 0001
  assign q_o[2] =  s_q[1] & ~s_q[2];  // 0011
  assign q_o[3] =  s_q[2] & ~s_q[3];  // 0111
  assign q_o[4] =  s_q[3] &  s_q[0];  // 1111
  assign q_o[5] =  s_q[1] & ~s_q[0];  // 1110
  assign q_o[6] =  s_q[2] & ~s_q[1];  // 1100
  assign q_o[7] =  s_q[3] & ~s_q[2];  // 1000

endmodule

`default_nettype wire
