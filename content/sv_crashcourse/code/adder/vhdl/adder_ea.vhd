-- SPDX-FileCopyrightText: 2026 Simon Dorrer
-- SPDX-License-Identifier: Apache-2.0
-- Description: Unsigned adder with a generic width and a carry bit.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adder is
  generic(
    WIDTH : positive := 8
  );
  port(
    a_i   : in  std_logic_vector(WIDTH - 1 downto 0);
    b_i   : in  std_logic_vector(WIDTH - 1 downto 0);
    sum_o : out std_logic_vector(WIDTH downto 0)
  );
end entity adder;

architecture rtl of adder is
begin
  sum_o <= std_logic_vector(resize(unsigned(a_i), WIDTH + 1)
                            + unsigned(b_i));
end architecture rtl;
