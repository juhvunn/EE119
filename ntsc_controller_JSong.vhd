----------------------------------------------------------------------------------
-- Company: Caltech
-- Engineer: JSong
--
-- Create Date:    11:15:44 11/06/2026
-- Design Name: NTSC Controller
-- Module Name:    ntsc_controller - Behavioral
-- Project Name: HW_NTSC_Controller
-- Target Devices:
-- Tool versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Revision 0.02 - ROM address made registered counters (no subtractors) and
--                 subtraction removed from sync generation to fit XC9572
-- Additional Comments:
--
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity NTSC is
    port (
        CLK        : in  std_logic;                     -- 10 MHz clock
        Col        : out std_logic_vector(9 downto 0);  -- ROM column address
        Row        : out std_logic_vector(7 downto 0);  -- ROM row address
        OddEven    : out std_logic;                     -- ROM field address
        VideoBlank : out std_logic;                     -- blank (active low)
        VideoSync  : out std_logic                      -- sync (active high)
    );
end NTSC;


architecture behavioral of NTSC is

    -- horizontal timing constants (in clocks)
    constant LINE_CLKS   : integer := 636;
    constant HALF_CLKS   : integer := 318;
    constant HSYNC_CLKS  : integer := 47;
    constant EQ_CLKS     : integer := 23;
    constant SER_CLKS    : integer := 273;
    constant VIDEO_START : integer := 109;
    constant PIXELS      : integer := 512;

    -- vertical timing constants (in lines)
    constant LAST_LINE  : integer := 525;
    constant EVEN_FIRST : integer := 21;
    constant EVEN_LAST  : integer := 260;
    constant ODD_FIRST  : integer := 284;
    constant ODD_LAST   : integer := 523;
    constant ODD_START  : integer := 262;   -- first line of the odd field

    -- the type of sync pulses in each half of a line
    type HalfType is (HALF_NORM, HALF_EQ, HALF_SER);

    -- counters
    signal HCnt    : integer range 0 to LINE_CLKS - 1 := 0;
    signal LineCnt : integer range 1 to LAST_LINE := 1;

    -- line decoding
    signal VideoLine  : std_logic;
    signal FirstHalf  : HalfType;
    signal SecondHalf : HalfType;

    -- next values of the (registered) outputs
    signal SyncNext  : std_logic;
    signal BlankNext : std_logic;

    -- registered outputs
    signal SyncOut  : std_logic := '1';
    signal BlankOut : std_logic := '0';

    -- registered ROM address
    signal ColCnt   : unsigned(9 downto 0) := (others => '0');
    signal RowCnt   : unsigned(7 downto 0) := (others => '0');
    signal OddField : std_logic := '0';

begin

    -- outputs
    VideoSync  <= SyncOut;
    VideoBlank <= BlankOut;

    -- ROM address outputs (registered counters, no subtractors)
    Col     <= std_logic_vector(ColCnt);
    Row     <= std_logic_vector(RowCnt);
    OddEven <= OddField;


    -- normal video lines are the only lines that are not blanked
    VideoLine <= '1'
        when (LineCnt >= EVEN_FIRST and LineCnt <= EVEN_LAST) or (LineCnt >= ODD_FIRST and LineCnt <= ODD_LAST)
        else '0';


    -- decode the type of sync pulses in each half of the current line
    -- (the second half of a normal line has no sync pulse)
    process(LineCnt)
    begin
        -- default is a normal (video or blanked) line
        FirstHalf  <= HALF_NORM;
        SecondHalf <= HALF_NORM;

        case LineCnt is
            when 1 to 3 | 7 to 9 | 264 to 265 | 270 to 271 =>
                FirstHalf  <= HALF_EQ;
                SecondHalf <= HALF_EQ;

            when 4 to 6 | 267 to 268 =>
                FirstHalf  <= HALF_SER;
                SecondHalf <= HALF_SER;

            when 263 =>
                SecondHalf <= HALF_EQ;

            when 266 =>
                FirstHalf  <= HALF_EQ;
                SecondHalf <= HALF_SER;

            when 269 =>
                FirstHalf  <= HALF_SER;
                SecondHalf <= HALF_EQ;

            when 272 =>
                FirstHalf <= HALF_EQ;

            when others =>
                null;

        end case;
    end process;


    -- generate the sync signal based on the half line type and the position
    -- in the line, every half line starts with sync (if it has one)
    -- (compares against start + width so no subtractor is needed)
    process(HCnt, FirstHalf, SecondHalf)

        variable kind  : HalfType;
        variable start : integer range 0 to HALF_CLKS;

    begin
        if HCnt < HALF_CLKS then
            kind  := FirstHalf;
            start := 0;
        else
            kind  := SecondHalf;
            start := HALF_CLKS;
        end if;

        SyncNext <= '0';

        case kind is

            when HALF_NORM =>
                -- Normal sync occurs only at the start of a full line.
                if HCnt < HSYNC_CLKS then
                    SyncNext <= '1';
                end if;

            when HALF_EQ =>
                if HCnt < start + EQ_CLKS then
                    SyncNext <= '1';
                end if;

            when HALF_SER =>
                if HCnt < start + SER_CLKS then
                    SyncNext <= '1';
                end if;

        end case;
    end process;


    -- not blanked only during the video portion of a normal video line
    BlankNext <= '1'
        when VideoLine = '1' and
             HCnt >= VIDEO_START and
             HCnt < VIDEO_START + PIXELS
        else '0';


    -- counters and registered outputs
    process(CLK)
    begin
        if rising_edge(CLK) then

            -- horizontal counter, at the end of the line go to the next line
            if HCnt = LINE_CLKS - 1 then

                HCnt <= 0;

                if LineCnt = LAST_LINE then
                    LineCnt <= 1;
                else
                    LineCnt <= LineCnt + 1;
                end if;

            else
                HCnt <= HCnt + 1;
            end if;

            -- register the timing outputs
            SyncOut  <= SyncNext;
            BlankOut <= BlankNext;

            -- column address, loaded with 0 so pixel 0's address is output
            -- at HCnt = VIDEO_START (one clock before it is displayed)
            if HCnt = VIDEO_START - 1 then
                ColCnt <= (others => '0');
            else
                ColCnt <= ColCnt + 1;
            end if;

            -- row address, 0 during vertical blanking and incremented at
            -- the end of every video line
            if VideoLine = '0' then
                RowCnt <= (others => '0');
            elsif HCnt = LINE_CLKS - 1 then
                RowCnt <= RowCnt + 1;
            end if;

            -- field address, the odd field starts at line 262
            if LineCnt >= ODD_START then
                OddField <= '1';
            else
                OddField <= '0';
            end if;

        end if;
    end process;

end behavioral;