// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: LED blinker for an ASIC, with the same timing as
// led_blink_fpga: led_o toggles every 2*DIV clock cycles. A clock
// enable (tick) replaces the divided clock, and a reset replaces the
// initial values.

`default_nettype none

module led_blink #(
  parameter int unsigned DIV = 12_500_000
) (
  input  logic clk_i,
  input  logic rst_ni,
  output logic led_o
);

  localparam int unsigned      COUNT_WIDTH = $clog2(DIV);
  localparam [COUNT_WIDTH-1:0] COUNT_LAST  = COUNT_WIDTH'(DIV - 1);

  logic [COUNT_WIDTH-1:0] count_d, count_q;
  logic                   phase_d, phase_q;  // was slow_clk_q
  logic                   led_d, led_q;
  logic                   wrap, tick;

  // Register process: one clock, one reset for all registers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_q <= '0;
      phase_q <= 1'b0;
      led_q   <= 1'b0;
    end else begin
      count_q <= count_d;
      phase_q <= phase_d;
      led_q   <= led_d;
    end
  end

  // wrap: every DIV clock cycles. tick: where slow_clk_q of the FPGA
  // version would rise, a one-cycle enable instead of a clock edge
  assign wrap = (count_q == COUNT_LAST);
  assign tick = wrap & ~phase_q;

  // Combinational process: defaults first, then all decisions
  always_comb begin
    count_d = count_q + 1'b1;
    phase_d = phase_q;
    led_d   = led_q;
    if (wrap) begin
      count_d = '0;
      phase_d = ~phase_q;
    end
    if (tick) begin
      led_d = ~led_q;
    end
  end

  assign led_o = led_q;

endmodule

`default_nettype wire
