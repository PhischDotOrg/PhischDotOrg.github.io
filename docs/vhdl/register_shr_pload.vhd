--
-- Copyright (c) 2011 Philip Schulz <phs@deadc0.de>
-- All rights reserved.
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity register_shr_pload is
generic (
    width : natural := 8
);
port (
    clk_i   : in  STD_LOGIC;
    pdat_i  : in  STD_LOGIC_VECTOR((width - 1) downto 0);
    sdat_i  : in  STD_LOGIC;
    sdat_o  : out STD_LOGIC;
    load_i  : in  STD_LOGIC;
    shr_i   : in  STD_LOGIC
);
end register_shr_pload;

architecture behavioral of register_shr_pload is
    signal data : std_logic_vector((width - 1) downto 0);
begin
    process(clk_i)
    begin
        if (rising_edge(clk_i)) then
            if (load_i = '1') then
                data <= pdat_i;
            elsif (shr_i = '1') then
                data <= data((data'high - 1) downto 0) & sdat_i;
            end if;
        end if;
    end process;

    sdat_o  <= data(data'high);
end behavioral;

