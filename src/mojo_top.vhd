library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

Library UNISIM;
use UNISIM.vcomponents.all;


entity mojo_top is
    Port ( 
        clk50m              : in  STD_LOGIC;
        rst_n               : in  STD_LOGIC;
        --cclk                : in  STD_LOGIC; -- spi/fpga programming clock (not used).
        led                 : out  STD_LOGIC_VECTOR (7 downto 0); -- board LEDs

        -- spi interface shared with AVR and SPI flash chip (not used here)
        --spi_mosi    : in  STD_LOGIC;
        --spi_miso    : out  STD_LOGIC;
        --spi_ss      : in  STD_LOGIC;
        --spi_sck     : in  STD_LOGIC;
        --spi_channel : in  STD_LOGIC_VECTOR (3 downto 0); ( not used here)

        -- avr rs232 interface (ttl levels) ( not used here )
        -- avr_tx      : in  STD_LOGIC;
        -- avr_rx      : in  STD_LOGIC;
        -- avr_rx_busy : in  STD_LOGIC

        -- RS232
        serial_tx   : out STD_LOGIC;  -- 3rd pin up from uC outside.
        serial_rx   : in  STD_LOGIC;   -- 4th pin up from uC outside.


        -- Dac Interface
        dac_reset   : out STD_LOGIC;  
        dac_sleep   : out STD_LOGIC;   
        dac_mode    : out STD_LOGIC;   
        dac_cmode   : out STD_LOGIC;   
        dac_clk_p   : out STD_LOGIC;   
        dac_clk_n   : out STD_LOGIC;   
        dac_DB      : out signed( 11 downto 0 )
    );
end mojo_top;

architecture Behavioral of mojo_top is

    --#########################################################
    --# Component Definitions
    --#########################################################

    component uart is
    port (
        i_clk               : in    std_logic;  -- system clock
        i_srst              : in    std_logic;  -- synchronious reset, 1 - active
        i_baud_div          : in    std_logic_vector(15 downto 0);  -- clk divider to get to baud rate
        -- uart interface
        o_uart_tx           : out   std_logic;  -- tx bit stream
        i_uart_rx           : in    std_logic;  -- uart rx bit stream input
        -- fpga side
        i_tx_send             : in    std_logic_vector(7 downto 0); -- data byte in
        i_tx_send_we          : in    std_logic;  -- write enable
        o_tx_send_busy        : out   std_logic;  -- tx is busy, writes are ignored.
        o_rx_read             : out   std_logic_vector(7 downto 0); -- data byte out
        o_rx_read_valid       : out   std_logic;  -- read data valid this clock cycle
        i_rx_read_rd          : in    std_logic  -- read request, get next byte..
    );
    end component uart;

    component uart_db_interface is
    port (
        i_clk                   : in    std_logic;     -- input system clock
        i_srst                  : in    std_logic;     -- sync reset to system clock
        -- uart interface
        i_rx_data               : in    std_logic_vector( 7 downto 0);  -- data from uart
        i_rx_data_valid         : in    std_logic;     -- valid data from uart
        o_rx_read_ack           : out   std_logic;     -- tell uart we have read byte.
        o_tx_send               : out   std_logic_vector( 7 downto 0); -- tx_send data
        o_tx_send_wstrb         : out   std_logic;     -- write data strobe
        i_tx_send_busy          : in    std_logic;     -- uart is busy tx, don't write anything.. (stall)
        -- databus master interface
        o_db_cmd_wstrb          : out   std_logic;     -- write command strobe
        o_db_cmd_out            : out   std_logic_vector( 7 downto 0); -- cmd to databus master
        o_db_cmd_data_out       : out   std_logic_vector( 7 downto 0); -- write data to databus master
        i_db_cmd_data_in        : in    std_logic_vector( 7 downto 0); -- read data from databus master
        i_db_cmd_rdy            : in    std_logic  -- db is ready to process a cmd / previous cmd is complete.
    );
    end component;

    component databus_master is
    generic (
        slave_latency_max   : integer := 3       -- latency from read/write strb to when the 
                                                 -- operation is complete in number of i_clk cycles.
                                                 -- 3 would give a slave 3 clock cycles to perform 
                                                 -- the needed operation.
    );
    port (
        -- clock and resets
        i_clk               : in    std_logic;                      -- input system clock
        i_srst              : in    std_logic;                      -- sync reset to system clock
        -- db master cmd interface
        i_db_cmd_in         : in    std_logic_vector( 7 downto 0);  -- input cmd byte
        i_db_cmd_wstrb      : in    std_logic;                      -- write strobe for cmd byte
        o_db_cmd_rdy        : out   std_logic;                      -- '1' rdy to process next cmd, '0' busy
        i_db_cmd_data_in    : in    std_logic_vector( 7 downto 0);  -- input byte if cmd is a write (with wstrb)
        o_db_cmd_data_out   : out   std_logic_vector( 7 downto 0);  -- output byte if cmd was a read
        -- data bus interface
        o_db_addr           : out   std_logic_vector( 6 downto 0);  -- 6 -> 0 bit address bus (7 bits)
        o_db_write_data     : out   std_logic_vector( 7 downto 0);  -- write data 
        i_db_read_data      : in    std_logic_vector( 7 downto 0);  -- read data
        o_db_read_strb      : out   std_logic;                      -- db_read_strobe
        o_db_write_strb     : out   std_logic                       -- db_write_strobe
    );
    end component;


    component dac_test is
    port (
        i_clk               : in std_logic;
        i_rst               : in std_logic;
        ------------------------------------------
        o_dac_cmode         : out std_logic;
        o_dac_mode          : out std_logic;
        o_dac_reset         : out std_logic;
        o_dac_sleep         : out std_logic;
        o_dac_clk           : out std_logic; 
        o_dac_db            : out signed(11 downto 0);
        ------------------------------------------
        i_nco_ftw           : in unsigned(31 downto 0)
    );
    end component dac_test;


    --###########################################################
    --# Signal Definitions
    --###########################################################
    
    -- uart signals
    signal baud_div          : std_logic_vector( 15 downto 0);
    signal tx_byte           : std_logic_vector( 7 downto 0);
    signal tx_byte_we        : std_logic;
    signal tx_byte_busy      : std_logic;
    signal rx_byte           : std_logic_vector( 7 downto 0);
    signal rx_byte_valid     : std_logic;
    signal rx_byte_rd        : std_logic;

    -- data bus master signals
    signal db_cmd            : std_logic_vector( 7 downto 0 );
    signal db_cmd_wstrb      : std_logic;
    signal db_cmd_rdy        : std_logic;
    signal db_cmd_wr_data    : std_logic_vector( 7 downto 0 );
    signal db_cmd_rd_data    : std_logic_vector( 7 downto 0 );

    -- data bus interface to slaves
    signal db_addr           : std_logic_vector(6 downto 0);
    signal db_wr_data        : std_logic_vector(7 downto 0);
    signal db_rd_data        : std_logic_vector(7 downto 0);
    signal db_wr_strb        : std_logic;
    signal db_rd_strb        : std_logic;

    -- output register for driving the LEDs
    signal led_reg          : std_logic_vector(7 downto 0);

    -- nco registers
    signal nco_reg0         : unsigned( 7 downto 0 );
    signal nco_reg1         : unsigned( 7 downto 0 );
    signal nco_reg2         : unsigned( 7 downto 0 );
    signal nco_reg3         : unsigned( 7 downto 0 );
    signal nco_update_state : std_logic_vector( 3 downto 0 );
    signal nco_ftw          : unsigned( 31 downto 0 );

    signal dac_clk          : std_logic;
    signal dac_sample       : signed(11 downto 0);
    -- sync reset signal to 50 MHz clk
    signal srst             : std_logic;


begin

    led <= led_reg;
    -- led <= rx_byte;


    baud_div <= x"01B2";  -- 115200

    uart_1 : uart 
    port map (
        i_clk                   => clk50m,
        i_srst                  => srst,
        i_baud_div              => baud_div,
        -- uart interface
        o_uart_tx               => serial_tx,
        i_uart_rx               => serial_rx,
        -- fpga side
        i_tx_send               => tx_byte,
        i_tx_send_we            => tx_byte_we,
        o_tx_send_busy          => tx_byte_busy,
        o_rx_read               => rx_byte,
        o_rx_read_valid         => rx_byte_valid,
        i_rx_read_rd            => rx_byte_rd
    );

    udbi_1 : uart_db_interface
    port map (
        i_clk                   => clk50m, 
        i_srst                  => srst,
        -- uart interface
        i_rx_data               => rx_byte,
        i_rx_data_valid         => rx_byte_valid,
        o_rx_read_ack           => rx_byte_rd,
        o_tx_send               => tx_byte,
        o_tx_send_wstrb         => tx_byte_we,
        i_tx_send_busy          => tx_byte_busy,
        -- databus master interface
        o_db_cmd_wstrb          => db_cmd_wstrb,
        o_db_cmd_out            => db_cmd,
        o_db_cmd_data_out       => db_cmd_wr_data,
        i_db_cmd_data_in        => db_cmd_rd_data,
        i_db_cmd_rdy            => db_cmd_rdy
    );


    db_master_1 : databus_master
    generic map (
        slave_latency_max    => 3                -- latency from read/write strb to when the 
                                                 -- operation is complete in number of i_clk cycles.
                                                 -- 3 would give a slave 3 clock cycles to perform 
                                                 -- the needed operation.
    )
    port map (
        -- clock and resets
        i_clk                 => clk50m,   
        i_srst                => srst,
        -- db master cmd interface
        i_db_cmd_in           => db_cmd,
        i_db_cmd_wstrb        => db_cmd_wstrb,
        o_db_cmd_rdy          => db_cmd_rdy,
        i_db_cmd_data_in      => db_cmd_wr_data,
        o_db_cmd_data_out     => db_cmd_rd_data,
        -- data bus interface
        o_db_addr             => db_addr,
        o_db_write_data       => db_wr_data,
        i_db_read_data        => db_rd_data,
        o_db_read_strb        => db_rd_strb,
        o_db_write_strb       => db_wr_strb
    );


    -- generate synchronious reset signal for
    -- synchronious blocks
    rst_sync : process( clk50m )
    begin
        if ( rising_edge(clk50m) ) then
            if ( rst_n = '0' ) then
                -- reset active
                srst <= '1';
                -- for now, just hardcode the nco rate at startup
                -- 0x1AE ~= 10 Hz rate.. (10.0117176818 Hz)
                -- freq = (nco_ftw / 2^31-1)*50e6
                -- nco_ftw = ( Freq / 50e6 ) * (2^31-1)
                -- nco_ftw <= x"000001AE";
            else
                srst <= '0';
            end if;
        end if;
    end process;

    -- simple data bus slave to control LEDs on address 3
    led_ctrl : process( clk50m )
    begin
        if ( rising_edge( clk50m ) ) then
            if ( srst = '1' ) then
                led_reg <= (others=>'0');
            else
                if ( db_wr_strb = '1' ) then
                    -- if address 0x03
                    if ( db_addr = "0000011" ) then
                        led_reg <= db_wr_data;
                    end if;
                end if;
                if ( db_rd_strb = '1' ) then
                    if ( db_addr = "0000011" ) then 
                        db_rd_data <= led_reg;
                    end if;
                else
                    db_rd_data <= (others=>'Z');
                end if;
            end if;
        end if;
    end process;
                
    -- memory map register for DAC, write only registers.
    -- have to write to all 4 to update the nco_ftw. order dosn't mater.
    DAC_REGS : process( clk50m )
    begin
        if ( rising_edge(clk50m) ) then
            if ( srst = '1' ) then
                nco_ftw <= x"051eb852"; -- ~ 1 MHz cycle rate..
            else
                if ( db_wr_strb = '1' ) then
                    if ( db_addr = "0000100" ) then  -- addr 4
                        nco_reg0 <= unsigned(db_wr_data);
                        nco_update_state(0) <= '1';
                    end if;
                    if ( db_addr = "0000101" ) then  -- addr 5
                        nco_reg1 <= unsigned(db_wr_data);
                        nco_update_state(1) <= '1';
                    end if;
                    if ( db_addr = "0000110" ) then  -- addr 6
                        nco_reg2 <= unsigned(db_wr_data);
                        nco_update_state(2) <= '1';
                    end if;
                    if ( db_addr = "0000111" ) then  -- addr 7
                        nco_reg3 <= unsigned(db_wr_data);
                        nco_update_state(3) <= '1';
                    end if;
                    if ( nco_update_state <= "1111" ) then
                        nco_update_state <= (others=>'0');
                        nco_ftw <= nco_reg0 & nco_reg1 & nco_reg2 & nco_reg3;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- single ended to differental IO driver block.. (Xilinx)
    OBUFDS_inst : OBUFDS
        generic map (
            IOSTANDARD => "DEFAULT"
        )
        port map (
            O => dac_clk_p,  --  P clk pin
            OB => dac_clk_n, --  N clk pin
            I => dac_clk     --  input clock
        );    


    u_dac_test : dac_test
    port map (
        i_clk              => clk50m, 
        i_rst              => srst,
        ------------------------------------------
        o_dac_cmode        => dac_cmode,
        o_dac_mode         => dac_mode,
        o_dac_reset        => dac_reset,
        o_dac_sleep        => dac_sleep,
        o_dac_clk          => dac_clk,
        o_dac_db           => dac_sample,
        ------------------------------------------
        i_nco_ftw          => nco_ftw 
    );

    dac_sample_latch : process( dac_clk )
    begin
        if ( rising_edge(dac_clk) ) then
            dac_DB <= dac_sample;
        end if;
    end process;

end architecture;

