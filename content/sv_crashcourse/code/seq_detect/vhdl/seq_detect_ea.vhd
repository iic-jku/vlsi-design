-- SPDX-FileCopyrightText: 2026 Simon Dorrer
-- SPDX-License-Identifier: Apache-2.0
-- Description: Moore FSM that detects the bit pattern 1011 in the serial
-- input bit_i (one bit per rising clock edge, overlapping occurrences count).
-- detect_o is high for one cycle after the edge that sampled the last 1.

library ieee;
use ieee.std_logic_1164.all;

entity seq_detect is
  port(
    clk_i    : in  std_logic;
    rst_i    : in  std_logic;
    bit_i    : in  std_logic;
    detect_o : out std_logic
  );
end entity seq_detect;

architecture rtl of seq_detect is
  -- Each state names the longest matched prefix of 1011
  type t_state is (DET_IDLE, DET_1, DET_10, DET_101, DET_1011);

  signal state      : t_state;
  signal next_state : t_state;
begin
  reg_proc: process(rst_i, clk_i) is
  begin
    if rst_i = '1' then
      state <= DET_IDLE;
    elsif rising_edge(clk_i) then
      state <= next_state;
    end if;
  end process reg_proc;

  fsm_logic: process(state, bit_i) is
  begin
    next_state <= state;
    detect_o <= '0';
    case state is
      when DET_IDLE =>
        if bit_i = '1' then
          next_state <= DET_1;
        end if;
      when DET_1 =>
        if bit_i = '0' then
          next_state <= DET_10;
        end if;
      when DET_10 =>
        if bit_i = '1' then
          next_state <= DET_101;
        else
          next_state <= DET_IDLE;
        end if;
      when DET_101 =>
        if bit_i = '1' then
          next_state <= DET_1011;
        else
          next_state <= DET_10;
        end if;
      when DET_1011 =>
        detect_o <= '1';
        if bit_i = '1' then
          next_state <= DET_1;
        else
          next_state <= DET_10;
        end if;
    end case;
  end process fsm_logic;
end architecture rtl;
