# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Scan insertion with OpenROAD. Replaces every flip-flop
# by its scan version and stitches the scan chains. Usage, in the
# folder of the netlist: TOP=bs_reg openroad -no_init -exit dft.tcl
# (reads $TOP.nl.v, writes ${TOP}_scan.nl.v). CLOCKS lists the clock
# inputs (default clk_i), MAX_LENGTH limits the length of a chain
# (default 100).

set top $::env(TOP)
set clocks clk_i
if {[info exists ::env(CLOCKS)]} { set clocks $::env(CLOCKS) }
set max_length 100
if {[info exists ::env(MAX_LENGTH)]} {
  set max_length $::env(MAX_LENGTH)
}

set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_lef $lib/lef/sg13cmos5l_tech.lef
read_lef $lib/lef/sg13cmos5l_stdcell.lef
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog $top.nl.v
link_design $top

# The chains are built per clock, so the clocks must be known
foreach clk $clocks {
  create_clock -name $clk -period 100 [get_ports $clk]
}
set_dft_config -max_length $max_length -clock_mixing no_mix

# Replace the flip-flops, plan the chains, and stitch them
scan_replace
report_dft_plan -verbose
execute_dft_plan
write_verilog ${top}_scan.nl.v
