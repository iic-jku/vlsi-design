// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Priority encoder with registered outputs. idx_o
// is the index of the lowest set bit of req_i, valid_o is high if
// any bit of req_i is set.

`default_nettype none

module prio_enc #(
  parameter int unsigned N = 8
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  logic [N-1:0]         req_i,
  output logic [$clog2(N)-1:0] idx_o,
  output logic                 valid_o
);

  localparam int unsigned W = $clog2(N);

  logic [W-1:0] idx_d, idx_q;
  logic         valid_d, valid_q;

  // Combinational process: defaults first, then all decisions
  always_comb begin
    idx_d   = '0;
    valid_d = |req_i;
    // The loop runs from the highest to the lowest bit, so the
    // lowest set bit is assigned last and wins.
    for (int i = N - 1; i >= 0; i--) begin
      if (req_i[i]) begin
        idx_d = W'(i);
      end
    end
  end

  // Register process: reset values and copies of the _d signals only
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      idx_q   <= '0;
      valid_q <= 1'b0;
    end else begin
      idx_q   <= idx_d;
      valid_q <= valid_d;
    end
  end

  assign idx_o   = idx_q;
  assign valid_o = valid_q;

endmodule

`default_nettype wire
