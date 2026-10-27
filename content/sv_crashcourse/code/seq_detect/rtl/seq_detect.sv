// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Moore FSM that detects the bit pattern 1011 in the serial
// input bit_i (one bit per rising clock edge, overlapping occurrences count).
// detect_o is high for one cycle after the edge that sampled the last 1.

`default_nettype none

module seq_detect (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic bit_i,
  output logic detect_o
);

  // Each state names the longest matched prefix of 1011
  typedef enum logic [2:0] {
    StIdle,
    St1,
    St10,
    St101,
    St1011
  } state_e;

  state_e state_d, state_q;

  always_comb begin
    state_d  = state_q;
    detect_o = 1'b0;
    unique case (state_q)
      StIdle: begin
        if (bit_i) state_d = St1;
      end
      St1: begin
        if (!bit_i) state_d = St10;
      end
      St10: begin
        if (bit_i) state_d = St101;
        else       state_d = StIdle;
      end
      St101: begin
        if (bit_i) state_d = St1011;
        else       state_d = St10;
      end
      St1011: begin
        detect_o = 1'b1;
        if (bit_i) state_d = St1;
        else       state_d = St10;
      end
      default: state_d = StIdle;  // unused encodings
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StIdle;
    end else begin
      state_q <= state_d;
    end
  end

endmodule

`default_nettype wire
