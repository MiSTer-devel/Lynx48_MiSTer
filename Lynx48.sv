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
//
//  Camputers Lynx 48K / 96K / 96K Scorpion / 128K for MiSTer.
//  Machine: Kyp's lynx and lynx128 (GPL v3), as merged by Shaeon (shaeon/Lynx_MiSTer), in
//  rtl/lynx_core.sv. Earlier MiSTer port: rampa069, Yo_Me, JasonA, JimmyStones, alanswx.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////
// OSD (osd-standard.md, video-standard.md, tape-standard.md)
//
// status bits: 0 reset, [4:3] Model, [5] CAS blanking, [7:6] Aspect ratio, [9:8] Scale,
// [12:10] Scandoubler Fx, [13] Swap joysticks, [15] Tape overlay, [16] Tape speed, [17] Tape audio,
// [18] Invert tape in, [19] Rewind tape (button).
// Machine settings (Model, CAS blanking) wait for Apply and reset; video, input and tape rows act
// at once. v,1: the 2022 core's bits (Scandoubler at [2:1], 16:9 at [5], Autostart at [6]) are
// dropped.

`include "build_id.v"
localparam CONF_STR = {
	"Lynx48;;",
	"-;",
	"S0,LDF,Disk;",
	"F1,TAPTZXWAV,Tape;",
	"F0,ROM,Load ROM;",
	"-;",
	"P1,Machine;",
	"P2,Video;",
	"P3,Input;",
	"P4,Audio;",
	"-;",
	"h0-,Changes pending;",
	"R[0],Apply and reset;",

	"P1O[4:3],Model,Lynx 48K,Lynx 96K,96K Scorpion,Lynx 128K;",
	"H1P1O[5],CAS blanking,On,Off;",
	"h1P1-;",
	"P1O[16],Tape speed,4x,Normal;",
	"P1-;",
	"P1T[19],Rewind tape;",

	"P2O[7:6],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P2O[9:8],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P2O[12:10],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P2-;",
	"P2O[15],Tape overlay,On,Off;",

	"P3O[13],Swap joysticks,No,Yes;",

	"P4O[17],Tape audio,Off,On;",
	"P4O[18],Invert tape in,No,Yes;",

	"I,Tape ready (rewound);",
	"J,Fire;",
	"jn,A;",
	"v,1;",
	"V,v",`BUILD_DATE
};

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;      // 48 MHz
wire pll_locked;

pll pll
(
	.refclk  (CLK_50M   ),
	.rst     (0         ),
	.outclk_0(clk_sys   ),
	.outclk_1(          ),
	.outclk_2(          ),
	.locked  (pll_locked)
);

///////////////////////   HPS   //////////////////////////////////

wire         forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [21:0] gamma_bus;
wire  [10:0] ps2_key;
wire  [31:0] joystick_0, joystick_1;

wire         ioctl_download;
wire  [15:0] ioctl_index;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire         ioctl_wait;

wire   [0:0] img_mounted;
wire         img_readonly;
wire  [63:0] img_size;
wire  [31:0] sd_lba[1];
wire   [0:0] sd_rd, sd_wr, sd_ack;
wire  [13:0] sd_buff_addr;
wire   [7:0] sd_buff_dout;
wire   [7:0] sd_buff_din[1];
wire         sd_buff_wr;

// settings the machine runs with, taken from the OSD at every reset
reg  [127:0] cfg = 128'd0;
wire         pending = status[5:3] != cfg[5:3];
wire         no_cas  = status[4:3] == 2'd3;          // CAS blanking: 48K / 96K only

reg          info_req = 0;

hps_io #(.CONF_STR(CONF_STR), .VDNUM(1)) hps_io
(
	.clk_sys           (clk_sys           ),
	.HPS_BUS           (HPS_BUS           ),
	.EXT_BUS           (                  ),
	.gamma_bus         (gamma_bus         ),
	.forced_scandoubler(forced_scandoubler),
	.buttons           (buttons           ),
	.status            (status            ),
	.status_menumask   ({ 14'd0, no_cas, pending }),
	.info_req          (info_req          ),
	.info              (8'd1              ),
	.ps2_key           (ps2_key           ),
	.joystick_0        (joystick_0        ),
	.joystick_1        (joystick_1        ),

	.ioctl_download    (ioctl_download    ),
	.ioctl_index       (ioctl_index       ),
	.ioctl_wr          (ioctl_wr          ),
	.ioctl_addr        (ioctl_addr        ),
	.ioctl_dout        (ioctl_dout        ),
	.ioctl_wait        (ioctl_wait        ),

	.img_mounted       (img_mounted       ),
	.img_readonly      (img_readonly      ),
	.img_size          (img_size          ),
	.sd_lba            (sd_lba            ),
	.sd_blk_cnt        ('{6'd0}           ),
	.sd_rd             (sd_rd             ),
	.sd_wr             (sd_wr             ),
	.sd_ack            (sd_ack            ),
	.sd_buff_addr      (sd_buff_addr      ),
	.sd_buff_dout      (sd_buff_dout      ),
	.sd_buff_din       (sd_buff_din       ),
	.sd_buff_wr        (sd_buff_wr        )
);

// boot.rom / Load ROM: index 0; boot1.rom (128K): index 0x40 (Main loads bootN.rom as N << 6)
wire rom_dl  = ioctl_download && ioctl_index[5:0] == 6'd0;
wire tape_dl = ioctl_download && ioctl_index[5:0] == 6'd1;

///////////////////////   RESET   ////////////////////////////////

wire key_F9, key_play, key_stop;

// held while anything below asks; the settings are taken from the OSD while it is held
wire reset_req = !pll_locked || RESET || status[0] || buttons[1] || !key_F9 || rom_dl;

always @(posedge clk_sys) if(reset_req) cfg <= status;

///////////////////////   TAPE   /////////////////////////////////
// The image goes to DDR3 (Shaeon's tape_ddr). A Lynx .TAP is played by rtl/lynx_tap.sv, a .TZX
// by tzxplayer. The deck plays while the motor relay is on (port 80h d1, 128K d3); a TZX can also
// be started / stopped with PgUp / PgDn. Every mount starts rewound. Turbo: CPU and tape 4x while
// the deck plays (tape-standard.md); Tape speed is read at each motor-on.
// Tape overlay (status bar while it plays, next-step hint while it is stopped):
// rtl/lynx_tape_overlay.sv.

wire motor, cpu_ce, m128;
wire [2:0] tape_speed, tap_speed_used;
wire tzx_busy, tzx_tape, tape_wait;
reg  motor_d = 0, fast = 0;
reg  tape_dl_d = 0;
always @(posedge clk_sys) tape_dl_d <= tape_dl;
wire tape_dl_end = tape_dl_d && !tape_dl;

always @(posedge clk_sys) begin
	motor_d <= motor;
	if(motor && !motor_d) fast <= !status[16];
	info_req <= tape_dl_end;
end

wire        is_tap;
wire [27:0] tap_size;
wire [24:0] tap_addr;
wire        tap_req, tap_ack;
wire  [7:0] tap_q;
wire        tap_tape, tap_running;
// a .WAV (RIFF) is played by rtl/lynx_wav.sv through the same byte port
reg         is_wav = 0;
always @(posedge clk_sys) if(tape_dl && ioctl_wr && ioctl_addr < 4)
	case(ioctl_addr[1:0])
		2'd0: is_wav <= ioctl_dout == "R";
		2'd1: is_wav <= is_wav && ioctl_dout == "I";
		2'd2: is_wav <= is_wav && ioctl_dout == "F";
		2'd3: is_wav <= is_wav && ioctl_dout == "F";
	endcase
wire        tap_loaded = is_tap && !is_wav && tap_size != 0;
wire        wav_loaded = is_tap &&  is_wav && tap_size != 0;
wire [24:0] wav_addr;
wire        wav_req, wav_tape, wav_running, wav_valid;
wire [31:0] wav_rate, wav_len;
wire [24:0] wav_pos;
wire  [2:0] wav_align;

lynx_wav lynx_wav
(
	.clock    (clk_sys          ),
	.rewind   (tape_dl || status[19]),
	.cpu_ce   (cpu_ce           ),
	.m128     (m128             ),
	.play     (motor            ),
	.size     (wav_loaded ? tap_size[24:0] : 25'd0),
	.rd_addr  (wav_addr         ),
	.rd_req   (wav_req          ),
	.rd_ack   (tap_ack && is_wav),
	.rd_data  (tap_q            ),
	.tape     (wav_tape         ),
	.running  (wav_running      ),
	.eot      (                 ),
	.pos      (wav_pos          ),
	.valid    (wav_valid        ),
	.rate     (wav_rate         ),
	.data_len (wav_len          ),
	.align    (wav_align        )
);

lynx_tap lynx_tap
(
	.clock    (clk_sys          ),
	.rewind   (tape_dl || status[19]),
	.cpu_ce   (cpu_ce           ),
	.m128     (m128             ),
	.play     (motor            ),
	.speed    (tape_speed       ),
	.size     (tap_loaded ? tap_size[24:0] : 25'd0),
	.rd_addr  (tap_addr         ),
	.rd_req   (tap_req          ),
	.rd_ack   (tap_ack && !is_wav),
	.rd_data  (tap_q            ),
	.tape     (tap_tape         ),
	.running  (tap_running      ),
	.eot      (tap_eot          ),
	.pos      (tap_pos          ),
	.file_type(tap_file_type    ),
	.in_file  (tap_in_file      ),
	.speed_used(tap_speed_used  )
);

wire        tap_eot, tap_in_file;
wire [24:0] tap_pos;
wire  [7:0] tap_file_type;

wire turbo = fast && motor && (tap_running || wav_running || tzx_busy);

// tzxplayer: one ce per 1/12 MHz at 1x, every clock at 4x
reg [1:0] tzx_div = 0;
always @(posedge clk_sys) tzx_div <= tzx_div + 1'd1;
wire tzx_ce = turbo || tzx_div == 0;


tape_ddr #(.MS(12000)) tape_ddr
(
	.clock           (clk_sys           ),
	.ce              (tzx_ce            ),
	.dl              (tape_dl           ),
	.dlA             (ioctl_addr        ),
	.dlD             (ioctl_dout        ),
	.dlW             (ioctl_wr && tape_dl),
	.dlWait          (tape_wait         ),
	.play            ((motor && !motor_d) || !key_play),
	.stop            ((!motor && motor_d) || !key_stop || status[19]),
	.stop48          (1'b1              ),
	.busy            (tzx_busy          ),
	.tape            (tzx_tape          ),
	.is_tap          (is_tap            ),
	.tap_size        (tap_size          ),
	.ext_a           (is_wav ? wav_addr : tap_addr),
	.ext_req         (is_wav ? wav_req  : tap_req ),
	.ext_ack         (tap_ack           ),
	.ext_q           (tap_q             ),
	.DDRAM_CLK       (DDRAM_CLK         ),
	.DDRAM_BUSY      (DDRAM_BUSY        ),
	.DDRAM_BURSTCNT  (DDRAM_BURSTCNT    ),
	.DDRAM_ADDR      (DDRAM_ADDR        ),
	.DDRAM_DOUT      (DDRAM_DOUT        ),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY  ),
	.DDRAM_RD        (DDRAM_RD          ),
	.DDRAM_DIN       (DDRAM_DIN         ),
	.DDRAM_BE        (DDRAM_BE          ),
	.DDRAM_WE        (DDRAM_WE          )
);

assign ioctl_wait = tape_wait;

// tape from the line-in ADC (a real cassette)
wire adc_tape, adc_act;

ltc2308_tape ltc2308_tape
(
	.reset   (1'b0    ),
	.clk     (CLK_50M ),
	.ADC_BUS (ADC_BUS ),
	.dout    (adc_tape),
	.active  (adc_act ),
	.adc_sync(        ),
	.adc_data(        )
);

reg [1:0] adc_tape_s = 0, adc_act_s = 0;
always @(posedge clk_sys) begin
	adc_tape_s <= { adc_tape_s[0], adc_tape };
	adc_act_s  <= { adc_act_s[0],  adc_act  };
end

wire tape_in = tap_loaded ? tap_tape : wav_loaded ? wav_tape ^ status[18] : tzx_busy ? tzx_tape
             : adc_act_s[1] && (adc_tape_s[1] ^ status[18]);

///////////////////////   MACHINE   //////////////////////////////

wire [31:0] joyA = status[13] ? joystick_1 : joystick_0;
wire [31:0] joyB = status[13] ? joystick_0 : joystick_1;

// active low { -, -, fire, -, right, left, down, up } (Kyp's mist.v)
wire [7:0] joy0 = ~{ 2'b00, joyA[4], 1'b0, joyA[0], joyA[1], joyA[2], joyA[3] };
wire [7:0] joy1 = ~{ 2'b00, joyB[4], 1'b0, joyB[0], joyB[1], joyB[2], joyB[3] };

wire       ce_pix, HSync, VSync, HBlank, VBlank, R, G, B;
wire [5:0] sound;
wire       fdc_busy;
wire       disk_cpm, dos_run, disk_read;
reg        disk_loaded = 0;
always @(posedge clk_sys) if(img_mounted[0]) disk_loaded <= |img_size;

lynx_core lynx_core
(
	.clock       (clk_sys          ),
	.reset       (reset_req        ),
	.model       (cfg[4:3]         ),
	.casM        (!cfg[5]          ),
	.turbo       (turbo            ),

	.rom_wr      (rom_dl && ioctl_wr),
	.rom_sel128  (ioctl_index[6]   ),
	.rom_addr    (ioctl_addr[15:0] ),
	.rom_data    (ioctl_dout       ),

	.ps2_key     (ps2_key          ),
	.joy0        (joy0             ),
	.joy1        (joy1             ),
	.key_F9      (key_F9           ),
	.key_play    (key_play         ),
	.key_stop    (key_stop         ),

	.tape_in     (tape_in          ),
	.motor       (motor            ),

	.img_mounted (img_mounted[0]   ),
	.img_readonly(img_readonly     ),
	.img_size    (img_size         ),
	.sd_lba      (sd_lba[0]        ),
	.sd_rd       (sd_rd[0]         ),
	.sd_wr       (sd_wr[0]         ),
	.sd_ack      (sd_ack[0]        ),
	.sd_buff_addr(sd_buff_addr[8:0]),
	.sd_buff_dout(sd_buff_dout     ),
	.sd_buff_din (sd_buff_din[0]   ),
	.sd_buff_wr  (sd_buff_wr       ),
	.fdc_busy    (fdc_busy         ),
	.disk_cpm    (disk_cpm         ),
	.dos_run     (dos_run          ),
	.disk_read   (disk_read        ),

	.sound       (sound            ),

	.ce_pix      (ce_pix           ),
	.HSync       (HSync            ),
	.VSync       (VSync            ),
	.HBlank      (HBlank           ),
	.VBlank      (VBlank           ),
	.R           (R                ),
	.G           (G                ),
	.B           (B                ),
	.m128        (m128             ),
	.cpu_ce      (cpu_ce           ),
	.tape_speed  (tape_speed       ),
	.dbg_cf      (                 ),
	.dbg_a       (                 )
);

///////////////////////   AUDIO   ////////////////////////////////
// 6-bit DAC (port 84h) and, with Tape audio On, the tape signal at a lower level.

wire        tape_snd = status[17] && motor && tape_in;
wire [15:0] mix = { 2'b00, sound, 8'd0 } + { 3'b000, {11{ tape_snd }}, 2'b00 };

assign AUDIO_L = mix;
assign AUDIO_R = mix;

///////////////////////   LEDS   /////////////////////////////////

assign LED_USER = ioctl_download || tzx_busy || tap_running || wav_running;
assign LED_DISK = { 1'b0, fdc_busy };

///////////////////////   VIDEO   ////////////////////////////////
// Picture: 256 x 252 at 6 MHz (48K / 96K) or 512 x 252 at 12 MHz (128K), 50 Hz.
// Original aspect: PAL square pixels are 7.375 MHz, so 256 pixels at 6 MHz are 256 * 7.375 / 6 =
// 314.67 square pixels wide: 314.67 : 252 = 236 : 189 (1.249). The 128K is the same. To be
// checked on hardware (video-standard.md, Moving a core over, step 7).

wire [1:0] ar  = status[7:6];
wire [2:0] sfx = status[12:10];          // 0 None, 1 HQ2x, 2-4 CRT 25/50/75%
wire [2:0] sl  = sfx ? sfx - 3'd1 : 3'd0;
wire       scandoubler = sfx != 3'd0 || forced_scandoubler;

assign CLK_VIDEO = clk_sys;
assign VGA_SL = sl[1:0];

wire vga_de;

wire [272:0] ov_status;
wire         ov_req, ov_ack;
wire  [23:0] ov_rgb;

lynx_tape_status tape_status
(
	.clk      (clk_sys          ),
	.dl_start (tape_dl && !tape_dl_d),
	.dl_wr    (tape_dl && ioctl_wr),
	.dl_data  (ioctl_dout       ),
	.dl_busy  (tape_dl          ),
	.is_tap   (is_tap && !is_wav),
	.wav      (wav_valid        ),
	.wav_rate (wav_rate         ),
	.wav_len  (wav_len          ),
	.wav_align(wav_align        ),
	.loaded   (tap_size != 0    ),
	.m128     (m128             ),
	.speed    (tap_speed_used   ),
	.playing  (is_wav ? wav_running : is_tap ? motor && !tap_eot : tzx_busy),
	.moving   (tap_running || wav_running),
	.fast     (turbo            ),
	.position (is_wav ? wav_pos : tap_pos),
	.length   (tap_size[24:0]   ),
	.in_file  (tap_in_file      ),
	.file_type(tap_file_type    ),
	.ps2_key  (ps2_key          ),
	.disk_loaded(disk_loaded    ),
	.disk_iface(cfg[4:3] != 2'd0),
	.disk_cpm (disk_cpm         ),
	.dos_run  (dos_run          ),
	.disk_read(disk_read        ),
	.status   (ov_status        ),
	.req      (ov_req           ),
	.ack      (ov_ack           )
);

lynx_tape_overlay tape_overlay
(
	.clk      (CLK_VIDEO        ),
	.ce_pix   (ce_pix           ),
	.hblank   (HBlank           ),
	.vblank   (VBlank           ),
	.enable   (!status[15]      ),
	.status   (ov_status        ),
	.req      (ov_req           ),
	.ack      (ov_ack           ),
	.rgb_in   ({{8{R}}, {8{G}}, {8{B}}}),
	.rgb_out  (ov_rgb           )
);

video_freak video_freak
(
	.CLK_VIDEO  (CLK_VIDEO  ),
	.CE_PIXEL   (CE_PIXEL   ),
	.VGA_VS     (VGA_VS     ),
	.HDMI_WIDTH (HDMI_WIDTH ),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE     (VGA_DE     ),
	.VIDEO_ARX  (VIDEO_ARX  ),
	.VIDEO_ARY  (VIDEO_ARY  ),
	.VGA_DE_IN  (vga_de     ),
	.ARX        ((!ar) ? 12'd236 : (ar - 1'd1)),
	.ARY        ((!ar) ? 12'd189 : 12'd0),
	.CROP_SIZE  (12'd0      ),
	.CROP_OFF   (5'd0       ),
	.SCALE      ({ 1'b0, status[9:8] })
);

video_mixer #(.LINE_LENGTH(520), .GAMMA(1)) video_mixer
(
	.CLK_VIDEO  (CLK_VIDEO  ),
	.CE_PIXEL   (CE_PIXEL   ),
	.ce_pix     (ce_pix     ),
	.scandoubler(scandoubler),
	.hq2x       (sfx == 3'd1),
	.gamma_bus  (gamma_bus  ),
	.R          (ov_rgb[23:16]),
	.G          (ov_rgb[15:8] ),
	.B          (ov_rgb[7:0]  ),
	.HSync      (HSync      ),
	.VSync      (VSync      ),
	.HBlank     (HBlank     ),
	.VBlank     (VBlank     ),
	.HDMI_FREEZE(HDMI_FREEZE),
	.freeze_sync(           ),
	.VGA_R      (VGA_R      ),
	.VGA_G      (VGA_G      ),
	.VGA_B      (VGA_B      ),
	.VGA_VS     (VGA_VS     ),
	.VGA_HS     (VGA_HS     ),
	.VGA_DE     (vga_de     )
);

endmodule
