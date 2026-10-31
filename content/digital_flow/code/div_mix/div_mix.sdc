# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Timing constraints of div_mix: the clock at clk_i and
# the clock that the flip-flop of div_q divides from it by two.

create_clock -name clk -period 4.0 [get_ports clk_i]
set div_q [get_pins -of_objects [get_nets div_q] \
  -filter "direction == output"]
create_generated_clock -name clk_div -source [get_ports clk_i] \
  -divide_by 2 $div_q
set_clock_transition 0.1 [all_clocks]
set_clock_uncertainty 0.1 [all_clocks]

set inputs [delete_from_list [all_inputs] [get_ports clk_i]]
set_input_delay 1.0 -clock clk $inputs
set_output_delay 1.0 -clock clk [get_ports a_o*]
set_output_delay 1.0 -clock clk_div [get_ports b_o*]
set_driving_cell -lib_cell sg13cmos5l_buf_2 -pin X $inputs
set_load 0.01 [all_outputs]
