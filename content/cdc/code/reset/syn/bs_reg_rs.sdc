# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Timing constraints of bs_reg_rs, the same as for
# bs_reg in chapter 6: a 250 MHz clock, and inputs and outputs that
# connect to registers outside the block.

# The clock, ideal until the clock tree exists
create_clock -name clk -period 4.0 [get_ports clk_i]
set_clock_transition 0.1 [get_clocks clk]
set_clock_uncertainty 0.1 [get_clocks clk]

# The environment: the external registers use 1 ns of each period
set inputs [delete_from_list [all_inputs] [get_ports clk_i]]
set_input_delay 1.0 -clock clk $inputs
set_output_delay 1.0 -clock clk [all_outputs]
set_driving_cell -lib_cell sg13cmos5l_buf_2 -pin X $inputs
set_load 0.01 [all_outputs]
