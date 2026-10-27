// SPDX-FileCopyrightText: 2026 Simon Dorrer and Harald Pretl
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Description: This file implements an N-bit up counter with
// synchronous reset & enable in SystemVerilog (two-process style).

`default_nettype none
`ifndef __COUNTER__
`define __COUNTER__

module counter #(
  parameter int unsigned       CTR_BW  = 8,
  parameter logic [CTR_BW-1:0] CTR_MAX = 2**CTR_BW - 1
)(
  input logic               clock_i,
  input logic               reset_i,
  input logic               enable_i,

  output logic [CTR_BW-1:0] counter_value_o
);

  logic [CTR_BW-1:0] count_d, count_q;

  // Combinational process: next counter value, wraps around at CTR_MAX
  always_comb begin
    count_d = count_q;
    if (enable_i) begin
      if (count_q == CTR_MAX) begin
        count_d = '0;
      end else begin
        count_d = count_q + 1'b1;
      end
    end
  end

  // Register process: synchronous reset and copy of count_d only
  always_ff @(posedge clock_i) begin
    if (reset_i) begin
      count_q <= '0;
    end else begin
      count_q <= count_d;
    end
  end

  assign counter_value_o = count_q;

endmodule // counter

`endif
`default_nettype wire
