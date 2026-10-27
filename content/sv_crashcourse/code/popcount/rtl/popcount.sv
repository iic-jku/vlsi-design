// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Combinational population count (number of ones in x_i).

`default_nettype none

module popcount (
  input  logic [7:0] x_i,
  output logic [3:0] count_o
);

  // The loop is unrolled at elaboration: eight adders, no clock cycles
  always_comb begin
    count_o = '0;
    for (int i = 0; i < 8; i++) begin
      count_o = count_o + 4'(x_i[i]);
    end
  end

endmodule

`default_nettype wire
