--
-- Copyright (c) 2011 Philip Schulz <phs@deadc0.de>
-- All rights reserved.
--

library ieee;
use ieee.std_logic_1164.all;

entity i2c_sync is
generic (
    depth   : natural := 4;
    delay   : natural := 1;
    divider : natural := 2
);
port (
    clk_i   : in    std_logic;

    -- Input Signals from I2C bus, not in synch with clk_i
    sda_i   : in    std_logic;
    scl_i   : in    std_logic;

    -- Output Signals, indicating I2C Bus Conditions
    start_o : out   std_logic;
    stop_o  : out   std_logic;
    pos_o   : out   std_logic;
    neg_o   : out   std_logic;
    dat_o   : out   std_logic
);
end i2c_sync;

architecture behavioral of i2c_sync is
    signal counter  : integer range 0 to (divider - 1) := 0;
    signal sdasr    : std_logic_vector((depth - 1) downto 0);
    signal sclsr    : std_logic_vector((depth - 1) downto 0);
    signal scldly   : std_logic_vector((delay - 1) downto 0);
    
    -- So XST can cope with the code below in a generic way.
    signal allhi    : std_logic_vector((depth - 1) downto 0);
    signal alllo    : std_logic_vector((depth - 1) downto 0);
    
    signal sdapos   : std_logic;
    signal sdaneg   : std_logic;
    
    -- For Simulation
    signal sda      : std_logic;
    signal scl      : std_logic;
begin
    -- So XST can cope with the code below in a generic way.
    allhi <= (others => '1');
    alllo <= (others => '0');

    -- For Simulation
    with scl_i select scl <= '0' when '0', '1' when others;
    with sda_i select sda <= '0' when '0', '1' when others;

    sync : process
    begin
        wait until rising_edge(clk_i);
        
        if (counter = 0) then
            -- SDA Positive Edge
            if ((sdasr(depth - 1) = '0')
              and (sdasr((depth - 2) downto 0) = allhi((depth - 2) downto 0))) then
                sdapos <= '1';
            else
                sdapos <= '0';
            end if;

            -- SDA Negative Edge
            if ((sdasr(depth - 1) = '1')
              and (sdasr((depth - 2) downto 0) = alllo((depth - 2) downto 0))) then
                sdaneg <= '1';
            else
                sdaneg <= '0';
            end if;
            
            -- SCL Positive Edge           
            if ((sclsr(depth - 1) = '0')
              and (sclsr((depth - 2) downto 0) = allhi((depth - 2) downto 0))) then
                pos_o <= '1';
            else
                pos_o <= '0';
            end if;
            
            -- SCL Negative Edge
            if ((sclsr(depth - 1) = '1')
              and (sclsr((depth - 2) downto 0) = alllo((depth - 2) downto 0))) then
                neg_o <= '1';
            else
                neg_o <= '0';
            end if;
            
            -- Shift Register
            sclsr   <= sclsr((depth - 2) downto 0) & scldly(delay - 1);
            sdasr   <= sdasr((depth - 2) downto 0) & sda;

            -- SDA Output
            dat_o <= sdasr(depth - 1);

            -- START Condition
            if ((sclsr = allhi) and (sdaneg = '1')) then
                start_o <= '1';
            else
                start_o <= '0';
            end if;

            -- STOP Condition
            if ((sclsr = allhi) and (sdapos = '1')) then
                stop_o <= '1';
            else
                stop_o <= '0';
            end if;
        
            -- Pre-divider
            counter <= (divider - 1);
        else
            start_o <= '0';
            stop_o  <= '0';
            pos_o   <= '0';
            neg_o   <= '0';
        
            counter <= (counter - 1);
        end if;
        
        scldly  <= scldly((delay - 2) downto 0) & scl;        
    end process sync;

end behavioral;

