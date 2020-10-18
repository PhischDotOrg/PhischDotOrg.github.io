--
-- Copyright (c) 2011 Philip Schulz <phs@deadc0.de>
-- All rights reserved.
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity register_addr is
generic (
    width : natural := 8
);
port (
    clk_i   : in  STD_LOGIC;
    load_i  : in  STD_LOGIC;
    incr_i  : in  STD_LOGIC;
    dat_i   : in  STD_LOGIC_VECTOR((width - 1) downto 0);
    dat_o   : out STD_LOGIC_VECTOR((width - 1) downto 0)
);
end register_addr;

architecture behavioral of register_addr is
    signal addr, offs : unsigned((width - 1) downto 0);
begin
--    process (clk_i, load_i, dat_i)
--    begin
--        if (load_i = '1') then
--            addr    <= unsigned(dat_i);
--        elsif (rising_edge(clk_i)) then
--            if (incr_i = '1') then
--                addr    <= addr + 1;
--            end if;
--        end if;
--    end process;
--
--    process(clk_i)
--    begin
--        if rising_edge(clk_i) then
--            dat_o   <= std_logic_vector(addr);
--        end if;
--    end process;

    --
    -- Use an adder and a counter. While this requires more resources than a
    -- simple adder, it makes the design faster.
    --
    count : process (clk_i, load_i)
    begin
        if (load_i = '1') then
            offs <= (others => '0');
        elsif (rising_edge(clk_i)) then
            if (incr_i = '1') then
                offs <= offs + 1;
            end if;
        end if;
    end process;
    
    reg : process (clk_i)
    begin
        if (rising_edge(clk_i)) then
            if (load_i = '1') then
                addr    <= unsigned(dat_i);
            end if;
        end if;
    end process;
    
    adder : process (clk_i, load_i)
    begin
        if (load_i = '1') then
            dat_o   <= (others => '0');
        elsif (rising_edge(clk_i)) then
            dat_o   <= std_logic_vector(addr + offs);
        end if;
    end process;
end behavioral;

