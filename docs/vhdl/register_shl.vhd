--
-- Copyright (c) 2011 Philip Schulz <phs@deadc0.de>
-- All rights reserved.
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity register_shl is
generic (
    width : natural := 8
);
port (
    clk_i : in  STD_LOGIC;
    we_i  : in  STD_LOGIC;
    dat_i : in  STD_LOGIC;
    dat_o : out STD_LOGIC_VECTOR ((width - 1) downto 0)
);
end register_shl;

architecture behavioral of register_shl is
    signal data : std_logic_vector((width - 1) downto 0);
begin
    process(clk_i)
    begin
        if rising_edge(clk_i) then
            if we_i = '1' then
                data <= data((data'high - 1) downto 0) & dat_i;
            end if;
        end if;
    end process;

    dat_o <= data;
end behavioral;

