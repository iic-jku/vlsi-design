// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: A register with an enable. It loads data_i only in
// the cycles in which en_i is high, and keeps its value otherwise.

`default_nettype none

module cg_reg #(
  parameter int unsigned WIDTH = 32
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             en_i,
  input  logic [WIDTH-1:0] data_i,
  output logic [WIDTH-1:0] data_o
);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_o <= '0;
    end else if (en_i) begin
      data_o <= data_i;
    end
  end

endmodule

`default_nettype wire
