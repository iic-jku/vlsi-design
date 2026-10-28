-- SPDX-FileCopyrightText: 2026 Simon Dorrer
-- SPDX-License-Identifier: Apache-2.0
-- Description: Tick generator in the two-process style. While
-- en_i is high, tick_o is high for one clock cycle every DIV clock
-- cycles (DIV >= 2).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tick_gen is
  generic(
    DIV : positive := 10
  );
  port(
    clk_i  : in  std_logic;
    rst_i  : in  std_logic;
    en_i   : in  std_logic;
    tick_o : out std_logic
  );
end entity tick_gen;

architecture rtl of tick_gen is
  constant C_COUNT_WIDTH : natural := natural(ceil(log2(real(DIV))));

  subtype t_count is unsigned(C_COUNT_WIDTH - 1 downto 0);

  constant C_LAST : t_count := to_unsigned(DIV - 1, C_COUNT_WIDTH);

  signal count      : t_count;
  signal next_count : t_count;
  signal tick       : std_logic;
  signal next_tick  : std_logic;
begin
  -- Register process: reset values and copies of the next_ signals only
  reg_proc: process(rst_i, clk_i) is
  begin
    if rst_i = '1' then
      count <= (others => '0');
      tick <= '0';
    elsif rising_edge(clk_i) then
      count <= next_count;
      tick <= next_tick;
    end if;
  end process reg_proc;

  -- Combinational process: defaults first, then all decisions
  counter_logic: process(count, en_i) is
  begin
    next_count <= count;
    next_tick <= '0';
    if en_i = '1' then
      if count = C_LAST then
        next_count <= (others => '0');
        next_tick <= '1';
      else
        next_count <= count + 1;
      end if;
    end if;
  end process counter_logic;

  tick_o <= tick;
end architecture rtl;
