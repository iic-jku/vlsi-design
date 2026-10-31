// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Asynchronous FIFO between a write and a read clock
// domain, with first-word fall-through like the FIFO of chapter 4.
// The pointers cross the domains in Gray code through sync_2ff.

`default_nettype none

module async_fifo #(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned DEPTH = 4  // power of two, at least 4
) (
  // Write domain
  input  logic             wclk_i,
  input  logic             wrst_ni,
  input  logic             push_i,
  input  logic [WIDTH-1:0] data_i,
  output logic             full_o,
  // Read domain
  input  logic             rclk_i,
  input  logic             rrst_ni,
  input  logic             pop_i,
  output logic [WIDTH-1:0] data_o,
  output logic             empty_o
);

  localparam int unsigned AW = $clog2(DEPTH);

  logic [AW:0]      wbin_q, wgray_q, wbin_d;  // write pointer
  logic [AW:0]      rbin_q, rgray_q, rbin_d;  // read pointer
  logic [AW:0]      rgray_w, wgray_r;  // synchronized into the other
  logic [WIDTH-1:0] mem_q [DEPTH];
  logic             push, pop;

  // Write domain: the pointer in binary and in Gray code
  always_ff @(posedge wclk_i or negedge wrst_ni) begin
    if (!wrst_ni) begin
      wbin_q  <= '0;
      wgray_q <= '0;
    end else begin
      wbin_q  <= wbin_d;
      wgray_q <= wbin_d ^ (wbin_d >> 1);
    end
  end

  always_ff @(posedge wclk_i) begin
    if (push) begin
      mem_q[wbin_q[AW-1:0]] <= data_i;
    end
  end

  // Read domain
  always_ff @(posedge rclk_i or negedge rrst_ni) begin
    if (!rrst_ni) begin
      rbin_q  <= '0;
      rgray_q <= '0;
    end else begin
      rbin_q  <= rbin_d;
      rgray_q <= rbin_d ^ (rbin_d >> 1);
    end
  end

  // Each Gray pointer into the other domain
  sync_2ff #(.WIDTH(AW + 1)) u_sync_r2w (
    .clk_i (wclk_i),
    .rst_ni(wrst_ni),
    .d_i   (rgray_q),
    .q_o   (rgray_w)
  );

  sync_2ff #(.WIDTH(AW + 1)) u_sync_w2r (
    .clk_i (rclk_i),
    .rst_ni(rrst_ni),
    .d_i   (wgray_q),
    .q_o   (wgray_r)
  );

  // Full: the write pointer is one lap ahead of the read pointer,
  // which in Gray code inverts the two upper bits
  assign full_o  = (wgray_q == {~rgray_w[AW:AW-1], rgray_w[AW-2:0]});
  assign empty_o = (rgray_q == wgray_r);
  assign data_o  = mem_q[rbin_q[AW-1:0]];

  always_comb begin
    push   = push_i && !full_o;
    pop    = pop_i && !empty_o;
    wbin_d = push ? wbin_q + 1'b1 : wbin_q;
    rbin_d = pop ? rbin_q + 1'b1 : rbin_q;
  end

endmodule

`default_nettype wire
