// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Mealy FSM of the simple controller. A start_i pulse
// moves it from idle to run (busy_o high). done_o is high in the
// clock cycle in which last_i is high, then the FSM returns to idle.

`default_nettype none

module ctrl_fsm_mealy (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic start_i,
  input  logic last_i,
  output logic busy_o,
  output logic done_o
);

  typedef enum logic {
    StIdle,
    StRun
  } state_e;

  state_e state_d, state_q;

  // State register
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StIdle;
    end else begin
      state_q <= state_d;
    end
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
        if (last_i) begin
          done_o  = 1'b1;  // depends on an input: Mealy output
          state_d = StIdle;
        end
      end
      default: state_d = StIdle;
    endcase
  end

endmodule

`default_nettype wire
