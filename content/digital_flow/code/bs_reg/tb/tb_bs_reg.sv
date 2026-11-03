// SPDX-FileCopyrightText: 2026 Simon Dorrer
// SPDX-License-Identifier: Apache-2.0
// Description: Testbench of bs_reg for the RTL and the netlist, with
// the delays of an SDF file if +SDF=<file> names one. It changes the
// inputs DRIVE ns after each rising edge and checks data_o SAMPLE ns
// after it, against the inputs of two edges before. Plusargs:
// +PERIOD, +DRIVE, +SAMPLE (ns), +CYCLES, +SHOW (mismatches to
// print), +SDF, +WAVES.

`timescale 1ns / 1ps

module tb_bs_reg;

  real   period = 4.0;  // the clock of the SDC
  real   drive = 1.0;   // the input delay of the SDC
  real   sample = 3.0;  // the period minus the output delay
  int    cycles = 2000, show = 3, errors = 0;
  string sdf;

  logic        clk_i = 1'b0, rst_ni = 1'b0;
  logic [31:0] data_i = '0;
  logic [4:0]  shamt_i = '0;
  logic [1:0]  mode_i = '0;
  logic [31:0] data_o, exp_o, expected [$];

  bs_reg dut (.*);

  // Reference model of the barrel shifter of chapter 4. A rotation
  // shifts two copies of the word side by side.
  function automatic logic [31:0] model(logic [31:0] d,
                                        logic [4:0] s, logic [1:0] m);
    logic [63:0] l, r;
    l = {d, d} << s;
    r = {d, d} >> s;
    case (m)
      2'b00:   model = d << s;
      2'b01:   model = d >> s;
      2'b10:   model = l[63:32];
      default: model = r[31:0];
    endcase
  endfunction

  initial begin
    if ($value$plusargs("SDF=%s", sdf)) $sdf_annotate(sdf, dut);
    void'($value$plusargs("PERIOD=%f", period));
    void'($value$plusargs("DRIVE=%f", drive));
    void'($value$plusargs("SAMPLE=%f", sample));
    void'($value$plusargs("CYCLES=%d", cycles));
    void'($value$plusargs("SHOW=%d", show));
    if ($test$plusargs("WAVES")) begin
      $dumpfile("tb_bs_reg.fst");
      $dumpvars(0, tb_bs_reg);
    end
    #(period / 2);
    forever #(period / 2) clk_i = ~clk_i;  // rising edges at k T
  end

  initial begin
    repeat (2) @(posedge clk_i);
    #(drive) rst_ni = 1'b1;
    for (int k = 0; k < cycles + 2; k++) begin
      @(posedge clk_i);
      #(drive);
      if (k < cycles) begin
        data_i  = $urandom;
        shamt_i = 5'($urandom);
        mode_i  = 2'($urandom);
        expected.push_back(model(data_i, shamt_i, mode_i));
      end
      #(sample - drive);
      if (k >= 2) begin
        exp_o = expected.pop_front();
        if (data_o !== exp_o) begin
          errors++;
          if (errors <= show)
            $display("%0.3f ns: data_o = %h, expected %h",
                     $realtime, data_o, exp_o);
        end
      end
    end
    $display("%0d cycles, %0d errors", cycles, errors);
    $finish;
  end

endmodule
