-----------------------------------------------------------------------------
-- databus_master.vhd
-- This file provides a simple data bus master design that can
-- interface with an 8 bit command bus.
--
-- Command Formats:
--
-- The commands are 8 bits in length.
--
-- In general this is the read/write command format for the databus.
--
-- Bit 7                      Bit 0
--  R/!W  A7 A6 A5 A4 A3 A2 A1 A0
--
-- There are 2 exceptions:
-- 0xFF and 0x7F are idle commands (they do nothing)
--
-- this means there are 0 -> 126 address in the databus master.
-- each address addresses 8 bits of memory.
--
-- Peter Fetterer <kb3gtn@gmail.com>
----------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity databus_master is
    Generic (
        slave_latency_max   : integer := 3       -- latency from read/write strb to when the 
                                                 -- operation is complete in number of i_clk cycles.
                                                 -- 3 would give a slave 3 clock cycles to perform 
                                                 -- the needed operation.
    );
    Port (
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
end entity;

architecture b of databus_master is

    ---------------------------------------------
    --  Signals 
    ---------------------------------------------
    signal db_state             : integer;
    signal slv_latency_cntr     : integer;

    signal db_data_read         : std_logic_vector( 7 downto 0);
    signal db_data_write        : std_logic_vector( 7 downto 0);
    signal db_addr              : std_logic_vector( 6 downto 0);
    signal db_wr_active         : std_logic;
    signal db_rd_active         : std_logic;

begin

    o_db_addr <= db_addr;
    o_db_write_data <= db_data_write;
    o_db_write_strb <= db_wr_active;
    o_db_cmd_data_out <= db_data_read;

    db_state_machine : process( i_clk )
    begin
        if ( rising_edge( i_clk ) ) then
            if ( i_srst = '1' ) then
                -- in reset
                db_state <= 0;
                o_db_cmd_rdy <= '0';
                db_addr <= (others=>'0');
                db_data_write <= (others=>'0');
                o_db_read_strb <= '0';
                db_wr_active <= '0';
                slv_latency_cntr <= 0;
            else
                -- state mux
                case db_state is
                when 0 =>
                    -- start of cycle
                    -- signal ready for a new command
                    o_db_cmd_rdy <= '1';
                    db_wr_active <= '0';
                    o_db_read_strb <= '0';
                    db_state <= 1;                    
                when 1 =>
                    -- wait for a command
                    if ( i_db_cmd_wstrb = '1' ) then
                        -- we have a command to process
                        if ( i_db_cmd_in = x"FF" ) or ( i_db_cmd_in = x"7F" ) then
                            -- idle command.. ignore
                            db_state <= 1;  -- stay here, wait for next cmd
                        else
                            -- this is a real command
                            db_addr <= i_db_cmd_in(6 downto 0); -- get address for cmd..
                            -- Is it a read or a write....
                            if ( i_db_cmd_in(7) = '1' ) then
                                -- this is a read register command
                                -- issue read request on address
                                o_db_read_strb <= '1';
                                o_db_cmd_rdy <= '0';  -- busy
                                db_state <= 2;
                            else
                                -- this is a write register command
                                -- issue write request
                                db_data_write <= i_db_cmd_data_in;
                                db_wr_active <= '1';
                                o_db_cmd_rdy <= '0'; -- busy
                                db_state <= 4;
                            end if;
                        end if;
                    end if;
                when 2 =>
                    -- read command started...
                    -- need to wait for slave_latency_max clock cycles
                    if ( slv_latency_cntr = slave_latency_max ) then
                        -- slave latency counter expired..
                        -- push down read strobe when timer expires
                        o_db_read_strb <= '0';
                        db_data_read <= i_db_read_data; -- sample read bus into local register.
                        slv_latency_cntr <= 0;
                        db_state <= 0;
                    else
                        slv_latency_cntr <= slv_latency_cntr + 1;
                    end if;
                -- state 3 removed..
                when 4 =>
                    -- write request wait period.
                    db_wr_active <= '0';
                    -- need to wait for slave_latency_max clock cycles
                    if ( slv_latency_cntr = slave_latency_max ) then
                        -- slave latency counter expired..
                        slv_latency_cntr <= 0;
                        -- write should be complete now..  
                        db_state <= 0;
                    else
                        slv_latency_cntr <= slv_latency_cntr + 1;
                    end if;
                when others =>
                    db_state <= 0;
                end case;
            end if;
        end if;
    end process;
                     
end architecture;

