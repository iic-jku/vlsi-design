// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: bs_reg of chapter 6 with a reset synchronizer: the
// registers see a reset that is released synchronously to clk_i.

`default_nettype none

module bs_reg_rs #(
  parameter int unsigned WIDTH = 32  // power of two
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic [WIDTH-1:0]         data_i,
  input  logic [$clog2(WIDTH)-1:0] shamt_i,
  input  logic [1:0]               mode_i,
  output logic [WIDTH-1:0]         data_o
);

  logic rst_n;

  rst_sync u_rst_sync (
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .rst_no(rst_n)
  );

  bs_reg #(.WIDTH(WIDTH)) u_bs_reg (
    .clk_i  (clk_i),
    .rst_ni (rst_n),
    .data_i (data_i),
    .shamt_i(shamt_i),
    .mode_i (mode_i),
    .data_o (data_o)
  );

endmodule

`default_nettype wire
