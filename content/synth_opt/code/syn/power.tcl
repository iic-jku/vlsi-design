# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Power analysis of a netlist <TOP>.nl.v in the current
# folder with OpenSTA and the constraints block.sdc. Usage:
# TOP=cg_reg sta -no_init -exit ../syn/power.tcl. VCD names a file
# with the activity of a simulation, whose testbench tb_<TOP> has
# the instance dut, and the script stops if a pin of the netlist
# gets no activity from it. Without VCD, every input except rst_ni
# toggles in 10 % of the clock cycles.
# CORNER selects the library corner (default typ_1p20V_25C).

set top $::env(TOP)
set corner typ_1p20V_25C
if {[info exists ::env(CORNER)]} { set corner $::env(CORNER) }
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_$corner.lib.gz
read_verilog $top.nl.v
link_design $top
read_sdc [file dirname [info script]]/block.sdc

# The activity of every net: from the simulation if there is one,
# otherwise the default activity at the inputs and a quiet reset
if {[info exists ::env(VCD)]} {
  read_vcd -scope tb_$top/dut $::env(VCD)
  # read_vcd reports no error when its scope or the netlist does not
  # match the simulation, and every pin it misses keeps the default
  # activity, so stop unless every pin is annotated
  sta::redirect_string_begin
  report_activity_annotation
  set annotation [sta::redirect_string_end]
  puts -nonewline $annotation
  if {![regexp {unannotated\s+0\s} $annotation]} {
    puts "Error: pins without activity from $::env(VCD)"
    exit 1
  }
} else {
  set_power_activity -input_ports rst_ni -activity 0 -duty 1
}
report_power -digits 3
