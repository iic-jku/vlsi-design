// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Combinational barrel shifter. mode_i selects shift
// left (00), shift right (01), rotate left (10), or rotate right
// (11) of data_i by shamt_i bit positions.

`default_nettype none

module barrel_shift #(
  parameter int unsigned WIDTH = 8  // power of two
) (
  input  logic [WIDTH-1:0]         data_i,
  input  logic [$clog2(WIDTH)-1:0] shamt_i,
  input  logic [1:0]               mode_i,
  output logic [WIDTH-1:0]         data_o
);

  // A rotation ORs back the bits that the shift moves out. For
  // shamt_i = 0, the shift by WIDTH gives 0.
  always_comb begin
    case (mode_i)
      2'b00:   data_o = data_i << shamt_i;
      2'b01:   data_o = data_i >> shamt_i;
      2'b10:   data_o = (data_i << shamt_i)
                      | (data_i >> (WIDTH - 32'(shamt_i)));
      default: data_o = (data_i >> shamt_i)
                      | (data_i << (WIDTH - 32'(shamt_i)));
    endcase
  end

endmodule

`default_nettype wire
