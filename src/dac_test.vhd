----------------------------------------------------------
-- DAC_TEST.VHD
--
--   Simple module to generate a cosine wave using a NCO
--   and a lookup table.
--
--   Goal is to generate a 16bit sinewave.  
--
--   We will use the top N-bits as needed for each sample
--   depending on dac depth.
--
---------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.math_real.ALL;

entity dac_test is
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
        i_nco_ftw           : in unsigned(31 downto 0)  -- 32bit nco word
    );
end entity dac_test;

architecture rtl of dac_test is 

    constant SAMPLE_WIDTH   : integer := 12;   -- 12 bit samples ( 11 downto 0 )
    constant MEM_DEPTH      : integer := 2**SAMPLE_WIDTH;  -- number of lookup table points needed.
    type mem_type is array  ( 0 to MEM_DEPTH-1) of signed(SAMPLE_WIDTH-1 downto 0);  -- define memory data type

    -- function to fill memory with cos table (at compile time)
    function init_lookuptable return mem_type is
        constant SCALE : real := 2**(real(SAMPLE_WIDTH-1));
        constant STEP  : real := 1.0/real(MEM_DEPTH);
        variable temp_mem : mem_type;
    begin
        for i in 0 to MEM_DEPTH-1 loop
            temp_mem(i) := to_signed( integer(cos(2.0*MATH_PI*real(i)*STEP)*SCALE), SAMPLE_WIDTH);
        end loop;
        return temp_mem;
    end;

    -- constant rom of cos lookup table for 2^11 entries.. (2048x12b)
    -- initalized at compile time.
    constant cos_lookup : mem_type := init_lookuptable;


    -- address for the sample we want to send to the DAC
    signal lookup_addr  : unsigned( 31 downto 0 );

    signal sample_out   : signed( 11 downto 0 );
    
begin

    o_dac_cmode <= '1'; -- '1' for differential clocking
    o_dac_mode  <= '1'; -- '1' = 2's compliment samples
    o_dac_sleep <= '0'; -- forces dac to run, set to '1' to place dac in sleep
    o_dac_reset <= '1'; -- (pin) forces dac into pin operation mode.. (spi is disabled)

    -- output clock for sample generation
    o_dac_clk <= i_clk; 

    o_dac_db <= sample_out;

    dac_nco : process( i_clk )
    begin
        if ( rising_edge(i_clk) ) then
            if ( i_rst = '1' ) then
                lookup_addr <= (others=>'0');
                sample_out <= cos_lookup(to_integer(lookup_addr(31 downto 31-SAMPLE_WIDTH)));
            else
                lookup_addr <= lookup_addr + i_nco_ftw;
                sample_out <= cos_lookup(to_integer(lookup_addr(31 downto 31-SAMPLE_WIDTH)));
            end if;
        end if;
    end process;

end architecture;


                
                    
