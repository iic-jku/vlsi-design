// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: The controller FSM of chapter 2 (ctrl_fsm) with the
// reset removed from its state register, to show how a missing reset
// hides in RTL simulation. Do not copy this into a real design.

`default_nettype none

module ctrl_fsm_noreset (
  input  logic clk_i,
  input  logic start_i,
  input  logic last_i,
  output logic busy_o,
  output logic done_o
);

  typedef enum logic [1:0] {
    StIdle,
    StRun,
    StDone
  } state_e;

  state_e state_d, state_q;

  // State register without a reset: its start value is unknown
  always_ff @(posedge clk_i) begin
    state_q <= state_d;
  end

  // Next-state and output logic, defaults first
  always_comb begin
    state_d = state_q;
    busy_o  = 1'b0;
    done_o  = 1'b0;
    unique case (state_q)
      StIdle: begin
        if (start_i) state_d = StRun;
      end
      StRun: begin
        busy_o = 1'b1;
        if (last_i) state_d = StDone;
      end
      StDone: begin
        done_o  = 1'b1;
        state_d = StIdle;
      end
      default: state_d = StIdle;  // unused encoding 2'b11
    endcase
  end

endmodule

`default_nettype wire
