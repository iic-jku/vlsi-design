// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: 4:1 multiplexer for 8-bit data with a zero flag.

`default_nettype none

module mux4 (
  input  logic [7:0] a_i,
  input  logic [7:0] b_i,
  input  logic [7:0] c_i,
  input  logic [7:0] d_i,
  input  logic [1:0] sel_i,
  output logic [7:0] y_o,
  output logic       zero_o
);

  always_comb begin
    case (sel_i)
      2'b00:   y_o = a_i;
      2'b01:   y_o = b_i;
      2'b10:   y_o = c_i;
      default: y_o = d_i;
    endcase
  end

  // An output can be read inside the module, no internal copy needed
  assign zero_o = (y_o == 8'h00);

endmodule

`default_nettype wire
