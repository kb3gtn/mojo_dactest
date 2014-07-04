-----------------------------------------------------------------------------
-- SPI_MASTER.vhd
--
-- This block is a SPI Master uart that is designed to interface with
-- a simple databus master address/data bus inteface.
--
-- This register exposes 3 registers
--
-- A status Register, and a data registers, Clock Rate Register
--
-- Conf register:
--
--   Bit0 - Chip Select 0 line value.. '1' -- asserted, '0' -- de-asserted
--   Bit1 - Chip Select 1 line value.. '1' -- asserted, '0' -- de-asserted
--   Bit2 - Chip Select 2 line value.. '1' -- asserted, '0' -- de-asserted
--   Bit3 - Chip Select 4 line value.. '1' -- asserted, '0' -- de-asserted
--   Bit4 - Clk Edge for data change.. '1' -- falling, '0' -- rising (clk polarity)
--   Bit5 - Data Polarity.. '1' -- Inverted, '0' -- Normal
--   Bit6 - Bit Order..  '1' -- msb first, '0' -- lsb first
--   Bit7 - Reset..  '1' asserted, '0' de-asserted ( running )
--
--   Chip selects are basically GPIO..
--   Can have multiple chip select asserted if you so desire..
--
-- Data register:
--   Bit(7 - 0)  -- data byte to transmit
--
--
-- Clock Rate Register
-- This register takes a value that defines the clock rate used in SPI operations
--
------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_master is
    generic (
        -- default address for this module to use..
        data_reg_addr       : std_logic_vector( 6 downto 0) := "000000";  -- address 0
        conf_reg_addr       : std_logic_vector( 6 downto 0) := "000001";  -- address 1
        baud_reg_addr       : std_logic_vector( 6 downto 0) := "000010"   -- address 2
    );
    port (
        i_clk               : in    std_logic;  -- input system clock (50 MHz)
        i_srst              : in    std_logic;  -- input sync reset to i_clk
        -- spi interface   
        o_spi_sclk          : out   std_logic;  -- spi clock signal
        o_spi_mosi          : out   std_logic;  -- spi master data output
        i_spi_miso          : in    std_logic;  -- spi master data input
        o_spi_cs_n          : out   std_logic_vector( 3 downto 0); -- chip select signals. (active low)
        -- data bus interface
        i_db_addr           : in    std_logic_vector( 6 downto 0);
        i_db_wr_strb        : in    std_logic;
        i_db_rd_strb        : in    std_logic;
        i_db_wr_data        : in    std_logic_vector( 7 downto 0 );
        o_db_rd_data        : out   std_logic_vector( 7 downto 0 )
    );
end entity;

architecture b of spi_master is

    --##########################################
    --# SIGNALS
    --##########################################

    signal app_rst          : std_logic;

    signal spi_sclk_strb    : std_logic; -- clock enable strobe for sclk state change. (2 time clock period)
    signal spi_bit_strb     : std_logic; -- bit shift should occur..

    signal spi_sclk         : std_logic; -- clock normal (data change on rising edge)
    signal spi_sclk_n       : std_logic; -- clock inverted (data change on falling edge)

    signal spi_mosi         : std_logic; -- mosi normal
    signal spi_mosi_n       : std_logic; -- mosi inverted
    signal spi_miso         : std_logic; -- miso normal
    signal spi_miso_n       : std_logic; -- miso inverted

    signal db_rd_data       : std_logic_vector( 7 downto 0);

    signal spi_register     : std_logic_vector( 7 downto 0 ); -- spi shift register
    signal chip_selects     : std_logic_vector( 3 downto 0 ); -- chip select outputs (gpio)

    signal spi_active       : std_logic; -- spi transaction in progress
    signal spi_start_strb   : std_logic; -- start spi transaction strobe/flag/clock enable
    signal spi_bit_cntr     : integer;   -- number of bits sent

    signal baud_cntr        : unsigned( 11 downto 0 );
    signal baud_val         : unsigned( 11 downto 0 );

    -- memory map regsiters
    signal baud_reg         : std_logic_vector( 7 downto 0 );
    signal conf_reg         : std_logic_vector( 7 downto 0 );
    signal spi_data_reg     : std_logic_vector( 7 downto 0 ); 


begin

    -- internal register to output bus
    o_db_rd_data <= db_rd_data;

    -- chip select outputs
    o_spi_cs_n <= conf_reg( 3 downto 0 );

    -- databus interface
    db_slave : process( i_clk )
    begin
        if ( rising_edge( i_clk ) ) then
            if ( i_srst = '1' ) then
                app_rst <= '0';
                baud_reg <= (others=>'0');
                conf_reg <= (others=>'0');
                db_rd_data <= (others=>'Z');
            else
                -- writes over reads
                if ( i_db_wr_strb = '1' ) then
                    -- we have a write on the bus
                    -- mux based on address
                    if ( i_db_addr = data_reg_addr ) then 
                        spi_data_reg <= i_db_wr_data;
                        spi_start_strb <= '1';  -- signal we have a new byte to send..
                    end if;
                    if ( i_db_addr = baud_reg_addr ) then 
                        baud_reg <= i_db_wr_data;
                    end if;
                    if ( i_db_addr = conf_reg_addr ) then
                        conf_reg <= i_db_wr_data;
                    end if;
                    -- in all cases, we are not performing a read..
                    -- high Z our drive on the read bus
                    db_rd_data <= (others=>'Z');
                else
                    spi_start_strb <= '0';
                    if ( i_db_rd_strb = '1' ) then
                        if( i_db_addr = data_reg_addr ) then 
                            db_rd_data <= spi_register;
                        end if;
                        if ( i_db_addr = baud_reg_addr ) then 
                            db_rd_data <= baud_reg;
                        end if;
                        if ( i_db_addr = conf_reg_addr ) then 
                            db_rd_data <= conf_reg;
                        end if;
                    else
                        db_rd_data <= (others=>'Z'); -- high Z bus
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- power of 2 scaling factor to baud value from memory mapped register 
    -- to internal counter limit..
    baud_val <= unsigned( "00" & baud_reg & "00" );  -- multiply by 4
                 
    -- simple clock divider to get
    -- bit rate for spi uart.
    baud_gen : process( i_clk )
    begin
        if ( rising_edge(i_clk) ) then
            if ( i_srst = '1' or app_rst = '1' ) then
                baud_cntr <= (others=>'0');
                spi_sclk_strb <= '0';
            else
                if ( baud_cntr = baud_val ) then
                    spi_sclk_strb <= '1';  -- next bit period strobe..
                    baud_cntr <= (others=>'0');
                else
                    spi_sclk_strb <= '0';
                    baud_cntr <= baud_cntr + 1;
                end if;
            end if;
        end if;
    end process;

    -- generate inverted/normal sclk as needed
    o_spi_sclk <= conf_reg(4) xor spi_sclk;  -- if conf_reg = '1', clock will be inverted.

    -- update spi_sclk when we get a strobe.
    clk_gen : process( i_clk )
    begin
        if ( rising_edge( i_clk ) ) then
            if ( i_srst = '1' or app_rst = '1' ) then
                spi_sclk <= '0';
                spi_bit_strb <= '0';
            else
                -- spi_active is cleared by the spi_shiftreg when it has shifted out..
                -- spi_active gets set when a spi_start_strb is recevied in spi_shiftreg
                -- spi_sclk_strb indicates 1/2 clock periods..
                if ( spi_sclk_strb = '1' and spi_active = '1' ) then
                    if ( spi_sclk = '1' ) then
                        spi_sclk <= '0';
                        spi_bit_strb <= '0';
                    else
                        if ( spi_bit_cntr = 8 ) then
                            spi_sclk <= '0';  -- dribble clock skip..
                        else
                            spi_sclk <= '1';
                        end if;
                        spi_bit_strb <= '1';  -- next bit in shift register..
                    end if;
                end if;
                if ( spi_active = '0' ) then
                    spi_sclk <= '0';
                end if;
                if ( spi_sclk_strb = '0' ) then
                    spi_bit_strb <= '0';
                end if;
            end if;
        end if;
    end process;

    -- SPI shift register
    spi_shiftreg : process( i_clk )
    begin
        if ( rising_edge( i_clk ) ) then
            if ( i_srst = '1' or app_rst = '1' ) then
                spi_register <= (others=>'0');
                spi_bit_cntr <= 0;
                spi_active <= '0';
                spi_mosi <= '0';
            else
                if ( spi_active = '0' and spi_start_strb = '1' ) then 
                    spi_active <= '1';
                    spi_register <= spi_data_reg; -- load in new contents to send
                    spi_bit_cntr <= 0;
                else
                    if ( spi_bit_strb = '1' and spi_active = '1' ) then
                        if ( spi_bit_cntr = 8) then 
                            spi_bit_cntr <= 0;
                            spi_active <= '0';
                        else 
                            spi_bit_cntr <= spi_bit_cntr + 1;
                            if ( conf_reg(6) = '1' ) then
                                -- send MSB first
                                spi_mosi <= spi_register(7);
                                spi_register <= spi_register( 6 downto 0 ) & spi_miso;
                            else
                                -- send LSB first
                                spi_mosi <= spi_register(0);
                                spi_register <= spi_miso & spi_register( 7 downto 1 );
                            end if;
                        end if;
                    end if;
                    if ( spi_active = '0' ) then
                        spi_mosi <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- data polarity selector
    -- also performs sampling of input data line to i_clk domain
    spi_pol_select : process( i_clk )
    begin
        if ( rising_edge( i_clk ) ) then
            if ( i_srst = '1' or app_rst = '1' ) then
                o_spi_mosi <= '0';
                spi_miso <= '0';
            else
                if ( conf_reg(5) = '1' ) then
                    -- use inverted data
                    o_spi_mosi <= not spi_mosi;
                    spi_miso <= not i_spi_miso;
                else
                    -- use normal data
                    o_spi_mosi <= spi_mosi;
                    spi_miso <= i_spi_miso;
                end if;
            end if;
        end if;
    end process;        

end architecture; 
                    

                         



