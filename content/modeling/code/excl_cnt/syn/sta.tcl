# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Minimal static timing analysis of a synthesized netlist
# with OpenSTA. Usage: TOP=<module> sta -no_init -exit syn/sta.tcl
# (reads <module>.nl.v from the current folder). The SDC commands are
# explained in the chapter on static timing analysis.

set top $::env(TOP)
read_liberty $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog $top.nl.v
link_design $top

# 100 MHz clock, ideal (no clock tree yet), inputs and outputs at the clock edge
create_clock -name clk -period 10 [get_ports clk_i]
set_input_delay 0 -clock clk [delete_from_list [all_inputs] [get_ports clk_i]]
set_output_delay 0 -clock clk [all_outputs]
set_input_transition 0.1 [all_inputs]
set_load 0.01 [all_outputs]

# Longest path to an output, and longest path between two flip-flops
report_checks -path_delay max -to [all_outputs] -format end
report_checks -path_delay max -from [all_registers -clock_pins] -to [all_registers -data_pins] -format end
