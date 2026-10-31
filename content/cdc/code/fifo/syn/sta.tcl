# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Static timing analysis of async_fifo with OpenSTA.
# Usage, in the folder fifo: sta -no_init -exit syn/sta.tcl (reads
# async_fifo.nl.v). CDC=1 makes the clocks asynchronous, CDC=2
# limits the delay of the crossing paths instead.

set lib $::env(PDK_ROOT)/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell
read_liberty $lib/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib
read_verilog async_fifo.nl.v
link_design async_fifo
read_sdc syn/async_fifo.sdc
set cdc 0
if {[info exists ::env(CDC)]} { set cdc $::env(CDC) }
if {$cdc == 1} {
  # The clocks are unrelated: no path between them is timed
  set_clock_groups -asynchronous -group wclk -group rclk
} elseif {$cdc == 2} {
  # Every crossing path within one period of the faster clock
  foreach {a b} {wclk rclk rclk wclk} {
    set_max_delay 10.0 -ignore_clock_latency \
      -from [get_clocks $a] -to [get_clocks $b]
    set_false_path -hold -from [get_clocks $a] -to [get_clocks $b]
  }
}

# The worst setup path of every path group, and the paths that
# cross from one clock to the other
report_checks -path_delay max -digits 3 -format end
report_checks -path_delay max -from [get_clocks wclk] \
  -to [get_clocks rclk] -digits 3
report_checks -path_delay max -from [get_clocks rclk] \
  -to [get_clocks wclk] -digits 3 -format end
