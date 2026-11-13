# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Scan insertion on a placed netlist with OpenROAD.
# Replaces the flip-flops by scan flip-flops, places the design,
# and stitches one chain, whose order then follows the placement.
# Prints the wire length of the chain, the length of the same chain
# in the order without placement (by descending instance name), and
# the position and the Q net of every scan flip-flop in chain order.
# Lengths are Manhattan distances between the cell centers, without
# the ports.
# Usage, in the folder of the netlist:
#   NETLIST=bs_reg32.nl.v TOP=bs_reg \
#     openroad -no_init -exit dft_place.tcl

set top $::env(TOP)
set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_lef $lib/lef/sg13cmos5l_tech.lef
read_lef $lib/lef/sg13cmos5l_stdcell.lef
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog $::env(NETLIST)
link_design $top
create_clock -name clk_i -period 100 [get_ports clk_i]
set_dft_config -max_length 1000 -clock_mixing no_mix

# Scan flip-flops first, since they are larger, then the placement
scan_replace
initialize_floorplan -utilization 50 -aspect_ratio 1 \
  -core_space 5 -site CoreSite
make_tracks
place_pins -hor_layers Metal3 -ver_layers Metal2
global_placement -density 0.6
detailed_placement

# Stitch the chain on the placed cells
execute_dft_plan

set block [ord::get_db_block]
set dbu [$block getDbUnitsPerMicron]
proc center {inst} {
  set bb [$inst getBBox]
  list [expr {([$bb xMin] + [$bb xMax]) / 2.0}] \
       [expr {([$bb yMin] + [$bb yMax]) / 2.0}]
}
proc length {insts} {
  set l 0.0
  foreach a [lrange $insts 0 end-1] b [lrange $insts 1 end] {
    lassign [center $a] xa ya
    lassign [center $b] xb yb
    set l [expr {$l + abs($xb - $xa) + abs($yb - $ya)}]
  }
  return [expr {$l / $::dbu}]
}

# Follow the chain from scan_in_0: SCD of each cell, Q to the next
set by_scd {}
foreach inst [$block getInsts] {
  set scd [$inst findITerm SCD]
  if {$scd ne "NULL"} {
    dict set by_scd [[$scd getNet] getName] $inst
  }
}
set chain {}
set net scan_in_0
while {[dict exists $by_scd $net]} {
  set inst [dict get $by_scd $net]
  lappend chain $inst
  set net [[[$inst findITerm Q] getNet] getName]
}
set names [lsort -decreasing -dictionary \
  [lmap i $chain {$i getName}]]
set by_name [lmap n $names {$block findInst $n}]

set core [$block getCoreArea]
puts [format "core: %.1f %.1f %.1f %.1f um" \
  [expr {[$core xMin] / $dbu}] [expr {[$core yMin] / $dbu}] \
  [expr {[$core xMax] / $dbu}] [expr {[$core yMax] / $dbu}]]
puts [format "chain: %d cells, %.1f um" [llength $chain] \
  [length $chain]]
puts [format "same cells by name: %.1f um" [length $by_name]]
foreach inst $chain {
  lassign [center $inst] x y
  puts [format "cell %s %.1f %.1f %s" [$inst getName] \
    [expr {$x / $dbu}] [expr {$y / $dbu}] \
    [[[$inst findITerm Q] getNet] getName]]
}
