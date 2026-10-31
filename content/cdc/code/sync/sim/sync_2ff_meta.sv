// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Simulation model of sync_2ff with metastability
// injection, used in place of rtl/sync_2ff.sv. A bit of d_i that
// changed less than WINDOW before the clock edge resolves randomly
// to its old or its new value, as a metastable first flip-flop may.

`timescale 1ns / 1ps

module sync_2ff #(
  parameter int unsigned WIDTH = 1
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [WIDTH-1:0] d_i,
  output logic [WIDTH-1:0] q_o
);

  localparam realtime WINDOW = 1.0;  // ns before the edge

  realtime          t_chg [WIDTH];   // time of the last change
  logic [WIDTH-1:0] d_old = '0, meta_q, sample;
  int               n_samples = 0, n_random = 0;  // statistics

  always @(d_i) begin
    for (int i = 0; i < WIDTH; i++) begin
      if (d_i[i] !== d_old[i]) t_chg[i] = $realtime;
    end
    d_old = d_i;
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      meta_q <= '0;
      q_o    <= '0;
    end else begin
      sample = d_i;
      for (int i = 0; i < WIDTH; i++) begin
        if ($realtime - t_chg[i] < WINDOW) begin
          if ($urandom_range(1) == 1) sample[i] = ~d_i[i];
        end
      end
      n_samples++;
      if (sample != d_i) n_random++;
      meta_q <= sample;
      q_o    <= meta_q;
    end
  end

  final $display("%m: %0d of %0d samples with a bit at its old value",
                 n_random, n_samples);

endmodule
