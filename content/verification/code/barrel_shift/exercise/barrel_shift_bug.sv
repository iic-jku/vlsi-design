// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Barrel shifter with one bug, for the exercise. The
// ports and their function are those of rtl/barrel_shift.sv.

`default_nettype none

module barrel_shift_bug #(
  parameter int unsigned WIDTH = 8  // power of two
) (
  input  logic [WIDTH-1:0]         data_i,
  input  logic [$clog2(WIDTH)-1:0] shamt_i,
  input  logic [1:0]               mode_i,
  output logic [WIDTH-1:0]         data_o
);

  logic [2:0] sh;

  always_comb begin
    sh = shamt_i;
    case (mode_i)
      2'b00:   data_o = data_i << sh;
      2'b01:   data_o = data_i >> sh;
      2'b10:   data_o = (data_i << sh)
                      | (data_i >> (WIDTH - 32'(sh)));
      default: data_o = (data_i >> sh)
                      | (data_i << (WIDTH - 32'(sh)));
    endcase
  end

endmodule

`default_nettype wire
