# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Equivalence check of a netlist before (gold) and after
# scan insertion (gate), with the flip-flops matched by name. Ties the
# scan inputs of the gate netlist to TIE (default 0). Usage, in the
# folder of the netlists: TOP=bs_reg yosys -q -c scan_eq.tcl (reads
# $TOP.nl.v and ${TOP}_scan.nl.v).

yosys -import
set top $::env(TOP)
set tie 0
if {[info exists ::env(TIE)]} { set tie $::env(TIE) }
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
set lib $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib

# Both netlists with the cell functions from the Liberty file
read_liberty -ignore_miss_func $lib
read_verilog $top.nl.v
yosys rename $top gold
read_verilog ${top}_scan.nl.v
yosys rename $top gate

# The scan ports become wires, the scan inputs get the constant
set f [open ${top}_scan.nl.v]
set scan_in [regexp -all -inline {input (scan_\w+);} [read $f]]
close $f
delete -port gate/scan_*
yosys cd gate
foreach {- port} $scan_in { connect -set $port 1'b$tie }
yosys cd ..
hierarchy -check
flatten -noscopeinfo gold gate
yosys rename -hide w:*.*  ;# the nets inside the flattened cells
opt_clean
async2sync

# Match the nets of both by name, then prove them equal
equiv_make gold gate equiv
hierarchy -top equiv
equiv_simple -seq 2
equiv_induct
tee -q -o equiv.log equiv_status
set f [open equiv.log]
set log [read $f]
close $f
regexp {Of those cells (\d+) are proven and (\d+) are unproven} \
  $log - proven unproven
puts "$proven points proven equal, $unproven unproven"
