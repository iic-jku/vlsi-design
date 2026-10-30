# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Static timing analysis of the synthesized FIFO with
# OpenSTA, and the SDF file for the timing simulation. Usage, in the
# macro folder: sta -no_init -exit syn/sta.tcl (reads fifo.nl.v,
# writes fifo.sdf). CLK_PERIOD_NS sets the clock period (default 20).

set period 20
if {[info exists ::env(CLK_PERIOD_NS)]} {
  set period $::env(CLK_PERIOD_NS)
}

set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog fifo.nl.v
link_design fifo

# Ideal clock. The testbench changes the inputs at the falling edge
# and samples the outputs at the next one: half a period each.
create_clock -name clk -period $period [get_ports clk_i]
set inputs [delete_from_list [all_inputs] [get_ports clk_i]]
set_input_delay [expr {$period / 2.0}] -clock clk $inputs
set_output_delay [expr {$period / 2.0}] -clock clk [all_outputs]
set_input_transition 0.1 [all_inputs]
set_load 0.01 [all_outputs]

report_checks -path_delay max
report_worst_slack -max -digits 3

# Icarus Verilog annotates only the typical value of each delay triple
write_sdf -include_typ -no_timestamp fifo.sdf

# Icarus Verilog cannot read the VOLTAGE and TEMPERATURE lines and
# the INTERCONNECT entries of the bus data_i. All INTERCONNECT delays
# are zero before layout, so remove them with the first CELL block.
set f [open fifo.sdf]
set sdf [read $f]
close $f
regsub -all {\n \((VOLTAGE|TEMPERATURE) [^\n]*} $sdf {} sdf
set top_cell { \(CELL\n  \(CELLTYPE "fifo"\)\n  \(INSTANCE\)\n}
append top_cell {  \(DELAY\n   \(ABSOLUTE\n(    \(INTERCONNECT [^\n]*\n)*}
append top_cell {   \)\n  \)\n \)\n}
regsub $top_cell $sdf {} sdf
set f [open fifo.sdf w]
puts -nonewline $f $sdf
close $f
