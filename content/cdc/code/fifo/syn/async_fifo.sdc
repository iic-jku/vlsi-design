# SPDX-FileCopyrightText: 2026 Simon Dorrer
# SPDX-License-Identifier: Apache-2.0
# Description: Timing constraints of async_fifo: a write clock of
# 100 MHz and an unrelated read clock of about 70 MHz, each with the
# ports of its own domain.

create_clock -name wclk -period 10.0 [get_ports wclk_i]
create_clock -name rclk -period 14.3 [get_ports rclk_i]
set_clock_transition 0.1 [all_clocks]
set_clock_uncertainty 0.1 [all_clocks]

# The ports of each domain refer to their own clock
set w_in [get_ports {wrst_ni push_i data_i*}]
set r_in [get_ports {rrst_ni pop_i}]
set_input_delay 1.0 -clock wclk $w_in
set_input_delay 1.0 -clock rclk $r_in
set_output_delay 1.0 -clock wclk [get_ports full_o]
set_output_delay 1.0 -clock rclk [get_ports {data_o* empty_o}]
set_driving_cell -lib_cell sg13cmos5l_buf_2 -pin X $w_in
set_driving_cell -lib_cell sg13cmos5l_buf_2 -pin X $r_in
set_load 0.01 [all_outputs]
