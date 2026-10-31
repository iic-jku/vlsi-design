# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Static timing analysis of bs_reg with OpenSTA. Usage,
# in the folder bs_reg: sta -no_init -exit syn/sta.tcl (reads
# bs_reg.nl.v). CORNER selects the library corner (default
# typ_1p20V_25C).

set corner typ_1p20V_25C
if {[info exists ::env(CORNER)]} { set corner $::env(CORNER) }
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_$corner.lib
read_verilog bs_reg.nl.v
link_design bs_reg
read_sdc syn/bs_reg.sdc

# Missing clocks and constraints, then the worst setup and hold paths
check_setup -verbose
report_checks -path_delay max -fields {fanout} -digits 3
report_checks -path_delay min -digits 3
report_clock_min_period
report_wns -digits 3
report_tns -digits 3
report_check_types -max_slew -max_capacitance -violators
