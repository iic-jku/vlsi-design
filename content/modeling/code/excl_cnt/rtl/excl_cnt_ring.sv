// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Exclusive counter, architecture 2: a one-hot ring of
// eight flip-flops, same behavior as excl_cnt_bin. clr_i
// (synchronous, priority over en_i) and the reset select q_o[0], en_i
// rotates the high bit up by one and wraps from q_o[7] to q_o[0].

`default_nettype none

module excl_cnt_ring (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       clr_i,
  input  logic       en_i,
  output logic [7:0] q_o
);

  logic [7:0] q_d, q_q;

  // Register process: the reset value is the first one-hot code
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      q_q <= 8'b0000_0001;
    end else begin
      q_q <= q_d;
    end
  end

  // Combinational process: rotate left by one bit
  always_comb begin
    q_d = q_q;
    if (clr_i) begin
      q_d = 8'b0000_0001;
    end else if (en_i) begin
      q_d = {q_q[6:0], q_q[7]};
    end
  end

  // The outputs come directly from the flip-flops
  assign q_o = q_q;

endmodule

`default_nettype wire
