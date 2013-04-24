// Copyright (C) 1991-2012 Altera Corporation
// Your use of Altera Corporation's design tools, logic functions 
// and other software and tools, and its AMPP partner logic 
// functions, and any output files from any of the foregoing 
// (including device programming or simulation files), and any 
// associated documentation or information are expressly subject 
// to the terms and conditions of the Altera Program License 
// Subscription Agreement, Altera MegaCore Function License 
// Agreement, or other applicable license agreement, including, 
// without limitation, that your use is for the sole purpose of 
// programming logic devices manufactured by Altera and sold by 
// Altera or its authorized distributors.  Please refer to the 
// applicable agreement for further details.


// Generated by Quartus II 32-bit Version 12.0 (Build Build 232 07/05/2012)
// Created on Tue Apr 23 23:50:31 2013

ZPUTest ZPUTest_inst
(
	.clk(clk_sig) ,	// input  clk_sig
	.src(src_sig) ,	// input [15:0] src_sig
	.counter(counter_sig) ,	// output [15:0] counter_sig
	.reset_in(reset_in_sig) ,	// input  reset_in_sig
	.keys(keys_sig) ,	// input [3:0] keys_sig
	.vga_red(vga_red_sig) ,	// output [7:0] vga_red_sig
	.vga_green(vga_green_sig) ,	// output [7:0] vga_green_sig
	.vga_blue(vga_blue_sig) ,	// output [7:0] vga_blue_sig
	.vga_hsync(vga_hsync_sig) ,	// output  vga_hsync_sig
	.vga_vsync(vga_vsync_sig) ,	// output  vga_vsync_sig
	.vga_window(vga_window_sig) ,	// output  vga_window_sig
	.sdr_data(sdr_data_sig) ,	// inout [15:0] sdr_data_sig
	.sdr_addr(sdr_addr_sig) ,	// output [11:0] sdr_addr_sig
	.sdr_dqm(sdr_dqm_sig) ,	// output [1:0] sdr_dqm_sig
	.sdr_we(sdr_we_sig) ,	// output  sdr_we_sig
	.sdr_cas(sdr_cas_sig) ,	// output  sdr_cas_sig
	.sdr_ras(sdr_ras_sig) ,	// output  sdr_ras_sig
	.sdr_cs(sdr_cs_sig) ,	// output  sdr_cs_sig
	.sdr_ba(sdr_ba_sig) ,	// output [1:0] sdr_ba_sig
	.sdr_clk(sdr_clk_sig) ,	// output  sdr_clk_sig
	.sdr_clkena(sdr_clkena_sig) ,	// output  sdr_clkena_sig
	.rs232_rxd(rs232_rxd_sig) ,	// input  rs232_rxd_sig
	.rs232_txd(rs232_txd_sig) 	// output  rs232_txd_sig
);

defparam ZPUTest_inst.sdram_rows = 12;
defparam ZPUTest_inst.sdram_cols = 8;
defparam ZPUTest_inst.sysclk_frequency = 1000;
defparam ZPUTest_inst.spi_maxspeed = 4;
