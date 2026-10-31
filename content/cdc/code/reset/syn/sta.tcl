# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Static timing analysis of bs_reg_rs with OpenSTA.
# Usage, in the folder reset: sta -no_init -exit syn/sta.tcl (reads
# bs_reg_rs.nl.v). SDC selects the constraints (default
# syn/bs_reg_rs.sdc).

set sdc syn/bs_reg_rs.sdc
if {[info exists ::env(SDC)]} { set sdc $::env(SDC) }
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog bs_reg_rs.nl.v
link_design bs_reg_rs
read_sdc $sdc

# The worst path of every path group, and the minimum periods
check_setup -verbose
report_checks -path_delay max -fields {fanout slew} -digits 3
report_clock_min_period
report_clock_min_period -include_port_paths
report_check_types -max_slew -max_capacitance -violators

# The checks of the reset input, and the removal checks
report_checks -from [get_ports rst_ni] -path_delay min_max \
  -format end -digits 3
report_checks -path_delay min -path_group asynchronous \
  -format end -digits 3
