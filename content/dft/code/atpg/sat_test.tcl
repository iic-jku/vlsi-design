# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Test generation for one stuck-at fault with a SAT
# solver. Builds a copy of the netlist with the fault, joins both in a
# miter, and searches an input for which the outputs differ. Usage:
#   TOP=cons PINS=u_or/C SA=0 yosys -c sat_test.tcl
# TOP is the module, read from $TOP.v unless NETLIST names the file.
# PINS lists the cell inputs that the fault forces to SA: one pin for
# a net with one load, all its loads for a net with several. (This
# misses a net that also drives an output port.)

yosys -import
set top $::env(TOP)
set netlist $top.v
if {[info exists ::env(NETLIST)]} { set netlist $::env(NETLIST) }
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
set lib $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib

# The cell functions from the Liberty file, then the netlist
read_liberty -ignore_miss_func $lib
read_verilog $netlist
hierarchy -check -top $top

# The faulty copy: each listed pin is tied to the stuck-at value
copy $top faulty
yosys cd faulty
foreach p $::env(PINS) {
  lassign [split $p /] cell pin
  connect -port $cell $pin 1'b$::env(SA)
}
yosys cd ..

# The miter compares both copies, the solver searches a difference
miter -equiv -flatten -make_outputs $top faulty miter
hierarchy -top miter
tee -q -o sat.log sat -prove trigger 0 -show-inputs miter
set f [open sat.log]
set log [read $f]
close $f
if {[string match "*model found: FAIL*" $log]} {
  puts "TEST FOUND, the inputs (decimal):"
  set rows {^\s+\\in_(\S+)\s+(\d+)}
  foreach {- name value} [regexp -all -inline -line $rows $log] {
    puts "  $name = $value"
  }
} else {
  puts "NO TEST EXISTS: the fault is untestable"
}
