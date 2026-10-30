// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: LED blinker written with FPGA habits. With a 50 MHz
// clock and the default DIV, slow_clk_q runs at 2 Hz and led_o blinks
// at 1 Hz. Works on an FPGA, but is not ready for an ASIC.

`default_nettype none

module led_blink_fpga #(
  parameter int unsigned DIV = 12_500_000
) (
  input  logic clk_i,
  output logic led_o
);

  localparam int unsigned      COUNT_WIDTH = $clog2(DIV);
  localparam [COUNT_WIDTH-1:0] COUNT_LAST  = COUNT_WIDTH'(DIV - 1);

  logic [COUNT_WIDTH-1:0] count_q    = '0;
  logic                   slow_clk_q = 1'b0;
  logic                   led_q      = 1'b0;

  // Clock divider: slow_clk_q toggles every DIV clock cycles
  always_ff @(posedge clk_i) begin
    if (count_q == COUNT_LAST) begin
      count_q    <= '0;
      slow_clk_q <= ~slow_clk_q;
    end else begin
      count_q <= count_q + 1'b1;
    end
  end

  // The LED toggles at every rising edge of the divided clock
  always_ff @(posedge slow_clk_q) begin
    led_q <= ~led_q;
  end

  assign led_o = led_q;

endmodule

`default_nettype wire
