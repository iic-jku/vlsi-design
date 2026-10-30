// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Single-port memory with synchronous write and read,
// written as an array. On an FPGA, this infers a block RAM. On an
// ASIC, Yosys builds it from flip-flops and multiplexers.

`default_nettype none

module ram_ff #(
  parameter int unsigned DEPTH = 256,
  parameter int unsigned WIDTH = 8
) (
  input  logic                     clk_i,
  input  logic                     we_i,
  input  logic [$clog2(DEPTH)-1:0] addr_i,
  input  logic [WIDTH-1:0]         wdata_i,
  output logic [WIDTH-1:0]         rdata_o
);

  logic [WIDTH-1:0] mem_q [DEPTH];

  // No reset: the content of a memory is undefined after power-up
  always_ff @(posedge clk_i) begin
    if (we_i) begin
      mem_q[addr_i] <= wdata_i;
    end
    rdata_o <= mem_q[addr_i];
  end

endmodule

`default_nettype wire
