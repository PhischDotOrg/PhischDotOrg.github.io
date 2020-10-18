--
-- Copyright (c) 2011-2013, Philip Schulz <phs@phisch.org>
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity wb_gpio is
generic (
    dat_sz  : natural := 8
);
port (
    clk_i  : in  std_logic;
    rst_i  : in  std_logic;
    --
    -- Whishbone Interface
    --
    dat_i  : in  std_logic_vector((dat_sz - 1) downto 0);
    dat_o  : out std_logic_vector((dat_sz - 1) downto 0);
    adr_i  : in  std_logic_vector(1 downto 0);
    cyc_i  : in  std_logic;
    lock_i : in  std_logic;
    sel_i  : in  std_logic;
    we_i   : in  std_logic;
    ack_o  : out std_logic;
    err_o  : out std_logic;
    rty_o  : out std_logic;
    stall_o: out std_logic;
    stb_i  : in  std_logic;
    --
    -- GPIO Interface
    --
    gp_io  : inout std_logic_vector((dat_sz - 1) downto 0)
);
end wb_gpio;

architecture Behavioral of wb_gpio is
    constant    depth   : natural := 2;
    type gpio_buffer is array(integer range (depth - 1) downto 0) of std_logic_vector((dat_sz - 1) downto 0);
    
    -- Internal Signals
    signal gpio         : std_logic_vector((dat_sz - 1) downto 0);
    
    -- Internal Registers
    signal gpio_outp    : std_logic_vector((dat_sz - 1) downto 0);
    signal gpio_sr      : gpio_buffer;

    -- Wishbone accessible Registers
    signal  reg_ena     : std_logic_vector((dat_sz - 1) downto 0);
    signal  reg_mask    : std_logic_vector((dat_sz - 1) downto 0);
begin
    shift_register : process
    begin
        wait until rising_edge(clk_i);
        
        gpio_sr <= gpio_sr((gpio_sr'high - 1) downto 0) & gp_io;
    end process;

    tristate : for i in (dat_sz - 1) downto 0
    generate
        with reg_ena(i) select
            gp_io(i) <= 'Z' when '0', gpio_outp(i) when others;
    end generate;

    gpio <= (gpio_sr(gpio_sr'high) and not reg_mask) or (dat_i and reg_mask);

    rty_o   <= '0';
    err_o   <= '0';
    stall_o <= '0';

    sync : process
    begin
        wait until rising_edge(clk_i);

        if (stb_i = '1') then
            ack_o <= '1';
            
            if (we_i = '1') then
                case adr_i is
                when "00" =>
                    gpio_outp   <= dat_i;
                when "01" =>
                    reg_ena     <= dat_i;
                when "10" =>
                    reg_mask    <= dat_i;
                when "11" =>
                    gpio_outp   <= gpio;
                when others =>
                    dat_o   <= (others => '-');
                end case;
            else
                case adr_i is
                when "00" =>
                    dat_o   <= gpio_sr(gpio_sr'high);
                when "01" =>
                    dat_o   <= reg_ena;
                when "10" =>
                    dat_o   <= reg_mask;
                when "11" =>
                    dat_o   <= gpio_sr(gpio_sr'high);
                when others =>
                    dat_o   <= (others => '-');
                end case;
            end if;
        else
            ack_o <= '0';
        end if;
    end process sync;
end Behavioral;

