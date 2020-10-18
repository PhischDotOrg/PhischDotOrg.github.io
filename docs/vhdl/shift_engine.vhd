
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity shift_engine is
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
    cpol_i  : in  std_logic;   -- SPI Clock Polarity
    cpha_i  : in  std_logic;   -- SPI Clock Phase
    div_i   : in  natural range 2 to width;         -- SPI Clock Divider, relative to clk_i

    cnt_i   : in  integer range 1 to (width - 1);   -- Number of Bits to Shift

    start_i : in  std_logic;
    done_o  : out std_logic;

    -- Shift Signals
    sclk_o  : out std_logic;
    mosi_o  : out std_logic;
    miso_i  : in  std_logic
);
end shift_engine;

architecture Behavioral of shift_engine is
    type shift_state_t is (
        idle, enable, shift, hold, disable
    );
    signal state : shift_state_t;

    signal  miso        : std_logic;
    signal  mosi        : std_logic;
    signal  reg_rx      : std_logic_vector((width - 1) downto 0);

    signal  reg_tx      : std_logic_vector((width - 1) downto 0);
    signal  tx_load     : std_logic;

    signal  shl         : std_logic;
    
    signal  delay_cnt   : integer range 0 to (delay - 1);
    signal  shift_cnt   : integer range 0 to ((2 * width) - 1);
    
    signal  spi_delay   : integer range 0 to ((2 ** width) - 1);
    signal  spi_cnt     : integer range 0 to ((delay / 2) - 1);
    signal  spi_cnt_ld  : std_logic;
    signal  spi_clk     : std_logic;
    signal  spi_edge    : std_logic;
    signal  spi_nedge   : std_logic;
    
    signal  spi_clk_en  : std_logic;
begin
    spi_delay   <= div_i / 2;

    rx_sr : process (clk_i)
    begin
        if (rising_edge(clk_i)) then
            miso    <= miso_i;
            if (shl = '1') then        
                reg_rx  <= reg_rx((reg_rx'high - 1) downto 0) & miso;
            end if;
        end if;
    end process rx_sr;
    dat_o   <= reg_rx;

    tx_sr : process (clk_i)
    begin
        if (rising_edge(clk_i)) then
            if (tx_load = '1') then
                reg_tx  <= dat_i;
            end if;
            
            if (shl = '1') then
                reg_tx  <= reg_tx((reg_rx'high - 1) downto 0) & '-';
            end if;

            mosi <= reg_tx(reg_tx'high);
        end if;
    end process tx_sr;
    mosi_o  <= mosi;


    counter : process (clk_i)
    begin
        if (rising_edge(clk_i)) then
            if (spi_cnt_ld = '1') then
                spi_cnt <= spi_delay;
            elsif (spi_clk_en = '1') then
                spi_cnt <= spi_cnt - 1;
            end if;
        end if;
    end process;
    
    clkgen : process (clk_i)
    begin
        if (rising_edge(clk_i)) then
            spi_edge    <= '0';
            spi_nedge   <= '0';

            shl         <= '0';

            spi_cnt_ld  <= '0';

            if (spi_clk_en = '1') then
                if (spi_cnt = 0) then
                    spi_cnt_ld  <= '1';

                    if (spi_clk = cpol_i) then
                        spi_edge    <= '1';

                        if (cpha_i = '1') then
                            shl <= '1';
                        end if;
                    else
                        spi_nedge   <= '1';
                    
                        if (cpha_i = '0') then
                            shl <= '1';
                        end if;
                    end if;
                    
                    spi_clk     <= not spi_clk;
                end if;
            else
                spi_clk     <= cpol_i;
            end if;
        end if;
    end process;
    sclk_o  <= spi_clk;

    fsm : process
    begin
        wait until rising_edge(clk_i);
        
        case state is
        when idle =>
            if (start_i = '1') then
                done_o      <= '0';
                tx_load     <= '1';
                
                delay_cnt   <= delay - 1;
                
                state       <= enable;
            else
                spi_clk_en  <= '0';

                done_o      <= '1';
            end if;
            
        when enable =>
            tx_load     <= '0';
        
            if (delay_cnt = 0) then
                shift_cnt   <= cnt_i;

                spi_clk_en  <= '1';
                
                state       <= shift;
            else
                delay_cnt   <= delay_cnt - 1;
            end if;

        when shift =>
            if (spi_edge = '1') then
                if (shift_cnt = 0) then
                    state       <= hold;
                else
                    shift_cnt   <= shift_cnt - 1;
                end if;
            end if;
            
        when hold =>
            if (spi_nedge = '1') then
                spi_clk_en  <= '0';
                    
                delay_cnt   <= delay - 1;
                state       <= disable;
            end if;
            
        when disable =>
            if (delay_cnt = 0) then
                state       <= idle;
            else
                delay_cnt   <= delay_cnt - 1;
            end if;
        end case;
        
        if (rst_i = '1') then
            done_o      <= '0';
            
            spi_clk_en  <= '0';

            state       <= idle;
        end if;
    end process fsm;
end Behavioral;

