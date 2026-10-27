-- SPDX-FileCopyrightText: 2026 Simon Dorrer
-- SPDX-License-Identifier: Apache-2.0
-- Description: 4:1 multiplexer for 8-bit data with a zero flag.

library ieee;
use ieee.std_logic_1164.all;

entity mux4 is
  port(
    a_i    : in  std_logic_vector(7 downto 0);
    b_i    : in  std_logic_vector(7 downto 0);
    c_i    : in  std_logic_vector(7 downto 0);
    d_i    : in  std_logic_vector(7 downto 0);
    sel_i  : in  std_logic_vector(1 downto 0);
    y_o    : out std_logic_vector(7 downto 0);
    zero_o : out std_logic
  );
end entity mux4;

architecture rtl of mux4 is
  signal y : std_logic_vector(7 downto 0);
begin
  with sel_i select
    y <= a_i when "00",
         b_i when "01",
         c_i when "10",
         d_i when others;

  y_o <= y;
  zero_o <= '1' when y = x"00" else '0';
end architecture rtl;
