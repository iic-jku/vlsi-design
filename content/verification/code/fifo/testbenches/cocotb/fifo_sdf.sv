// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Wrapper for the timing simulation of the synthesized
// FIFO. Icarus Verilog annotates the cell delays of the SDF file that
// the plusarg +SDF=<file> names.

`default_nettype none

module fifo_sdf (
  input  wire       clk_i,
  input  wire       rst_ni,
  input  wire       push_i,
  input  wire [7:0] data_i,
  input  wire       pop_i,
  output wire [7:0] data_o,
  output wire       full_o,
  output wire       empty_o
);

  fifo u_fifo (.*);

  string sdf_file;

  initial begin
    if ($value$plusargs("SDF=%s", sdf_file)) begin
      $sdf_annotate(sdf_file, u_fifo);
    end
  end

endmodule

`default_nettype wire
