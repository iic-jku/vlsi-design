# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Longest path through a combinational netlist with
# OpenSTA. Usage: TOP=<module> sta -no_init -exit comb_sta.tcl (reads
# <module>.nl.v from the current folder). A virtual clock of 10 ns
# gives the paths from the inputs to the outputs a reference. CORNER
# (default typ_1p20V_25C) selects the library corner.

set top $::env(TOP)
set corner typ_1p20V_25C
if {[info exists ::env(CORNER)]} { set corner $::env(CORNER) }
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_$corner.lib
read_verilog $top.nl.v
link_design $top

create_clock -name vclk -period 10
set_input_delay 0 -clock vclk [all_inputs]
set_output_delay 0 -clock vclk [all_outputs]
set_input_transition 0.1 [all_inputs]
set_load 0.01 [all_outputs]

report_checks -path_delay max -format end
