-- SPDX-FileCopyrightText: 2026 Simon Dorrer
-- SPDX-License-Identifier: Apache-2.0
-- Description: Moore FSM of a simple controller. A start_i pulse moves it
-- from idle to run (busy_o high) until last_i, then done_o is high for one
-- clock cycle before the FSM returns to idle.

library ieee;
use ieee.std_logic_1164.all;

entity ctrl_fsm is
  port(
    clk_i   : in  std_logic;
    rst_i   : in  std_logic;
    start_i : in  std_logic;
    last_i  : in  std_logic;
    busy_o  : out std_logic;
    done_o  : out std_logic
  );
end entity ctrl_fsm;

architecture rtl of ctrl_fsm is
  type t_state is (CTRL_IDLE, CTRL_RUN, CTRL_DONE);

  signal state      : t_state;
  signal next_state : t_state;
begin
  reg_proc: process(rst_i, clk_i) is
  begin
    if rst_i = '1' then
      state <= CTRL_IDLE;
    elsif rising_edge(clk_i) then
      state <= next_state;
    end if;
  end process reg_proc;

  fsm_logic: process(state, start_i, last_i) is
  begin
    next_state <= state;
    busy_o <= '0';
    done_o <= '0';
    case state is
      when CTRL_IDLE =>
        if start_i = '1' then
          next_state <= CTRL_RUN;
        end if;
      when CTRL_RUN =>
        busy_o <= '1';
        if last_i = '1' then
          next_state <= CTRL_DONE;
        end if;
      when CTRL_DONE =>
        done_o <= '1';
        next_state <= CTRL_IDLE;
    end case;
  end process fsm_logic;
end architecture rtl;
