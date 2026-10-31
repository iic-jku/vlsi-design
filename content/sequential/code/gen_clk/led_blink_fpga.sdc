# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Timing constraints of the FPGA LED blinker of chapter
# 3: the 50 MHz clock and the clock that slow_clk_q derives from it.

create_clock -name clk -period 20 [get_ports clk_i]

# slow_clk_q toggles every DIV = 12,500,000 cycles: clk / (2 * DIV)
set div_q [get_pins -of_objects [get_nets slow_clk_q] \
  -filter "direction == output"]
create_generated_clock -name slow_clk -source [get_ports clk_i] \
  -divide_by 25000000 $div_q

set_output_delay 0 -clock clk [all_outputs]
set_load 0.01 [all_outputs]
