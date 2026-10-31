// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: The barrel shifter of chapter 4 between an input and
// an output register, so that every path through it starts and ends
// at a flip-flop.

`default_nettype none

module bs_reg #(
  parameter int unsigned WIDTH = 32  // power of two
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic [WIDTH-1:0]         data_i,
  input  logic [$clog2(WIDTH)-1:0] shamt_i,
  input  logic [1:0]               mode_i,
  output logic [WIDTH-1:0]         data_o
);

  logic [WIDTH-1:0]         data_q, result, out_q;
  logic [$clog2(WIDTH)-1:0] shamt_q;
  logic [1:0]               mode_q;

  // Register process: the input and the output register
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_q  <= '0;
      shamt_q <= '0;
      mode_q  <= '0;
      out_q   <= '0;
    end else begin
      data_q  <= data_i;
      shamt_q <= shamt_i;
      mode_q  <= mode_i;
      out_q   <= result;
    end
  end

  barrel_shift #(.WIDTH(WIDTH)) u_shift (
    .data_i (data_q),
    .shamt_i(shamt_q),
    .mode_i (mode_q),
    .data_o (result)
  );

  assign data_o = out_q;

endmodule
