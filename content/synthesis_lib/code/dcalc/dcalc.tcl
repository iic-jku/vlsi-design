# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Delay calculation of the inverter in one_inv.v with
# OpenSTA. Usage: sta -no_init -exit dcalc.tcl. The environment
# variables CORNER (default typ_1p20V_25C), SLEW (input transition
# in ns, default 0.25), and LOAD (output load in pF, default 0.05) set
# the library corner and the operating point.

proc env_or {name default} {
  if {[info exists ::env($name)]} { return $::env($name) }
  return $default
}

set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
set corner [env_or CORNER typ_1p20V_25C]
read_liberty $lib/lib/sg13cmos5l_stdcell_$corner.lib
read_verilog one_inv.v
link_design one_inv

set_input_transition [env_or SLEW 0.25] [get_ports a]
set_load [env_or LOAD 0.05] [get_ports y]

report_dcalc -from u1/A -to u1/Y -digits 4
report_check_types -max_capacitance -violators
