// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Priority encoder with registered outputs in plain
// Verilog-2001. idx is the index of the lowest set bit of req,
// valid is high if any bit of req is set. This file contains a
// mistake on purpose (exercise), do not use it as a template.

module prio_enc (clk, rst_n, req, idx, valid);

  parameter N = 8;
  parameter W = 3;  // width of idx, must be log2(N)

  input          clk;
  input          rst_n;
  input  [N-1:0] req;
  output [W-1:0] idx;
  output         valid;

  reg    [W-1:0] idx;
  reg            valid;
  reg    [W-1:0] idx_next;
  wire           valid_next;
  integer        i;

  assign valid_next = |req;

  // The loop runs from the highest to the lowest bit, so the
  // lowest set bit is assigned last and wins.
  always @(*) begin
    for (i = N - 1; i >= 0; i = i - 1)
      if (req[i])
        idx_next = i;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      idx   <= {W{1'b0}};
      valid <= 1'b0;
    end else begin
      idx   <= idx_next;
      valid <= valid_next;
    end
  end

endmodule
