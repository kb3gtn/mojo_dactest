-------------------------------------------------------------------------------
-- uart_db_interface.vhd
--
-- This block is a state machine that interfaces that
-- translates the uart data stream into write/read commands
-- with the data bus master.
--
-- Note: There is a design simplification going on in this code..
--   There is an assumption that the databus actions occur much faster than
--   we can push uart data into this state machine.
--
--   In the case for slow uarts (sub 200 kbps) and system clock faster than 20 MHz
--   and slave latencies only a few clocks, this is assured.
--
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_db_interface is
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
end entity;

architecture b of uart_db_interface is
    
    -----------------------------------------------------------
    -- signals
    -----------------------------------------------------------
    signal cmd_state            : std_logic;
    signal cmd_in               : std_logic_vector( 7 downto 0);
    signal write_data           : std_logic_vector( 7 downto 0);

    signal cmd_rdy_re           : std_logic;  -- rising edge detected
    signal cmd_rdy_d1           : std_logic;  -- delayed 1

    signal rx_data_valid_re     : std_logic;
    signal rx_data_Valid_d1     : std_logic;

begin

    o_db_cmd_out <= cmd_in;
    o_db_cmd_data_out <= write_data;

    cmd_done_detect : process( i_clk )
    begin
        if ( rising_edge( i_clk ) ) then
            if ( i_srst = '1' ) then
                -- in reset
                cmd_rdy_re <= '0';
                cmd_rdy_d1 <= i_db_cmd_rdy;
            else
                cmd_rdy_d1 <= i_db_cmd_rdy;
                if ( cmd_rdy_d1 = '0' and i_db_cmd_rdy = '1' ) then
                    cmd_rdy_re <= '1';
                else
                    cmd_rdy_re <= '0';
                end if;
            end if;
        end if;
    end process;

    uart_rd_sm : process( i_clk )
    begin
        if ( rising_edge( i_clk ) ) then
            if ( i_srst = '1' ) then
                -- in reset
                o_tx_send <= (others=>'0');
                o_tx_send_wstrb <= '0';
            else
                -- for a read command completion do...
                if ( cmd_in(7) = '1' and cmd_rdy_re = '1' ) then
                    -- there is an assumption that tx fifo is always
                    -- ready for data. 
                    -- in the usage case here this is safe because
                    -- commands are rate limited by the uart input rate.
                    -- we are guaranteed that we will send data at the
                    -- serial link rate, since it takes 1 uart bytes to get
                    -- 1 read byte back to the uart...
                    o_tx_send <= i_db_cmd_data_in;
                    o_tx_send_wstrb <= '1';
                 else
                    o_tx_send_wstrb <= '0';
                end if;
            end if;
        end if;
    end process; 
                    
    -- detect rising edge on data_valid
    rx_valid_re_det : process(i_clk)
    begin
        if ( rising_edge(i_clk) ) then
            rx_data_valid_d1 <= i_rx_data_valid;
            if ( rx_data_valid_d1 = '0' and i_rx_data_valid = '1' ) then
                rx_data_valid_re <= '1';
            else
                rx_data_Valid_re <= '0';
            end if;
        end if;
    end process;

    uart_intf_sm : process (i_clk)
    begin
        if ( rising_edge( i_clk ) ) then
            if ( i_srst = '1' ) then
                -- in reset
                cmd_state <= '0';  -- '0' -- get address '1' -- get data (if write cmd)                
                o_db_cmd_wstrb <= '0';
                cmd_in <= (others=>'0');
            else
                -- only do stuff if i_db_cmd_rdy is a '1'
                -- if busy, just wait.
                if ( i_db_cmd_rdy = '1' ) then
                    -- uart rx takes priority over uart tx
                    if ( rx_data_valid_re = '1' ) then
                        -- we have input data to read..
                        o_rx_read_ack <= '1';
                        -- cmd_state 0 -- first byte in command (reads only have 1 byte)
                        --                writes have 2 bytes, address and data.
                        if ( cmd_state = '0' ) then
                            -- process input cmd
                            cmd_in <= i_rx_data;
                            if ( i_rx_data(7) = '0' ) then
                                -- this is a write cmd,
                                -- next byte received will be data..
                                cmd_state <= '1'; -- get data next cycle
                                o_db_cmd_wstrb <= '0';
                            else
                                -- this is a read cmd, only 1 byte command is needed.
                                -- next byte received will be another command
                                cmd_state <= '0';
                                -- issue read to databus master
                                o_db_cmd_wstrb <= '1';
                            end if;
                        else
                            -- get data cycle on write command
                            -- processing input data
                            write_data <= i_rx_data;
                            -- issue cmd to databus master.
                            o_db_cmd_wstrb <= '1';
                            cmd_state <= '0'; -- reset back to cmd_state 0, start of next command
                        end if; -- cmd_state
                    else
                        -- not reading any data.. 
                        o_db_cmd_wstrb <= '0';
                        o_rx_read_ack <= '0';
                    end if;  --  data_valid
                else
                    o_db_cmd_wstrb <= '0';
                    o_rx_read_ack <= '0';
                end if; -- cmd_rdy
            end if;  -- reset
        end if;  -- clk_rising
    end process;

end architecture; 
