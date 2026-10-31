// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: The barrel shifter between two registers behind a
// reset synchronizer (bs_reg_rs), with a test mode: during the scan
// test, the registers take their reset directly from the pin rst_ni.

`default_nettype none

module bs_reg_rs_tm #(
  parameter int unsigned WIDTH = 32  // power of two
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic                     test_mode_i,  // 1 during the test
  input  logic [WIDTH-1:0]         data_i,
  input  logic [$clog2(WIDTH)-1:0] shamt_i,
  input  logic [1:0]               mode_i,
  output logic [WIDTH-1:0]         data_o
);

  logic rst_sync_n, rst_n;

  rst_sync u_rst_sync (
    .clk_i (clk_i),
    .rst_ni(rst_ni),
    .rst_no(rst_sync_n)
  );

  // In test mode, the tester controls the reset of the registers
  assign rst_n = test_mode_i ? rst_ni : rst_sync_n;

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
