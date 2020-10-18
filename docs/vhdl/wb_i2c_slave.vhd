--
-- Copyright (c) 2011 Philip Schulz <phs@deadc0.de>
-- All rights reserved.
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;

entity wb_i2c_slave is
generic (
    -- Number of Bytes in one I2C data nibble, should be left at 8 for
    -- I2C compabitility.
    dat_sz  : natural := 8; 

    -- Width of target register (Number of Bits).
    off_sz  : natural := 8;

    -- Page size. Determines granulatiry of addressing. Given in powers of two,
    -- i.e. one page contains 2**pg_sz nibbles (Size of nibble == dat_sz)
    pg_sz   : natural := 1;

    -- Increment Target Register. If set, consecutive r/w access cycles will
    -- increment the internal target register by one.
    increment_target : std_logic := '1';

    -- I2C Device Address.
    i2c_adr : std_logic_vector(7 downto 0) := x"A2"
);
port (
    clk_i       : in  std_logic;
    rst_i       : in  std_logic;
    --
    -- Whishbone Interface
    --
    adr_o       : out std_logic_vector((off_sz - 1) downto (pg_sz - 1));
    dat_i       : in  std_logic_vector((dat_sz - 1) downto 0);
    dat_o       : out std_logic_vector((dat_sz - 1) downto 0);
    ack_i       : in  std_logic;
    cyc_o       : out std_logic;
    stall_i     : in  std_logic;
    err_i       : in  std_logic;
    lock_o      : out std_logic;
    rty_i       : in  std_logic;
    sel_o       : out std_logic_vector((pg_sz - 1) downto 0);
    stb_o       : out std_logic;
    we_o        : out std_logic;
    --
    -- I2C Interface
    --
    i2c_scl_io  : inout std_logic;
    i2c_sda_io  : inout std_logic
);
end wb_i2c_slave;

architecture behavioral of wb_i2c_slave is
    -- Number of Bytes in one I2C data nibble, should be left at 8 for
    -- I2C compabitility.
    constant i2c_nibble_sz  : natural := 8;

    component i2c_sync is
    generic (
        depth   : natural := 8;
        delay   : natural := 2;
        divider : natural := 1
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
    end component i2c_sync;

    component register_shl is
    generic (
        width : natural := 8
    );
    port (
        clk_i : in  STD_LOGIC;
        we_i  : in  STD_LOGIC;
        dat_i : in  STD_LOGIC;
        dat_o : out STD_LOGIC_VECTOR ((width - 1) downto 0)
    );
    end component register_shl;

    component register_shr_pload is
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
    end component register_shr_pload;

    component register_addr is
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
    end component register_addr;

    --
    -- I2C finite state machine related definitions
    --
    type i2c_state_t is (
      idle,             start,              dev_addr_shift,     dev_addr_wait,
      dev_addr_ack,     rdy,                target_shift,       target_wait,
      target_ack,       wr_rdy,             wr_rx,              wr_wait,
      wb_wr,            wr_ack,             wr_nack,            rd_wait,
      wb_rd,            rd_tx,              rd_ack
    );
    signal i2c_state : i2c_state_t;

    --
    -- Internal Signal Declarations
    --
    signal  i2c_start           : std_logic;
    signal  i2c_stop            : std_logic;
    signal  i2c_edge            : std_logic;
    signal  i2c_falling         : std_logic;
    signal  i2c_dat             : std_logic;

    --
    -- Device Address Signals
    --
    signal  dev_addr_shl        : std_logic;
    signal  dev_addr            : std_logic_vector(i2c_adr'range);

    --
    -- Target Register Signals
    --
    signal  target_reg_shl      : std_logic;
    signal  target_reg          : std_logic_vector((off_sz - 1) downto 0);

    --
    -- Address Register Signals
    --
    signal  wb_addr_load        : std_logic;
    signal  wb_addr_incr        : std_logic;
    signal  wb_addr             : std_logic_vector((off_sz - 1) downto 0);

    --
    -- Counter Signals
    --
    signal  cnt                 : natural range 0 to (i2c_nibble_sz - 1);
    signal  cnt_ce              : std_logic;
    signal  cnt_rst             : std_logic;
    
    signal  cnt_target          : natural range 0 to ((off_sz / i2c_nibble_sz) - 1);

    --
    -- Data Register Whishbone -> I2C (Read Cycles) Signals
    --
    signal  rd_data             : std_logic;
    signal  rd_data_load        : std_logic;
    signal  rd_data_shift       : std_logic;

    --
    -- Data Register I2C -> Whishbone (Write Cycles) Signals
    --
    signal  wr_data_shl         : std_logic;
    signal  wr_data             : std_logic_vector((dat_sz - 1) downto 0);

    --
    -- Misc. Signals
    --
    signal  i2c_scl_outp        : std_logic;
    signal  i2c_scl_we          : std_logic;
    signal  i2c_sda_outp        : std_logic;
    signal  i2c_sda_we          : std_logic;
    
begin
    iic_sync : i2c_sync
    generic map (
        depth   => 8,
        delay   => 2,
        divider => 1
    )
    port map (
        clk_i   => clk_i,

        -- Input Signals from I2C bus, not in synch with clk_i
        sda_i   => i2c_sda_io,
        scl_i   => i2c_scl_io,

        -- Output Signals, indicating I2C Bus Conditions
        start_o => i2c_start,
        stop_o  => i2c_stop,
        pos_o   => i2c_edge,
        neg_o   => i2c_falling,
        dat_o   => i2c_dat
    );

    device_address : register_shl
    generic map (
        width   => dat_sz
    )
    port map (
        clk_i   =>  clk_i, 
        we_i    =>  dev_addr_shl, 
        dat_i   =>  i2c_dat,
        dat_o   =>  dev_addr
    );

    target_register : register_shl
    generic map (
        width   => off_sz
    )
    port map (
        clk_i   =>  clk_i, 
        we_i    =>  target_reg_shl, 
        dat_i   =>  i2c_dat,
        dat_o   =>  target_reg
    );

     addr_register : register_addr
     generic map (
         width   => off_sz
     )
     port map (
         clk_i   => clk_i,
         load_i  => wb_addr_load,
         incr_i  => wb_addr_incr,
         dat_i   => target_reg,
         dat_o   => wb_addr
     );
 
    wb_to_i2c : register_shr_pload
    generic map (
        width   => dat_sz
    )
    port map (
        clk_i   =>  clk_i,
        pdat_i  =>  dat_i,
        sdat_i  =>  '-', 
        sdat_o  =>  rd_data,
        load_i  =>  rd_data_load,
        shr_i   =>  rd_data_shift
    );

    i2c_to_wb : register_shl
    generic map (
        width   => dat_sz
    )
    port map (
        clk_i   =>  clk_i, 
        we_i    =>  wr_data_shl,
        dat_i   =>  i2c_dat,
        dat_o   =>  wr_data
    );

    counter : process (clk_i)
    begin
        if (rising_edge(clk_i)) then
            if (cnt_rst = '1') then
                cnt <= 0;
            elsif (cnt_ce = '1') then
                cnt <= cnt + 1;
            end if;
        end if;
    end process;
    
    process
    begin
        wait until rising_edge(clk_i);

        -- Default values for signals
        dev_addr_shl    <= '0';
        target_reg_shl  <= '0';

        rd_data_load    <= '0';
        rd_data_shift   <= '0';

        wr_data_shl     <= '0';

        i2c_scl_outp    <= '-';
        i2c_scl_we      <= '0';

        i2c_sda_outp    <= '-';
        i2c_sda_we      <= '0';

        -- Default values for Whishbone Signals
        adr_o           <= (others => '-');
        dat_o           <= (others => '-'); 
        sel_o           <= (others => '-'); 
        we_o            <= '-';

        stb_o           <= '0'; 
        lock_o          <= '-'; 

        wb_addr_load    <= '0';
        wb_addr_incr    <= '0';

        cnt_ce          <= '0';
        cnt_rst         <= '0';

        case i2c_state is
        when idle =>
            cyc_o       <= '0';
            
            if (i2c_start = '1') then
                cnt_rst     <= '1';

                i2c_state   <= start;
            end if;
       
        when start =>
            if (i2c_edge = '1') then
                dev_addr_shl<= '1';
                cnt_ce      <= '1';

                i2c_state   <= dev_addr_shift;
            end if;

        when dev_addr_shift =>
            if (i2c_edge = '1') then
                dev_addr_shl<= '1';
                cnt_ce      <= '1';

                if (cnt = i2c_adr'high) then
                    i2c_state <= dev_addr_wait;
                end if;
            end if;

        when dev_addr_wait =>
            if (i2c_falling = '1') then
                if (dev_addr(i2c_adr'high downto 1)
                  = i2c_adr(i2c_adr'high downto 1)) then
                    i2c_state <= dev_addr_ack;
                else
                    i2c_state <= idle;
                end if;
            end if;
            
        when dev_addr_ack =>
            i2c_sda_outp    <= '0';
            i2c_sda_we      <= '1';

            if (i2c_falling = '1') then
                cnt_rst     <= '1';
                cnt_target  <= 0;
                
                if (dev_addr(0) = '0') then
                    i2c_state       <= rdy;
                else
                    i2c_scl_outp    <= '0';
                    i2c_scl_we      <= '1';

                    cyc_o           <= '1';

                    i2c_state       <= wb_rd;
                end if;
            end if;

        when rdy =>
            if (i2c_edge = '1') then
                target_reg_shl  <= '1';

                cnt_ce      <= '1';

                i2c_state   <= target_shift;
            end if;

        when target_shift =>
            if (i2c_edge = '1') then
                target_reg_shl  <= '1';

                cnt_ce          <= '1';
           
                if (cnt = (i2c_nibble_sz - 1)) then
                    i2c_state  <= target_wait;
                else
                    i2c_state  <= target_shift;
                end if;
            
            end if;

        when target_wait =>
            if (i2c_falling = '1') then
                i2c_sda_outp    <= '0';
                i2c_sda_we      <= '1';

                i2c_state       <= target_ack;
            end if;

        when target_ack =>
            i2c_sda_outp    <= '0';
            i2c_sda_we      <= '1';

            if (i2c_falling = '1') then
                cnt_rst <= '1';
                if (cnt_target = ((off_sz / i2c_nibble_sz) - 1)) then
                    wb_addr_load    <= '1';

                    cyc_o           <= '1';

                    i2c_state       <= wr_rdy;
                else
                    cnt_target      <= cnt_target + 1;
                    i2c_state       <= rdy;
                end if;            
            end if;

        when wr_rdy =>
            if (i2c_edge = '1') then
                cnt_ce      <= '1';
                wr_data_shl <= '1';

                i2c_state   <= wr_rx;
            end if;

        when wr_rx =>
            --
            -- State accepts the START condition as an I2C master may
            -- send a "Repeated START" which needs to be handled here.
            --
            if (i2c_start = '1') then
                cnt_rst     <= '1';

                i2c_state   <= start;
            elsif (i2c_edge = '1') then
                cnt_ce      <= '1';
                wr_data_shl <= '1';
                
                if (cnt = (i2c_nibble_sz - 1)) then
                    i2c_state <= wr_wait;
                end if;
            end if;

        when wr_wait =>
            if (i2c_falling = '1') then
                i2c_scl_outp<= '0';
                i2c_scl_we  <= '1';
                
                i2c_state   <= wb_wr;
            end if;

        when wb_wr =>
            i2c_scl_outp    <= '0';
            i2c_scl_we      <= '1';

            adr_o           <= wb_addr;
            we_o            <= '1';
            sel_o           <= (others => '1');

            dat_o           <= wr_data;

            lock_o          <= '1';
            stb_o           <= '1';

            if (ack_i = '1') then
                wb_addr_incr<= increment_target;

                i2c_sda_outp<= '0';
                i2c_sda_we  <= '1';

                cnt_rst     <= '1';

                i2c_state   <= wr_ack;
            elsif ((rty_i = '1') or (err_i = '1')) then
                i2c_sda_outp<= '1';
                i2c_sda_we  <= '1';
                
                cnt_rst     <= '1';

                i2c_state   <= wr_nack;
            end if;

        when wr_ack =>
            i2c_sda_outp    <= '0';
            i2c_sda_we      <= '1';

            if (i2c_falling = '1') then
                i2c_state <= wr_rdy;
            end if;

        when wr_nack =>
            i2c_sda_outp    <= '1';
            i2c_sda_we      <= '1';

            if (i2c_falling = '1') then
                i2c_state <= wr_rdy;
            end if;

        when rd_wait =>
            if (i2c_falling = '1') then
                i2c_scl_outp    <= '0';
                i2c_scl_we      <= '1';

                i2c_state       <= wb_rd;
            end if;

        when wb_rd =>
            i2c_scl_outp    <= '0';
            i2c_scl_we      <= '1';

            adr_o           <= wb_addr;
            we_o            <= '0';
            sel_o           <= (others => '1');

            lock_o          <= '1';
            stb_o           <= '1';

            if (ack_i = '1') then
                wb_addr_incr<= increment_target;

                cnt_rst     <= '1';
                rd_data_load<= '1';            

                i2c_sda_outp<= rd_data;
                i2c_sda_we  <= '1';

                i2c_state   <= rd_tx;
            elsif ((rty_i = '1') or (err_i = '1')) then
                i2c_state   <= idle;
            end if;

        when rd_tx =>
            i2c_sda_outp    <= rd_data;
            i2c_sda_we      <= '1';

            if (i2c_falling = '1') then
                if (cnt = (i2c_nibble_sz - 1)) then
                    i2c_state       <= rd_ack;
                else
                    rd_data_shift   <= '1';

                    cnt_ce          <= '1';
                end if;
            end if;

        when rd_ack =>
            if (i2c_edge = '1') then
                if (i2c_dat = '0') then
                    i2c_state   <= rd_wait;
                else
                    i2c_state   <= idle;
                end if;
            end if;
        end case;
        
        if ((rst_i = '1') or (i2c_stop = '1')) then
            i2c_state <= idle;
        end if;
    end process;

    with ((i2c_scl_we = '1') and (i2c_scl_outp = '0')) select i2c_scl_io <= '0' when true, 'Z' when others;
    with ((i2c_sda_we = '1') and (i2c_sda_outp = '0')) select i2c_sda_io <= '0' when true, 'Z' when others;
end behavioral;

