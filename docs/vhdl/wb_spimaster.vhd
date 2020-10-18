library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity wb_spimaster is
generic (
    dat_sz  : natural := 8;
    slv_bits: natural := 3
);
port (
    clk_i  : in  std_logic;
    rst_i  : in  std_logic;
    --
    -- Whishbone Interface
    --
    adr_i  : in  std_logic_vector(1 downto 0);
    dat_i  : in  std_logic_vector((dat_sz - 1) downto 0);
    dat_o  : out std_logic_vector((dat_sz - 1) downto 0);
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
    -- SPI Master Signals
    --
    spi_mosi_o  : out std_logic;
    spi_miso_i  : in  std_logic;
    spi_nsel_o  : out std_logic_vector(((2 ** slv_bits) - 1) downto 0);
    spi_sclk_o  : out std_logic
);
end wb_spimaster;

architecture Behavioral of wb_spimaster is
    component shift_engine is
    generic (
        -- Width of parallel data
        width   : natural := 8;
        -- Delay after NSEL is pulled low, in ticks of clk_i
        delay   : natural := 2
    );
    port (
        -- Clocking
        clk_i   : in  std_logic;
        rst_i   : in  std_logic;

        -- Data
        dat_i   : in  std_logic_vector((width - 1) downto 0);
        dat_o   : out std_logic_vector((width - 1) downto 0);

        -- Control Signals
        cpol_i  : in std_logic;    -- SPI Clock Polarity
        cpha_i  : in std_logic;    -- SPI Clock Phase
        div_i   : in  natural range 2 to width;         -- SPI Clock Divider, relative to clk_i

        cnt_i   : in  integer range 1 to (width - 1);   -- Number of Bits to Shift

        start_i : in  std_logic;
        done_o  : out std_logic;

        -- Shift Signals
        sclk_o  : out std_logic;
        mosi_o  : out std_logic;
        miso_i  : in  std_logic
    );
    end component shift_engine;
    
    -- Internal Registers
    signal  tx_dat  : std_logic_vector((dat_sz - 1) downto 0)           := (others => '-');
    signal  rx_dat  : std_logic_vector((dat_sz - 1) downto 0)           := (others => '-');
    signal  ctrl    : std_logic_vector((dat_sz - 2) downto 0)           := (others => '0');
    signal  nsel    : std_logic_vector(((2 ** slv_bits) - 1) downto 0)  := (others => '1');
    signal  div     : std_logic_vector((dat_sz - 1) downto 0)           := (others => '1');

    signal  start   : std_logic;
    signal  done    : std_logic;

    signal  tmp_div : integer   := 2;
    signal  tmp_cnt : integer   := (dat_sz - 1);
begin
    shift : shift_engine
    generic map (
        -- Width of parallel data
        width   => dat_sz,
        -- Delay after NSEL is pulled low, in ticks of clk_i
        delay   => 2
    )
    port map (
        -- Clocking
        clk_i   => clk_i,
        rst_i   => rst_i,

        -- Data
        dat_i   => tx_dat,
        dat_o   => rx_dat,

        -- Control Signals
        cpol_i  => ctrl(4),
        cpha_i  => ctrl(5),
        div_i   => tmp_div,
        
        cnt_i   => tmp_cnt,

        start_i => start,
        done_o  => done,

        -- Shift Signals
        sclk_o  => spi_sclk_o,
        mosi_o  => spi_mosi_o,
        miso_i  => spi_miso_i
    );
    
    tmp_cnt <= to_integer(unsigned(ctrl(2 downto 0)));
    tmp_div <= to_integer(unsigned(div));
    
    process (clk_i)
    begin
        if (rising_edge(clk_i)) then
            start   <= '0';

            ack_o <= stb_i;
            err_o <= '0';
            
            if ((stb_i = '1') and (we_i = '1')) then
                case adr_i is
                when "00" =>
                    tx_dat  <= dat_i;
                when "01" =>
                    ctrl((dat_i'high - 1) downto 0) <= dat_i((dat_i'high - 1) downto 0);
                    if ((done = '0') and (dat_i(7) = '1')) then
                        ack_o   <= '0';
                        err_o   <= '1';
                    else
                        start   <= dat_i(dat_i'high);
                    end if;
                when "10" =>
                    nsel(((2 ** slv_bits) - 1) downto 0) <= dat_i(((2 ** slv_bits) - 1) downto 0);
                when "11" =>
                    div     <= dat_i;
                when others =>
                end case;
            else
                case adr_i is
                when "00" =>
                    dat_o   <= rx_dat;
                when "01" =>
                    dat_o(6 downto 0)   <= ctrl(6 downto 0);
                    dat_o(7)            <= not done;
                when "10" =>
                    dat_o(nsel'high downto 0) <= nsel;
                when "11" =>
                    dat_o   <= div;
                when others =>
                    dat_o   <= (others => '-');
                end case;
            end if;
        end if;
    end process;
    
    rty_o       <= '0';
    spi_nsel_o  <= nsel;
    stall_o     <= stb_i;
end Behavioral;

