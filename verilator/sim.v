`timescale 1ns / 1ps
/*============================================================================
	Aznable (custom 8-bit computer system) - Verilator emu module

	Author: Jim Gregory - https://github.com/JimmyStones/
	Version: 1.1
	Date: 2021-10-17

	This program is free software; you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the Free
	Software Foundation; either version 3 of the License, or (at your option)
	any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program. If not, see <http://www.gnu.org/licenses/>.
===========================================================================*/

module emu (

	input clk_sys,
	input reset,
	input menu,
	
	input [31:0] joystick_0,
	input [31:0] joystick_1,
	input [31:0] joystick_2,
	input [31:0] joystick_3,
	input [31:0] joystick_4,
	input [31:0] joystick_5,
	
	input [15:0] joystick_l_analog_0,
	input [15:0] joystick_l_analog_1,
	input [15:0] joystick_l_analog_2,
	input [15:0] joystick_l_analog_3,
	input [15:0] joystick_l_analog_4,
	input [15:0] joystick_l_analog_5,
	
	input [15:0] joystick_r_analog_0,
	input [15:0] joystick_r_analog_1,
	input [15:0] joystick_r_analog_2,
	input [15:0] joystick_r_analog_3,
	input [15:0] joystick_r_analog_4,
	input [15:0] joystick_r_analog_5,

	input [7:0] paddle_0,
	input [7:0] paddle_1,
	input [7:0] paddle_2,
	input [7:0] paddle_3,
	input [7:0] paddle_4,
	input [7:0] paddle_5,

	input [8:0] spinner_0,
	input [8:0] spinner_1,
	input [8:0] spinner_2,
	input [8:0] spinner_3,
	input [8:0] spinner_4,
	input [8:0] spinner_5,

	// ps2 alternative interface.
	// [8] - extended, [9] - pressed, [10] - toggles with every press/release
	input [10:0] ps2_key,

	// [24] - toggles with every event
	input [24:0] ps2_mouse,
	input [15:0] ps2_mouse_ext, // 15:8 - reserved(additional buttons), 7:0 - wheel movements

	// [31:0] - seconds since 1970-01-01 00:00:00, [32] - toggle with every change
	input [32:0] timestamp,

	output [7:0] VGA_R,
	output [7:0] VGA_G,
	output [7:0] VGA_B,
	
	output VGA_HS,
	output VGA_VS,
	output VGA_HB,
	output VGA_VB,

	output CE_PIXEL,
	
	output	[15:0]	AUDIO_L,
	output	[15:0]	AUDIO_R,
	
	input			ioctl_download,
	input			ioctl_wr,
	input [24:0]	ioctl_addr,
	input [7:0]		ioctl_dout,
	input [7:0]		ioctl_index,
	output reg		ioctl_wait=1'b0
);
wire [31:0] joy_0 = joystick_0;
wire [31:0] joy_1 = joystick_1;
wire [8:0] video;
assign VGA_R={video[8:6],video[8],4'b0};
assign VGA_G={video[5:3],video[5],4'b0};
assign VGA_B={video[2:0],video[2],4'b0};

wire [1:0] mode = 2'b10; // b0 = 48k, b1 = 96k
wire crtcDe;
wire ear;

lynx48 lynx48
(
        .clock    (clk_sys),
        .reset_osd(~reset),
        .led      (),

        .hSync    (VGA_HS ),
        .vSync    (VGA_VS),
        .vBlank   (VGA_VB),
        .hBlank   (VGA_HB),
        .crtcDe   (crtcDe ),
        .rgb      (video  ),

        .ps2      (ps2_key    ),
        .joy_0    (~{1'b0,1'b0,joy_0[4],1'b0,joy_0[0],joy_0[1],joy_0[2],joy_0[3]} ),
        .joy_1    (~{1'b0,1'b0,joy_1[4],1'b0,joy_1[0],joy_1[1],joy_1[2],joy_1[3]} ),

        .audio    (AUDIO_L),
        .ear      (ear    ),

        //      Removed offset addition
        .ioctl_addr                     (ioctl_addr                     ),
        .ioctl_data                     (ioctl_dout ),
        .ioctl_download         (ioctl_download         ),
        .ioctl_index            (ioctl_index            ),
        .ioctl_wr                       (ioctl_wr                       ),

        .ce_pix                         (CE_PIXEL),
        .mode                           (mode                           )
);

/* verilator lint_on PINMISSING */

// Debug defines
`define DEBUG_SIMULATION


endmodule 

