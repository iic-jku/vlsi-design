# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Setup checks of the two halves of the path in
# borrow_latch.v or borrow_ff.v with OpenSTA. Usage:
# TOP=borrow_latch sta -no_init -exit borrow.tcl (or TOP=borrow_ff).

set top $::env(TOP)
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog $top.v
link_design $top

create_clock -name clk -period 4 [get_ports clk_i]
set_input_delay 0 -clock clk [get_ports d_i]
set_output_delay 0 -clock clk [all_outputs]
set_input_transition 0.1 [all_inputs]
set_load 0.01 [all_outputs]

report_checks -path_delay max -to [get_pins mid/D] -digits 3
report_checks -path_delay max -to [get_pins ff2/D] -digits 3
