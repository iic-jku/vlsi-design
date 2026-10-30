// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Assertions for the FIFO. The bind statement at the end
// adds this checker to every instance of fifo without changing its
// RTL, and the checker can also read the internal pointers.

`default_nettype none

module fifo_sva #(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned DEPTH = 4
) (
  input logic                   clk_i,
  input logic                   rst_ni,
  input logic                   push_i,
  input logic                   pop_i,
  input logic [WIDTH-1:0]       data_o,
  input logic                   full_o,
  input logic                   empty_o,
  input logic [$clog2(DEPTH):0] wr_ptr_q,
  input logic [$clog2(DEPTH):0] rd_ptr_q
);

  logic [$clog2(DEPTH):0] level;
  assign level = wr_ptr_q - rd_ptr_q;

  // Never full and empty at the same time
  a_flags: assert property (@(posedge clk_i) disable iff (!rst_ni)
    !(full_o && empty_o));

  // The fill level never exceeds DEPTH (white box: the pointers)
  a_level: assert property (@(posedge clk_i) disable iff (!rst_ni)
    32'(level) <= DEPTH);

  // The oldest entry does not change without a pop
  a_head: assert property (@(posedge clk_i) disable iff (!rst_ni)
    !empty_o && !pop_i |=> $stable(data_o));

  // A full FIFO refuses a push, so a pop always makes room
  a_room: assert property (@(posedge clk_i) disable iff (!rst_ni)
    full_o && pop_i |=> !full_o);

  // Was a push and a pop on a full FIFO ever tried?
  c_full_push_pop: cover property (@(posedge clk_i)
    disable iff (!rst_ni) full_o && push_i && pop_i);

endmodule

bind fifo fifo_sva #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_sva (.*);

`default_nettype wire
