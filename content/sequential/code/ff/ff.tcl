# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Timing parameters of the flip-flop in one_ff.v with
# OpenSTA. Usage: sta -no_init -exit ff.tcl. CORNER selects the
# library corner (default typ_1p20V_25C).

set corner typ_1p20V_25C
if {[info exists ::env(CORNER)]} { set corner $::env(CORNER) }
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_$corner.lib
read_verilog one_ff.v
link_design one_ff

# Clock and data edges of 0.1 ns, and 5 fF at the output
create_clock -name clk -period 4 [get_ports clk_i]
set_clock_transition 0.1 [get_clocks clk]
set_input_transition 0.1 [get_ports {d_i rst_ni}]
set_load 0.005 [get_ports q_o]

report_dcalc -from u1/CLK -to u1/Q -digits 3
report_dcalc -max -from u1/CLK -to u1/D -digits 3
report_dcalc -min -from u1/CLK -to u1/D -digits 3
report_dcalc -max -from u1/CLK -to u1/RESET_B -digits 3
report_dcalc -min -from u1/CLK -to u1/RESET_B -digits 3
report_dcalc -from u1/RESET_B -to u1/Q -digits 3
report_dcalc -from u1/CLK -to u1/CLK -digits 3
report_dcalc -from u1/RESET_B -to u1/RESET_B -digits 3
