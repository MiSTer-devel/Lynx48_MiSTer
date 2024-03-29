//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

//assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;

assign AUDIO_S = 0;
//assign AUDIO_L = 0;
//assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

assign VIDEO_ARX = status[5] ? 8'd16 : 8'd4; 
assign VIDEO_ARY = status[5] ? 8'd9  : 8'd3; 

`include "build_id.v" 
localparam CONF_STR = {
	"Lynx48;;",
	"-;",
	"F[1],TAP,Load Cassette;",
	"-;",
	"O[5],Aspect ratio,4:3,16:9;",
	"O[2:1],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"-;",
	"O[4:3],Machine,Lynx 48K,Lynx 96k,96k Scorpion,Lynx 128k;",
	"O[6],BASIC Autostart,On,Off;",	
	"-;",
	"OD,Joysticks Swap,No,Yes;",
	"-;",	
	"T[0],Reset;",	
	"R[0],Reset and close OSD;",
	"J,Button;",
	"jn,A;",
	"V,v",`BUILD_DATE 
};

wire 		 forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire   [1:0] mode = status[4:3];
wire   [1:0] old_mode;

wire         ioctl_download;
wire   [7:0] ioctl_index;
wire         ioctl_wr;
wire  [24:0] ioctl_addr;
wire   [7:0] ioctl_data;

wire  [21:0] gamma_bus;

//Keyboard Ps2

wire [10:0] ps2_key;
wire [15:0]joystick_0;
wire [15:0]joystick_1;

wire [5:0] joy_0 = status[13] ? joystick_1[5:0] : joystick_0[5:0];
wire [5:0] joy_1 = status[13] ? joystick_0[5:0] : joystick_1[5:0];

wire autostart_basic = status[6] ? 1'b0 : 1'b1;
//wire [1:0] autostart_basic = status[6:1];

hps_io #(.CONF_STR(CONF_STR), .PS2DIV(1103)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),
	
	//Keyboard Ps2
	.ps2_key(ps2_key),
	.joystick_0 (joystick_0),
	.joystick_1 (joystick_1),

	//ioctl
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data)
);


///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.outclk_2(clk_sdram_o),
	.locked (pll_locked)
);

reg reset;

always @(posedge clk_sys) begin
	old_mode <= mode;
	reset <= (!pll_locked | status[0] | buttons[1] | old_mode != mode | RESET);
end

//////////////////////////////////////////////////////////////////

wire [1:0] col = status[4:3];

wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire [8:0] video;

lynx48 lynx48	
(
	.clock    (clk_sys),
	.reset_osd(~reset),
	.led      (LED_USER),

	.hSync    (HSync  ),
	.vSync    (VSync  ),
	.vBlank   (VBlank ),
	.hBlank   (HBlank ),
	.crtcDe   (crtcDe ),
	.rgb      (video  ),
	
	.ps2      (ps2_key),
	.joy_0    (~{1'b0,1'b0,joy_0[4],1'b0,joy_0[0],joy_0[1],joy_0[2],joy_0[3]} ),
	.joy_1    (~{1'b0,1'b0,joy_1[4],1'b0,joy_1[0],joy_1[1],joy_1[2],joy_1[3]} ),
	
	.audio    (AUDIO_L),
	.ear      (ear    ),
	
	.autostart_basic (autostart_basic),

	//	Removed offset addition
	.ioctl_addr			(ioctl_addr			),
	.ioctl_data			(ioctl_data			),
	.ioctl_download		(ioctl_download		),
	.ioctl_index		(ioctl_index		),
	.ioctl_wr			(ioctl_wr			),
  
	.ce_pix   			(ce_pix				),
	.mode     			(mode				)
);

assign AUDIO_R = AUDIO_L;
assign CLK_VIDEO = clk_sys;

//////////////////////////////////////////////////////////////////

wire [1:0] scale = status[2:1];
assign VGA_SL = scale ; //{scale == 3, scale == 2};
//assign VGA_SL = 0;
wire freeze_sync;

video_mixer #(448, 1) mixer
(
	.*,

        .hq2x(scale == 1),
        .scandoubler (scale || forced_scandoubler),

        .R({video[8:6],video[8]}), 
        .G({video[5:3],video[5]}), 
        .B({video[2:0],video[2]}),

);


/////////  EAR added by Fernando Mosquera
wire ear;
assign ear = tape_adc_act & tape_adc;

ltc2308_tape ltc2308_tape
(
  .clk(CLK_50M),
  .ADC_BUS(ADC_BUS),
  .dout(tape_adc),
  .active(tape_adc_act)
);
/////////////////////////

endmodule
