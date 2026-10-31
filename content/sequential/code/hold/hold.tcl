# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Hold and setup check of the path from ff1 to ff2 in
# shift.v with OpenSTA. Usage: sta -no_init -exit hold.tcl. CORNER
# selects the library corner (default typ_1p20V_25C), PERIOD the
# clock period in ns (default 4).

set corner typ_1p20V_25C
if {[info exists ::env(CORNER)]} { set corner $::env(CORNER) }
set period 4
if {[info exists ::env(PERIOD)]} { set period $::env(PERIOD) }
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_$corner.lib
read_verilog shift.v
link_design shift

# The clock buffers are in the netlist: propagate the clock through
create_clock -name clk -period $period [get_ports clk_i]
set_propagated_clock [all_clocks]
set_input_delay 0 -clock clk [get_ports d_i]
set_output_delay 0 -clock clk [all_outputs]
set_input_transition 0.1 [all_inputs]
set_load 0.01 [all_outputs]

report_checks -path_delay min -to [get_pins ff2/D] -digits 3
report_checks -path_delay max -to [get_pins ff2/D] -digits 3
