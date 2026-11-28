# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Timing parameters of the latch in one_latch.v with
# OpenSTA, with the edges and the load of ff/ff.tcl. Usage:
# sta -no_init -exit latch.tcl

set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib.gz
read_verilog one_latch.v
link_design one_latch

# Clock and data edges of 0.1 ns, and 5 fF at the output
create_clock -name clk -period 4 [get_ports clk_i]
set_clock_transition 0.1 [get_clocks clk]
set_input_transition 0.1 [get_ports {clk_i d_i rst_ni}]
set_load 0.005 [get_ports q_o]

# GATE_N falling opens the latch, GATE_N rising closes it
report_dcalc -from u1/GATE_N -to u1/Q -digits 3
report_dcalc -from u1/D -to u1/Q -digits 3
report_dcalc -max -from u1/GATE_N -to u1/D -digits 3
