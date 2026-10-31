# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Static timing analysis of a netlist <TOP>.nl.v in the
# current folder with OpenSTA and the constraints block.sdc. Usage:
# TOP=add_reg sta -no_init -exit ../syn/sta.tcl. CORNER selects the
# library corner (default typ_1p20V_25C).

set top $::env(TOP)
set corner typ_1p20V_25C
if {[info exists ::env(CORNER)]} { set corner $::env(CORNER) }
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_$corner.lib
read_verilog $top.nl.v
link_design $top
read_sdc [file dirname [info script]]/block.sdc

# The worst setup path of the clock, and the minimum period
report_checks -path_delay max -path_group clk -digits 3
report_clock_min_period
report_clock_min_period -include_port_paths
