// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Tick generator in the two-process style. While en_i is high,
// tick_o is high for one clock cycle every DIV clock cycles (DIV >= 2).

`default_nettype none

module tick_gen #(
  parameter int unsigned DIV = 10
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic en_i,
  output logic tick_o
);

  localparam int unsigned      COUNT_WIDTH = $clog2(DIV);
  localparam [COUNT_WIDTH-1:0] COUNT_LAST  = COUNT_WIDTH'(DIV - 1);

  logic [COUNT_WIDTH-1:0] count_d, count_q;
  logic                   tick_d, tick_q;

  // Combinational process: defaults first, then all decisions
  always_comb begin
    count_d = count_q;
    tick_d  = 1'b0;
    if (en_i) begin
      if (count_q == COUNT_LAST) begin
        count_d = '0;
        tick_d  = 1'b1;
      end else begin
        count_d = count_q + 1'b1;
      end
    end
  end

  // Register process: reset values and copies of the _d signals only
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_q <= '0;
      tick_q  <= 1'b0;
    end else begin
      count_q <= count_d;
      tick_q  <= tick_d;
    end
  end

  assign tick_o = tick_q;

endmodule

`default_nettype wire
