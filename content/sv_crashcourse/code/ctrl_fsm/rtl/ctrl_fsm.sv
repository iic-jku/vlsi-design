// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Moore FSM of a simple controller. A start_i pulse
// moves it from idle to run (busy_o high) until last_i, then done_o
// is high for one clock cycle before the FSM returns to idle.

`default_nettype none

module ctrl_fsm (
  input  logic clk_i,
  input  logic rst_ni,
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

  // State register
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StIdle;
    end else begin
      state_q <= state_d;
    end
  end

endmodule

`default_nettype wire
