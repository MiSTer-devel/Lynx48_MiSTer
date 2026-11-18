// Simulation top: lynx_core with the hps_io side replaced by plain ports driven from sim_main.cpp.
module lynx_sim
(
	input  wire        clk,            // 48 MHz clk_sys
	input  wire        reset,
	input  wire [ 1:0] model,
	input  wire        turbo,
	input  wire        rom_wr,
	input  wire        rom_sel128,
	input  wire [15:0] rom_addr,
	input  wire [ 7:0] rom_data,
	input  wire [10:0] ps2_key,
	input  wire [ 7:0] joy0,
	input  wire [ 7:0] joy1,
	input  wire        tape_adc,       // used when no TAP is loaded
	input  wire        tape_rewind,
	input  wire        is_wav,         // the image is a RIFF WAV: lynx_wav plays it
	input  wire [24:0] tape_size,
	output wire [24:0] tape_addr,
	output wire        tape_req,
	input  wire        tape_ack,
	input  wire [ 7:0] tape_data,
	output wire        tape_level,
	output wire        tape_eot,
	output wire [24:0] tape_pos,
	output wire [ 2:0] tape_spd,
	output wire [15:0] dbg_cf,
	input  wire        dl_start,       // the tape image as hps_io sends it (for the overlay's parser)
	input  wire        dl_busy,
	input  wire        dl_wr,
	input  wire [ 7:0] dl_data,
	input  wire        overlay_on,
	input  wire        img_mounted,    // disk image (SD block interface, as hps_io)
	input  wire [31:0] img_size,
	output wire [31:0] sd_lba,
	output wire        sd_rd,
	output wire        sd_wr,
	input  wire        sd_ack,
	input  wire [ 8:0] sd_buff_addr,
	input  wire [ 7:0] sd_buff_dout,
	input  wire        sd_buff_wr,
	output wire        dos_run,
	output wire        disk_read,
	output wire        disk_cpm,
	output wire [23:0] rgb,            // picture after the tape overlay
	output wire        motor,
	output wire [ 5:0] sound,
	output wire        ce_pix,
	output wire        HSync,
	output wire        VSync,
	output wire        HBlank,
	output wire        VBlank,
	output wire        R,
	output wire        G,
	output wire        B,
	output wire [15:0] dbg_a
);

wire cpu_ce, m128, tape_in, tap_tape;
wire [2:0] tape_speed, speed_used;
assign tape_spd = tape_speed;

wire [24:0] tap_addr, wav_addr, wav_pos, tap_pos;
wire        tap_req, wav_req, wav_tape, wav_running, wav_eot, tap_eot;
assign tape_addr = is_wav ? wav_addr : tap_addr;
assign tape_req  = is_wav ? wav_req  : tap_req;
assign tape_pos  = is_wav ? wav_pos  : tap_pos;
assign tape_eot  = is_wav ? wav_eot  : tap_eot;

lynx_wav wav
(
	.clock    (clk        ),
	.rewind   (tape_rewind),
	.cpu_ce   (cpu_ce     ),
	.m128     (m128       ),
	.play     (motor      ),
	.size     (is_wav ? tape_size : 25'd0),
	.rd_addr  (wav_addr   ),
	.rd_req   (wav_req    ),
	.rd_ack   (tape_ack && is_wav),
	.rd_data  (tape_data  ),
	.tape     (wav_tape   ),
	.running  (wav_running),
	.eot      (wav_eot    ),
	.pos      (wav_pos    ),
	.valid    (           ),
	.rate     (           ),
	.data_len (           ),
	.align    (           )
);

lynx_tap tap
(
	.clock    (clk        ),
	.rewind   (tape_rewind),
	.cpu_ce   (cpu_ce     ),
	.m128     (m128       ),
	.play     (motor      ),
	.speed    (tape_speed ),
	.size     (is_wav ? 25'd0 : tape_size),
	.rd_addr  (tap_addr   ),
	.rd_req   (tap_req    ),
	.rd_ack   (tape_ack && !is_wav),
	.rd_data  (tape_data  ),
	.tape     (tap_tape   ),
	.running  (           ),
	.eot      (tap_eot    ),
	.pos      (tap_pos    ),
	.file_type(file_type  ),
	.in_file  (in_file    ),
	.speed_used(speed_used)
);

wire [7:0]   file_type;
wire         in_file;
wire [272:0] ov_status;
wire         ov_req, ov_ack;

lynx_tape_status tape_status
(
	.clk      (clk         ),
	.dl_start (dl_start    ),
	.dl_wr    (dl_wr       ),
	.dl_data  (dl_data     ),
	.dl_busy  (dl_busy     ),
	.is_tap   (1'b1        ),
	.loaded   (tape_size != 0),
	.m128     (m128        ),
	.speed    (speed_used  ),
	.playing  (motor       ),
	.moving   (motor && !tape_eot),
	.fast     (turbo && motor && !tape_eot),
	.position (tape_pos    ),
	.length   (tape_size   ),
	.in_file  (in_file     ),
	.file_type(file_type   ),
	.ps2_key  (ps2_key     ),
	.disk_loaded(img_size != 0),
	.disk_iface(model != 2'd0),
	.disk_cpm (disk_cpm    ),
	.dos_run  (dos_run     ),
	.disk_read(disk_read   ),
	.status   (ov_status   ),
	.req      (ov_req      ),
	.ack      (ov_ack      )
);

lynx_tape_overlay tape_overlay
(
	.clk      (clk         ),
	.ce_pix   (ce_pix      ),
	.hblank   (HBlank      ),
	.vblank   (VBlank      ),
	.enable   (overlay_on  ),
	.status   (ov_status   ),
	.req      (ov_req      ),
	.ack      (ov_ack      ),
	.rgb_in   ({{8{R}}, {8{G}}, {8{B}}}),
	.rgb_out  (rgb         )
);

assign tape_in    = tape_size == 0 ? tape_adc : is_wav ? wav_tape : tap_tape;
assign tape_level = tape_in;

lynx_core core
(
	.clock       (clk         ),
	.reset       (reset       ),
	.model       (model       ),
	.casM        (1'b1        ),
	.turbo       (turbo       ),
	.rom_wr      (rom_wr      ),
	.rom_sel128  (rom_sel128  ),
	.rom_addr    (rom_addr    ),
	.rom_data    (rom_data    ),
	.ps2_key     (ps2_key     ),
	.joy0        (joy0        ),
	.joy1        (joy1        ),
	.key_F9      (            ),
	.key_play    (            ),
	.key_stop    (            ),
	.tape_in     (tape_in     ),
	.cpu_ce      (cpu_ce      ),
	.tape_speed  (tape_speed  ),
	.dbg_cf      (dbg_cf      ),
	.motor       (motor       ),
	.img_mounted (img_mounted ),
	.img_readonly(1'b1        ),
	.img_size    ({ 32'd0, img_size }),
	.sd_lba      (sd_lba      ),
	.sd_rd       (sd_rd       ),
	.sd_wr       (sd_wr       ),
	.sd_ack      (sd_ack      ),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din (            ),
	.sd_buff_wr  (sd_buff_wr  ),
	.fdc_busy    (            ),
	.disk_cpm    (disk_cpm    ),
	.dos_run     (dos_run     ),
	.disk_read   (disk_read   ),
	.sound       (sound       ),
	.ce_pix      (ce_pix      ),
	.HSync       (HSync       ),
	.VSync       (VSync       ),
	.HBlank      (HBlank      ),
	.VBlank      (VBlank      ),
	.R           (R           ),
	.G           (G           ),
	.B           (B           ),
	.m128        (m128        ),
	.dbg_a       (dbg_a       )
);

endmodule
