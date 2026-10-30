// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Synchronous FIFO with first-word fall-through: data_o
// shows the oldest entry while empty_o is low. A push is accepted
// only while the FIFO is not full, a pop only while it is not empty.

`default_nettype none

module fifo #(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned DEPTH = 4  // power of two, at least 2
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             push_i,
  input  logic [WIDTH-1:0] data_i,
  input  logic             pop_i,
  output logic [WIDTH-1:0] data_o,
  output logic             full_o,
  output logic             empty_o
);

  localparam int unsigned AW = $clog2(DEPTH);

  // One bit more than the address: the extra wrap bit tells a full
  // FIFO (same address, different wrap bit) from an empty one
  logic [AW:0]      wr_ptr_d, wr_ptr_q, rd_ptr_d, rd_ptr_q;
  logic [WIDTH-1:0] mem_q [DEPTH];
  logic             push, pop;

  // Register process
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
    end else begin
      wr_ptr_q <= wr_ptr_d;
      rd_ptr_q <= rd_ptr_d;
    end
  end

  // Storage without reset: a pop never reads an unwritten entry
  always_ff @(posedge clk_i) begin
    if (push) begin
      mem_q[wr_ptr_q[AW-1:0]] <= data_i;
    end
  end

  // Combinational process
  always_comb begin
    push     = push_i && !full_o;
    pop      = pop_i && !empty_o;
    wr_ptr_d = push ? wr_ptr_q + 1'b1 : wr_ptr_q;
    rd_ptr_d = pop ? rd_ptr_q + 1'b1 : rd_ptr_q;
  end

  // Status flags and read port, decoded from the registers only
  assign empty_o = (wr_ptr_q == rd_ptr_q);
  assign full_o  = (wr_ptr_q == {~rd_ptr_q[AW], rd_ptr_q[AW-1:0]});
  assign data_o  = mem_q[rd_ptr_q[AW-1:0]];

endmodule

`default_nettype wire
