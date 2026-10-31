// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Reset synchronizer. Asserts the reset of a clock
// domain at once, asynchronously, and releases it synchronously, two
// or, if the first flip-flop resolves late, three rising edges of
// clk_i after rst_ni rises.

`default_nettype none

module rst_sync (
  input  logic clk_i,
  input  logic rst_ni,  // asynchronous reset, e.g., from a pad
  output logic rst_no   // reset of the clock domain of clk_i
);

  logic meta_q;  // may be metastable after the release

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      meta_q <= 1'b0;
      rst_no <= 1'b0;
    end else begin
      meta_q <= 1'b1;
      rst_no <= meta_q;
    end
  end

endmodule

`default_nettype wire
