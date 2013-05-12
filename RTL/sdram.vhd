------------------------------------------------------------------------------
------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2009 Tobias Gubener                                        -- 
-- Subdesign fAMpIGA by TobiFlex                                            --
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU General Public License as published        --
-- by the Free Software Foundation, either version 3 of the License, or     --
-- (at your option) any later version.                                      --
--                                                                          --
-- This source file is distributed in the hope that it will be useful,      --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of           --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            --
-- GNU General Public License for more details.                             --
--                                                                          --
-- You should have received a copy of the GNU General Public License        --
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.    --
--                                                                          --
------------------------------------------------------------------------------
------------------------------------------------------------------------------

-- 32 bit CPU write port for the benefit of the ZPU core.
 
library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.ALL;

entity sdram is
generic
	(
		rows : integer := 12;	-- FIXME - change access sizes according to number of rows
		cols : integer := 8
	);
port
	(
-- Physical connections to the SDRAM
	sdata		: inout std_logic_vector(15 downto 0);
	sdaddr		: out std_logic_vector((rows-1) downto 0);
	sd_we		: out std_logic;	-- Write enable, active low
	sd_ras		: out std_logic;	-- Row Address Strobe, active low
	sd_cas		: out std_logic;	-- Column Address Strobe, active low
	sd_cs		: out std_logic;	-- Chip select - only the lsb does anything.
	dqm			: out std_logic_vector(1 downto 0);	-- Data mask, upper and lower byte
	ba			: buffer std_logic_vector(1 downto 0); -- Bank?

-- Housekeeping
	sysclk		: in std_logic;
	reset		: in std_logic;
	reset_out	: out std_logic;
	reinit : in std_logic :='0';

-- Port 0 - VGA
	vga_addr : in std_logic_vector(31 downto 0);
	vga_data	: out std_logic_vector(15 downto 0);
	vga_req : in std_logic;
	vga_fill : out std_logic;
	vga_ack : out std_logic;
	vga_newframe : in std_logic;
	vga_refresh : in std_logic; -- SDRAM won't come out of reset without this.
	vga_reservebank : in std_logic; -- Keep a bank clear for instant access in slot 1
	vga_reserveaddr : in std_logic_vector(31 downto 0);

	-- Port 1
	datawr1		: in std_logic_vector(31 downto 0);	-- Data in from ZPU
	dataout1		: out std_logic_vector(31 downto 0); -- Data destined for ZPU
	Addr1		: in std_logic_vector(31 downto 0);	-- Address in from ZPU - FIXME case
	req1		: in std_logic;
	wr1			: in std_logic;	-- Read/write from Minimig
	wrL1		: in std_logic;	-- Minimig write lower byte
	wrU1		: in std_logic;	-- Minimig write upper byte
	wrU2		: in std_logic;	-- Minimig write upper word
	dtack1	: buffer std_logic
	);
end;

architecture rtl of sdram is


signal initstate	:unsigned(3 downto 0);	-- Counter used to initialise the RAM
signal cas_sd_cs	:std_logic;	-- Temp registers...
signal cas_sd_ras	:std_logic;
signal cas_sd_cas	:std_logic;
signal cas_sd_we 	:std_logic;
signal cas_dqm		:std_logic_vector(1 downto 0);	-- ...mask register for entire burst
signal init_done	:std_logic :='0';
signal datain		:std_logic_vector(15 downto 0);
signal casaddr		:std_logic_vector(31 downto 0);
signal sdwrite 		:std_logic;
signal sdata_reg	:std_logic_vector(15 downto 0);

signal refreshcycle :std_logic;
signal qvalid		:std_logic;
signal qdataout0	:std_logic_vector(15 downto 0); -- temp data for Minimig
signal qdataout1	:std_logic_vector(15 downto 0); -- temp data for Minimig

type sdram_states is (ph0,ph1,ph2,ph3,ph4,ph5,ph6,ph7,ph8,ph9,ph10,ph11,ph12,ph13,ph14,ph15);
signal sdram_state		: sdram_states;

type sdram_ports is (idle,refresh,port0,port1,writecache);

signal sdram_slot1 : sdram_ports :=refresh;
signal sdram_slot1_readwrite : std_logic;
signal sdram_slot2 : sdram_ports :=idle;
signal sdram_slot2_readwrite : std_logic;

-- Since VGA has absolute priority, we keep track of the next bank and disallow accesses
-- to either the current or next bank in the interleaved access slots.
signal slot1_bank : std_logic_vector(1 downto 0) := "00";
signal slot2_bank : std_logic_vector(1 downto 0) := "11";

-- refresh timer - once per scanline, so don't need the counter...
-- signal refreshcounter : unsigned(12 downto 0);	-- 13 bits gives us 8192 cycles between refreshes => pretty conservative.
signal refreshpending : std_logic :='0';

signal port1_dtack : std_logic;

type writecache_states is (waitwrite,fill,finish);
signal writecache_state : writecache_states;

signal writecache_addr : std_logic_vector(31 downto 1); -- Burst can start at 16-bit alignment
signal writecache_word0 : std_logic_vector(15 downto 0);
signal writecache_word1 : std_logic_vector(15 downto 0);
signal writecache_dqm : std_logic_vector(7 downto 0);
signal writecache_req : std_logic;
signal writecache_dirty : std_logic;
signal writecache_dtack : std_logic;
signal writecache_burst : std_logic;

signal readword : std_logic_vector(31 downto 0);

begin

	process(sysclk)
	begin
	
	dtack1 <= port1_dtack and writecache_dtack; -- and not readcache_dtack;
	dataout1 <= readword;

	if reset='0' then
		writecache_req<='0';
		writecache_dirty<='0';
		writecache_dqm<="11111111";
		writecache_state<=waitwrite;
	elsif rising_edge(sysclk) then

		writecache_dtack<='1';
		writecache_dqm(7 downto 4)<="1111"; -- Never write the upper quadword.

		-- 32-bit variant of writecache for ZPU...
		case writecache_state is
			when waitwrite =>
				if req1='1' and wr1='0' then -- write request
					if writecache_dirty='0' then
						writecache_addr(31 downto 3)<=addr1(31 downto 3);
						if wrU2='1' then -- is this a halfword write?	
							-- 00 -> 11, 01 -> 00, 10 -> 01, 11 -> 10
							writecache_addr(2)<=addr1(2) xor not addr1(1); -- Mangle address to start 1 word early
							writecache_addr(1)<=not addr1(1);	-- More LE-efficient than shifting the data
						else
							writecache_addr(2 downto 1)<=addr1(2 downto 1);
						end if;
						writecache_word0<=datawr1(31 downto 16);
						writecache_dqm(1 downto 0)<=wrU2&wrU2; -- Are we writing the upper word?
						writecache_word1<=datawr1(15 downto 0);
						writecache_dqm(3 downto 2)<=wrU1&wrL1; -- Are we writing the lower two bytes?
						writecache_req<='1';
						writecache_dtack<='0';
						writecache_dirty<='1';
					end if;
				end if;
				if writecache_burst='1' and writecache_dirty='1' then
					writecache_req<='0';
					writecache_state<=fill;
				end if;
			when fill =>
				if writecache_burst='0' then
					writecache_dirty<='0';
					writecache_dqm<="11111111";
					writecache_state<=waitwrite;
				end if;
			when others =>
				null;
		end case;
				
	end if;
end process;


-------------------------------------------------------------------------
-- SDRAM Basic
-------------------------------------------------------------------------
	reset_out <= init_done;-- and cache_ready;
--	port1bank <= unsigned(Addr1(4 downto 3));

	process (sysclk, reset, sdwrite, datain) begin
		IF sdwrite='1' THEN	-- Keep sdram data high impedence if not writing to it.
			sdata <= datain;
		ELSE
			sdata <= "ZZZZZZZZZZZZZZZZ";
		END IF;

		--   sample SDRAM data
		if rising_edge(sysclk) then
			sdata_reg <= sdata;
			vga_data <= sdata;
		END IF;	
		
		if reset = '0' then
			initstate <= (others => '0');
			init_done <= '0';
			sdram_state <= ph0;
			sdwrite <= '0';
		ELSIF rising_edge(sysclk) THEN
			sdwrite <= '0';

			if reinit='1' then
				init_done<='0';
				initstate<="1111";
			end if;			
			

--                          (sync)
-- Phase     :  0     1     2     3     4     5     6     7     8     9    10    11    12    13    14    15
-- sysclk    :/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__

-- _RAS      :            \_____/
-- _CAS      :           (\auto/)           \_____/

-- SDWrite   :________________________/                 \_________________________________________

			case sdram_state is	--LATENCY=3
				when ph0 =>	
					if sdram_slot2=writecache then -- port1 and sdram_slot2_readwrite='0' then
						sdwrite<='1';
					end if;
					sdram_state <= ph1;
				when ph1 =>	
					if sdram_slot2=port0 then
						vga_fill<='1';
					end if;
					sdram_state <= ph2;
				when ph2 =>
					sdram_state <= ph3;
--					enaRDreg <= '1';
				when ph3 =>
					sdram_state <= ph4;
				when ph4 =>	sdram_state <= ph5;
					sdwrite <= '1';
				when ph5 => sdram_state <= ph6;
					vga_fill<='0';
					sdwrite <= '1';
				when ph6 =>	sdram_state <= ph7;
					sdwrite <= '1';
--							enaWRreg <= '1';
--							ena7RDreg <= '1';
				when ph7 =>	sdram_state <= ph8;
					sdwrite <= '1';
				when ph8 =>	sdram_state <= ph9;
					if sdram_slot1=writecache then -- port1 and sdram_slot1_readwrite='0' then
						sdwrite<='1';
					end if;
					
				when ph9 =>	sdram_state <= ph10;
					if sdram_slot1=port0 then
						vga_fill<='1';
					end if;
				when ph10 => sdram_state <= ph11;
--					cachefill<='1';
--							enaRDreg <= '1';
				when ph11 => sdram_state <= ph12;
--					cachefill<='1';
				when ph12 => sdram_state <= ph13;
--					cachefill<='1';
					sdwrite<='1';
				when ph13 => sdram_state <= ph14;
					vga_fill<='0';
					sdwrite<='1';
				when ph14 =>
						sdwrite<='1';
						if initstate /= "1111" THEN -- 16 complete phase cycles before we allow the rest of the design to come out of reset.
							initstate <= initstate+1;
							sdram_state <= ph15;
						elsif init_done='1' then
							sdram_state <= ph15;
						elsif vga_refresh='1' then -- Delay here to establish phase relationship between SDRAM and VGA
							init_done <='1';
							sdram_state <= ph0;
						end if;
--							enaWRreg <= '1';
--							ena7WRreg <= '1';
				when ph15 => sdram_state <= ph0;
					sdwrite<='1';
				when others => sdram_state <= ph0;
			end case;	
		END IF;	
	end process;		


	
	process (sysclk, initstate, datain, init_done, casaddr, refreshcycle) begin


		if reset='0' then
			sdram_slot1<=refresh;
			sdram_slot2<=idle;
			slot1_bank<="00";
			slot2_bank<="11";
			writecache_burst<='0';
		elsif rising_edge(sysclk) THEN -- rising edge
	
			-- Attend to refresh counter
--			refreshcounter<=refreshcounter+"0000000000001";
			if sdram_slot1=refresh then
				refreshpending<='0';
--			elsif refreshcounter(12 downto 4)="000000000" then
--				refreshpending<='1';
			elsif vga_refresh='1' then
				refreshpending<='1';
			end if;

		--		ba <= Addr(22 downto 21);
			sd_cs <='1';
			sd_ras <= '1';
			sd_cas <= '1';
			sd_we <= '1';
			sdaddr <= "XXXXXXXXXXXX";
			ba <= "00";
			dqm <= "00";  -- safe defaults for everything...

			port1_dtack<='1';

			-- The following block only happens during reset.
			if init_done='0' then
				if sdram_state =ph2 then
					case initstate is
						when "0010" => --PRECHARGE
							sdaddr(10) <= '1'; 	--all banks
							sd_cs <='0';
							sd_ras <= '0';
							sd_cas <= '1';
							sd_we <= '0';
						when "0011"|"0100"|"0101"|"0110"|"0111"|"1000"|"1001"|"1010"|"1011"|"1100" => --AUTOREFRESH
							sd_cs <='0'; 
							sd_ras <= '0';
							sd_cas <= '0';
							sd_we <= '1';
						when "1101" => --LOAD MODE REGISTER
							sd_cs <='0';
							sd_ras <= '0';
							sd_cas <= '0';
							sd_we <= '0';
--							ba <= "00";
	--						sdaddr <= "001000100010"; --BURST=4 LATENCY=2
--							sdaddr <= "001000110010"; --BURST=4 LATENCY=3
--							sdaddr <= "001000110000"; --noBURST LATENCY=3
							sdaddr <= "000000110010"; --BURST=4 LATENCY=3, BURST WRITES
						when others =>	null;	--NOP
					end case;
				END IF;
			else		

			
-- We have 8 megabytes to play with, addressed with bits 22 downto 0
-- bits 22 and 21 are used as bank select
-- bits 20 downto 9 are the row address, set in phase 2.
-- bits 23, 8 downto 1

-- In the interests of interleaving bank access, rearrange this somewhat
-- We're transferring 4 word bursts, so 8 bytes at a time, so leave lower 3 bits
-- as they are, but try making the next two the bank select bits

-- Bank select will thus be addr(4 downto 3),
-- Column will be addr(10 downto 5) & addr(2 downto 1) instead of addr(8 downto 1)
-- Row will be addr(22 downto 11) instead of (20 downto 9)

--  ph0				(drive data)
--
--  ph1
--						Data word 1
--  ph2 Active first bank / Autorefresh (RAS)
--						Data word 2
--  ph3
--						Data word 3 -  Assert dtack, propagates next cycle by which time all data is valid.
--  ph4
--						Data word 4
--  ph5 ReadA (CAS) (drive data)

--  ph6 (drive data)

--  ph7 (drive data)

--  ph8 (drive data)
--  ph9 Data word 1

-- ph10 Data word 2
--						Active second bank

-- ph11 Data word 3  -  Assert dtack, propagates next cycle by which time all data is valid.

-- ph12 Data word 4

-- ph13
--						ReadA (CAS) (drive data)
-- ph14
--						(drive data)
-- ph15
--						(drive data)

-- Time slot control			

				vga_ack<='0';
				case sdram_state is

					when ph2 => -- ACTIVE for first access slot
						cas_sd_cs <= '0';  -- Only the lowest bit has any significance...
						cas_sd_ras <= '1';
						cas_sd_cas <= '1';
						cas_sd_we <= '1';

						cas_dqm <= "00";

						sdram_slot1<=idle;
						if refreshpending='1' and sdram_slot2=idle then	-- refreshcycle
							sdram_slot1<=refresh;
							sd_cs <= '0'; --ACTIVE
							sd_ras <= '0';
							sd_cas <= '0'; --AUTOREFRESH
						elsif vga_req='1' then
							if vga_addr(4 downto 3)/=slot2_bank or sdram_slot2=idle then
								sdram_slot1<=port0;
								sdaddr <= vga_addr(22 downto 11);
								ba <= vga_addr(4 downto 3);
								slot1_bank <= vga_addr(4 downto 3);
--								if vga_idle='0' then
--									vga_nextbank <= unsigned(vga_addr(4 downto 3))+"01";
--								end if;
								casaddr <= vga_addr(31 downto 3) & "000"; -- read whole cache line in burst mode.
	--							datain <= X"0000";
								cas_sd_cas <= '0';
								cas_sd_we <= '1';
								sd_cs <= '0'; --ACTIVE
								sd_ras <= '0';
								vga_ack<='1'; -- Signal to VGA controller that it can bump bankreserve
--							else
--								vga_nextbank <= unsigned(vga_addr(4 downto 3)); -- reserve bank for next access
							end if;
						elsif writecache_req='1'
								and sdram_slot2/=writecache
								and (writecache_addr(4 downto 3)/=slot2_bank or sdram_slot2=idle)
									then
							sdram_slot1<=writecache;
							sdaddr <= writecache_addr(22 downto 11);
							ba <= writecache_addr(4 downto 3);
							slot1_bank <= writecache_addr(4 downto 3);
							cas_dqm <= wrU1&wrL1;
							casaddr <= writecache_addr&"0";
--							datain <= writecache_word0;
							cas_sd_cas <= '0';
							cas_sd_we <= '0';
							sdram_slot1_readwrite <= '0';
							sd_cs <= '0'; --ACTIVE
							sd_ras <= '0';
						elsif req1='1'
								and (Addr1(4 downto 3)/=slot2_bank or sdram_slot2=idle) then
							sdram_slot1<=port1;
							sdaddr <= Addr1(22 downto 11);
							ba <= Addr1(4 downto 3);
							slot1_bank <= Addr1(4 downto 3); -- slot1 bank
							cas_dqm <= "00";
							casaddr <= Addr1(31 downto 1) & "0";
--							datain <= datawr1;
							cas_sd_cas <= '0';
							cas_sd_we <= '1';
							sdram_slot1_readwrite <= '1';
							sd_cs <= '0'; --ACTIVE
							sd_ras <= '0';
						end if;

						if sdram_slot2=port1 then
							readword(31 downto 16)<=sdata_reg;
--							readword(15 downto 0)<=sdata_reg;
--							readcache_fill<='1';
						end if;


					when ph3 =>
						if sdram_slot2=port1 then
							readword(15 downto 0)<=sdata_reg;
							port1_dtack<='0';
--							readword2(31 downto 15)<=sdata;
--							readcache_fill<='1';
						end if;
						-- If we're doing a read cycle for the second slot, assert dtack.
--						case sdram_slot2 is
	--						when port0 =>
	--							dtack0<='0';
--							when port1 =>
--								if sdram_slot2_readwrite='1' then
--									port1_dtack<='0'; -- only for read cycles, write cycles can finish sooner.
--								end if;
--								readcache_fill='1';
--							when others =>
--								null;
--						end case;
						if sdram_slot1=writecache then
							writecache_burst<='1';	-- Close the door on new write data
						end if;

					when ph4 =>
						if sdram_slot2=port1 then
--							readword2(31 downto 16)<=sdata_reg;
--							readword2(15 downto 0)<=sdata;
--							readcache_fill<='1';
						end if;
						
					when ph5 => -- Read or Write command			
						sdaddr <=  "0100" & casaddr(10 downto 5) & casaddr(2 downto 1) ;--auto precharge
						ba <= casaddr(4 downto 3);
						sd_cs <= cas_sd_cs; 

						dqm <= cas_dqm;

						sd_ras <= cas_sd_ras;
						sd_cas <= cas_sd_cas;
						sd_we  <= cas_sd_we;
						if sdram_slot1=writecache then
							datain <= writecache_word0;
							dqm <= writecache_dqm(1 downto 0);
						end if;
						if sdram_slot2=port1 then
--							readword2(15 downto 0)<=sdata_reg;
--							readword2(15 downto 0)<=sdata;
--							readcache_fill<='1';
						end if;

					when ph6 => -- Next word of burst write
--						if sdram_slot2=port1 then
--							readcache_fill<='1';
--						end if;
						if sdram_slot1=writecache then
							datain <= writecache_word1;
							dqm <= writecache_dqm(3 downto 2);
							writecache_burst<='0'; -- End write burst after 32 bits.
						end if;

					when ph7 => -- third word of burst write
						if sdram_slot1=writecache then
--							datain <= writecache_word2;
							dqm <= writecache_dqm(5 downto 4);
						end if;
				
					when ph8 =>
						if sdram_slot1=writecache then
--							datain <= writecache_word3;
							dqm <= writecache_dqm(7 downto 6);
						end if;

					when ph9 =>
						if sdram_slot1=port1 then
--							readcache_fill<='1';
						end if;

					when ph10 => -- Second access slot...
						cas_sd_cs <= '0';  -- Only the lowest bit has any significance...
						cas_sd_ras <= '1';
						cas_sd_cas <= '1';
						cas_sd_we <= '1';
						
						cas_dqm <= "00";

						sdram_slot2<=idle;
						if refreshpending='1' or sdram_slot1=refresh then
							sdram_slot2<=idle;
						elsif writecache_req='1'
								and sdram_slot1/=writecache
								and (writecache_addr(4 downto 3)/=slot1_bank or sdram_slot1=idle)
								and (writecache_addr(4 downto 3)/=vga_reserveaddr(4 downto 3)
									or vga_reservebank='0') then  -- Safe to use this slot with this bank?
							sdram_slot2<=writecache;
							sdaddr <= writecache_addr(22 downto 11);
							ba <= writecache_addr(4 downto 3);
							slot2_bank <= writecache_addr(4 downto 3);
							cas_dqm <= wrU1&wrL1;
							casaddr <= writecache_addr&"0";
--							datain <= writecache_word0;
							cas_sd_cas <= '0';
							cas_sd_we <= '0';
							sdram_slot2_readwrite <= '0';
							sd_cs <= '0'; --ACTIVE
							sd_ras <= '0';
						elsif req1='1' -- req1='1' and wr1='1'
								and (Addr1(4 downto 3)/=slot1_bank or sdram_slot1=idle)
								and (Addr1(4 downto 3)/=vga_reserveaddr(4 downto 3)
									or vga_reservebank='0') then  -- Safe to use this slot with this bank?
							sdram_slot2<=port1;
							sdaddr <= Addr1(22 downto 11);
							ba <= Addr1(4 downto 3);
							slot2_bank <= Addr1(4 downto 3);
							cas_dqm <= "00";
							casaddr <= Addr1(31 downto 1) & "0"; -- We no longer mask off LSBs for burst read
--							datain <= datawr1;
							cas_sd_cas <= '0';
							cas_sd_we <= '1';
							sdram_slot2_readwrite <= '1';
							sd_cs <= '0'; --ACTIVE
							sd_ras <= '0';
						end if;

						-- Fill - takes effect next cycle.
						if sdram_slot1=port1 then
							readword(31 downto 16)<=sdata_reg;
--							readcache_fill<='1';
						end if;
				
					when ph11 =>
						if sdram_slot1=port1 then
							readword(15 downto 0)<=sdata_reg;
							port1_dtack<='0';
--							readword2(15 downto 0)<=sdata;
--							readcache_fill<='1';
						end if;
--						case sdram_slot1 is
	--						when port0 =>
	--							dtack0<='0';
--							when port1 =>
--								if sdram_slot1_readwrite='1' then
--									port1_dtack<='0'; -- only for read cycles, write cycles can finish sooner.
--								end if;
--							when others =>
--								null;
--						end case;
						if sdram_slot2=writecache then
							writecache_burst<='1';  -- close the door on new write data
						end if;

					when ph12 =>
						if sdram_slot1=port1 then
--							readword2(31 downto 16)<=sdata_reg;
--							readcache_fill<='1';
						end if;
						
					-- Phase 13 - CAS for second window...
					when ph13 =>
						if sdram_slot2/=idle then
							sdaddr <=  "0100" & casaddr(10 downto 5) & casaddr(2 downto 1) ;--auto precharge
							ba <= casaddr(4 downto 3);
							sd_cs <= cas_sd_cs; 

							dqm <= cas_dqm;

							sd_ras <= cas_sd_ras;
							sd_cas <= cas_sd_cas;
							sd_we  <= cas_sd_we;
							if sdram_slot2=writecache then
								datain <= writecache_word0;
								dqm <= writecache_dqm(1 downto 0);
							end if;
						end if;

						if sdram_slot1=port1 then
--							readword2(15 downto 0)<=sdata_reg;
--							readcache_fill<='1';
						end if;

					when ph14 => -- Second word of burst write
						if sdram_slot2=writecache then
							datain <= writecache_word1;
							dqm <= writecache_dqm(3 downto 2);
							writecache_burst<='0'; -- End burst after 32 bits for ZPU
						end if;

					when ph15 => -- Third word of burst write
						if sdram_slot2=writecache then
--							datain <= writecache_word2;
							dqm <= writecache_dqm(5 downto 4);
						end if;

					when ph0 => -- Final word of burst write
						if sdram_slot2=writecache then
--							datain <= writecache_word3;
							dqm <= writecache_dqm(7 downto 6);
						end if;
--						if sdram_slot2=port1 then
--							readcache_fill<='1';
--						end if;

					when ph1 =>
						if sdram_slot2=port1 then
--							readword(31 downto 16)<=sdata_reg;
--							readcache_fill<='1';
						end if;

					when others =>
						null;
						
				end case;

			END IF;	
		END IF;	
	END process;		
END;
