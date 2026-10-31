# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Static timing analysis of an LED blinker with OpenSTA.
# Usage: TOP=<module> SDC=<file> sta -no_init -exit sta.tcl (reads
# <module>.nl.v from the current folder).

set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog $::env(TOP).nl.v
link_design $::env(TOP)
read_sdc $::env(SDC)

check_setup -verbose
report_clock_properties
report_checks -path_delay max -format end
