// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: PWM generator. In every period of 2**WIDTH clock cycles,
// pwm_o is high for exactly duty_i cycles (duty_i = 0 keeps it low).

`default_nettype none

module pwm #(
  parameter int unsigned WIDTH = 8
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [WIDTH-1:0] duty_i,
  output logic             pwm_o
);

  logic [WIDTH-1:0] count_d, count_q;
  logic             pwm_d, pwm_q;

  always_comb begin
    count_d = count_q + 1'b1;  // wraps from 2**WIDTH - 1 to 0
    pwm_d   = (count_q < duty_i);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_q <= '0;
      pwm_q   <= 1'b0;
    end else begin
      count_q <= count_d;
      pwm_q   <= pwm_d;
    end
  end

  // Registered output: no glitches on the way to a pad
  assign pwm_o = pwm_q;

endmodule

`default_nettype wire
