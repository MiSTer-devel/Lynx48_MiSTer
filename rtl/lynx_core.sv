//-------------------------------------------------------------------------------------------------
// Camputers Lynx 48K / 96K / 96K Scorpion / 128K: everything that is the machine.
//
// Both of Kyp's machines (rtl/lynx_48k.v, rtl/lynx_128k.v) are in here; only the selected one runs,
// the other is held in reset. They share the ROM loader, user RAM, the WD1793, keyboard, joysticks,
// tape input, audio and video out. The structure follows Shaeon's Lynx_MiSTer (Lynx.sv), with the
// memories in block RAM instead of SDRAM, so the core runs without an SDRAM module, and with a
// turbo input for tape loading. The emu top (Lynx48.sv) and the Verilator sim both use this module.
//
// Memory (block RAM):
//   rom48   64K  boot.rom  (ioctl index 0):  48K-1, 48K-2, 96K-1, 96K-2, 96K-3, Scorpion, XDOS, FF
//   rom128  32K  boot1.rom (ioctl index 40h): 128K-1, 128K-2, 128K-3, XDOS
//   ram1    64K  bank 1 user RAM (48K: 16K mirrored as Kyp maps it, 96K / 128K: 64K)
//   ram4    64K  128K bank 4
//   vram2 / vram3  2 x 16K  48K / 96K video (red+blue / green+alt green)
//   vram128 64K  128K video
//-------------------------------------------------------------------------------------------------
module lynx_core
(
	input  wire        clock,          // 48 MHz
	input  wire        reset,          // active high: machine held in reset
	input  wire [ 1:0] model,          // 0 48K, 1 96K, 2 96K Scorpion, 3 128K (latched by the top)
	input  wire        casM,           // Kyp's "bank 2 CAS enable" (48K / 96K)
	input  wire        turbo,          // 1: CPU 4x (tape loading)

	// ROM download (hps_io ioctl)
	input  wire        rom_wr,
	input  wire        rom_sel128,     // 0 boot.rom, 1 boot1.rom
	input  wire [15:0] rom_addr,
	input  wire [ 7:0] rom_data,

	// keyboard / joysticks
	input  wire [10:0] ps2_key,
	input  wire [ 7:0] joy0,           // active low { -, -, fire, -, right, left, down, up }
	input  wire [ 7:0] joy1,
	output wire        key_F9,         // active low
	output wire        key_play,       // active low
	output wire        key_stop,       // active low

	// tape
	input  wire        tape_in,        // level into the tape input port bit
	output wire        motor,          // tape motor relay

	// floppy (hps_io SD block interface, one drive)
	input  wire        img_mounted,
	input  wire        img_readonly,
	input  wire [63:0] img_size,
	output wire [31:0] sd_lba,
	output wire        sd_rd,
	output wire        sd_wr,
	input  wire        sd_ack,
	input  wire [ 8:0] sd_buff_addr,
	input  wire [ 7:0] sd_buff_dout,
	output wire [ 7:0] sd_buff_din,
	input  wire        sd_buff_wr,
	output wire        fdc_busy,
	output reg         disk_cpm,       // the mounted disk is a CP/M boot disk (sector 0: 00 00 18 ...)
	output reg         dos_run,        // the DOS ROM has run since reset (XROM)
	output reg         disk_read,      // a sector has been read since the disk was mounted

	// audio: 6-bit DAC (port 84h)
	output wire [ 5:0] sound,

	// video (on clock): one ce_pix per pixel, positive syncs and blanks, 1 bit per gun
	output reg         ce_pix,
	output reg         HSync,
	output reg         VSync,
	output reg         HBlank,
	output reg         VBlank,
	output reg         R,
	output reg         G,
	output reg         B,
	output wire        m128,
	output wire        cpu_ce,         // the running CPU's clock enable (tape timebase)
	output reg  [ 2:0] tape_speed,     // BASIC TAPE n (0-5) of the 48K / 96K, for lynx_tap
	output wire [15:0] dbg_cf,         // COARSE, FINE (debug)

	// debug
	output wire [15:0] dbg_a
);

//--- clock enables -------------------------------------------------------------------------------
// As in Kyp's psd.v / Shaeon's Lynx.sv, plus turbo: the CPU (and with it the port registers and
// the WD1793, which run on the CPU enable) goes 4x; the 6845 and the pixel clock stay at 1x.

	reg [5:0] ce6 = 6'd0;
	always @(negedge clock) ce6 <= ce6 + 1'd1;

	wire pe12M = ce6[1:0] == 1;            // 128K pixel
	wire pe06M = ce6[2:0] == 3;            // 48/96K pixel
	wire peM75 = ce6[5:0] == 31;           // 48/96K 6845
	wire pe1M5 = ce6[4:0] == 15;           // 128K 6845

	// 48/96K CPU: 4 MHz = 48 / 12 (pe at 5, ne at 11); turbo 16 MHz = 48 / 3
	reg [3:0] ce4 = 4'd0;
	wire      ce4_end = turbo ? ce4 == 4'd2 : ce4 == 4'd11;
	always @(negedge clock) ce4 <= ce4_end ? 4'd0 : ce4 + 1'd1;
	wire pe04M = turbo ? ce4 == 4'd0 : ce4 == 4'd5;
	wire ne04M = turbo ? ce4 == 4'd2 : ce4 == 4'd11;

	// 128K CPU: 6 MHz = 48 / 8 (pe at 3, ne at 7); turbo 24 MHz = 48 / 2
	wire pe6M0 = turbo ? !ce6[0] : ce6[2:0] == 3;
	wire ne6M0 = turbo ?  ce6[0] : ce6[2:0] == 7;

//--- model ---------------------------------------------------------------------------------------

	assign m128 = model == 2'd3;
	wire ramM = model == 2'd1 || model == 2'd2;   // 96K
	wire romX = model == 2'd2;                    // Scorpion ROM

	wire reset48  = !reset && !m128;              // active low
	wire reset128 = !reset &&  m128;

//--- keyboard ------------------------------------------------------------------------------------

	wire [3:0] row48, row128;
	wire [3:0] row = m128 ? row128 : row48;
	wire [7:0] col;
	wire       esc;

	matrix matrix
	(
		.clock  (clock   ),
		.ps2_key(ps2_key ),
		.row    (row     ),
		.col    (col     ),
		.esc    (esc     ),
		.F9     (key_F9  ),
		.play   (key_play),
		.stop   (key_stop)
	);

//--- ROMs ----------------------------------------------------------------------------------------

	reg [7:0] rom48 [0:65535];
	reg [7:0] rom128[0:32767];
	initial begin
		$readmemh("boot.hex",  rom48);
		$readmemh("boot1.hex", rom128);
	end

	wire [15:0] mem0A48, mem0A128;
	wire        mem0R48, mem0R128;

	// ROM pages, as romP in Kyp's psd.v
	reg [2:0] romP48;
	always @*
		casex({ romX, ramM, mem0A48[15:13] })
			5'bx_0_000: romP48 = 3'd0;  // 48K-1
			5'bx_0_001: romP48 = 3'd1;  // 48K-2
			5'bx_1_000: romP48 = 3'd2;  // 96K-1
			5'bx_1_001: romP48 = 3'd3;  // 96K-2
			5'b0_1_010: romP48 = 3'd4;  // 96K-3
			5'b1_1_010: romP48 = 3'd5;  // 96K-3 Scorpion
			5'bx_x_111: romP48 = 3'd6;  // XDOS
			default:    romP48 = 3'd7;
		endcase

	wire [1:0] romP128 = mem0A128[15:13] <= 3'd2 ? mem0A128[14:13] : 2'd3;

	reg [7:0] rom48Q, rom128Q;
	always @(posedge clock) begin
		if(rom_wr && !rom_sel128) rom48[rom_addr] <= rom_data;
		rom48Q <= rom48[{ romP48, mem0A48[12:0] }];
	end
	always @(posedge clock) begin
		if(rom_wr && rom_sel128) rom128[rom_addr[14:0]] <= rom_data;
		rom128Q <= rom128[{ romP128, mem0A128[12:0] }];
	end

//--- user RAM (bank 1, shared) and 128K bank 4 ---------------------------------------------------

	wire [15:0] mem1A48, mem1A128;
	wire [ 7:0] mem1D48, mem1D128;
	wire        mem1R48, mem1W48, mem1R128, mem1W128;

	reg  [7:0] ram1[0:65535];
	reg  [7:0] ram1Q;
	wire [15:0] ram1A = m128 ? mem1A128 : mem1A48;
	wire [ 7:0] ram1D = m128 ? mem1D128 : mem1D48;
	wire        ram1W = m128 ? mem1W128 : mem1W48;
	always @(posedge clock) begin
		if(ram1W) ram1[ram1A] <= ram1D;
		ram1Q <= ram1[ram1A];
	end

	// TAPE n: the ROM keeps the speed in COARSE / FINE at 629Dh / 629Eh (Jynx, LynxEmulatorGuest.cpp
	// GetLynxTapeSpeedBitsPerSecond; the ROM reads them at 0D6Fh / 0D78h).
	// 128K: its variables are elsewhere, it stays at TAPE 0 here.
	reg [7:0] coarse = 8'd0, fine = 8'd0;
	assign dbg_cf = { coarse, fine };
	wire [15:0] cA = ramM ? 16'h629D : 16'h229D;   // 48K: mem1A = {00, A14, A12-0}
	always @(posedge clock) begin
		if(reset) begin coarse <= 8'd0; fine <= 8'd0; end
		else if(ram1W && !m128) begin
			if(ram1A == cA)        coarse <= ram1D;
			if(ram1A == cA + 1'd1) fine   <= ram1D;
		end
		case({ coarse, fine })
			16'h0101: tape_speed <= 3'd1;   //  900 baud
			16'h0204: tape_speed <= 3'd2;   // 1200
			16'h0202: tape_speed <= 3'd3;   // 1500
			16'h0201: tape_speed <= 3'd4;   // 1800
			16'h0302: tape_speed <= 3'd5;   // 2100
			default:  tape_speed <= 3'd0;   //  600
		endcase
	end

	wire [15:0] mem4A128;
	wire [ 7:0] mem4D128;
	wire        mem4R128, mem4W128;

	reg  [7:0] ram4[0:65535];
	reg  [7:0] ram4Q;
	always @(posedge clock) begin
		if(mem4W128) ram4[mem4A128] <= mem4D128;
		ram4Q <= ram4[mem4A128];
	end

//--- ESC during LOAD ------------------------------------------------------------------------------
// The ROM looks at ESC only between edges of the tape signal; a real cassette always gives it hiss,
// but a silent input (no tape, the end of the image, WAV silence) would leave LOAD waiting for
// ever. While the motor runs and ESC is held, a 2 kHz square wave stands in for the hiss.
	reg [14:0] hiss = 15'd0;
	always @(posedge clock) hiss <= hiss + 1'd1;      // bit 14: 48 MHz / 2^15 = 1.46 kHz
	wire tape_q = esc && motor ? hiss[14] : tape_in;

//--- floppy (WD1793, shared) ---------------------------------------------------------------------

	wire [1:0] fdcA48,  fdcA128;
	wire [7:0] fdcD48,  fdcD128;
	wire       fdcR48,  fdcW48,  fdcSel48,  fdcSide48;
	wire       fdcR128, fdcW128, fdcSel128, fdcSide128;
	wire [7:0] fdcQ;

	wire       fdcSel  = m128 ? fdcSel128  : fdcSel48;
	reg        fdcDisk = 1'b0;
	always @(posedge clock) if(img_mounted) fdcDisk <= |img_size;

	// Disk hint (lynx_tape_status): at mount, sector 0 is read once before the WD1793 gets the SD
	// interface: a CP/M boot disk starts 00 00 18 (JR), a Lynx DOS disk 01. The DOS ROM has run
	// (XROM) when it has been read 256 times (the BASIC ROM's own check at reset reads it 8-12
	// times); a Read Sector command (8xh) means the disk is in use.
	wire [31:0] wd_lba;
	wire        wd_rd, wd_wr;
	reg         peek = 1'b0, peek_rd = 1'b0, peek_ack = 1'b0;
	reg  [7:0]  peek_b0;
	assign sd_lba = peek ? 32'd0 : wd_lba;
	assign sd_rd  = peek ? peek_rd : wd_rd;
	assign sd_wr  = peek ? 1'b0 : wd_wr;
	always @(posedge clock) begin
		peek_ack <= sd_ack;
		if(img_mounted) begin peek <= |img_size; peek_rd <= 1'b0; disk_cpm <= 1'b0; end
		else if(peek) begin
			if(!peek_rd && !peek_ack && !sd_ack) peek_rd <= 1'b1;
			if(sd_ack) peek_rd <= 1'b0;
			if(sd_ack && sd_buff_wr && sd_buff_addr == 9'd0) peek_b0 <= sd_buff_dout;
			if(sd_ack && sd_buff_wr && sd_buff_addr == 9'd2) disk_cpm <= peek_b0 == 8'h00 && sd_buff_dout == 8'h18;
			if(peek_ack && !sd_ack) peek <= 1'b0;
		end
	end

	reg [8:0] dos_cnt = 9'd0;
	wire      dos_rd = m128 ? mem0R128 && mem0A128[15:13] == 3'd7 : mem0R48 && mem0A48[15:13] == 3'd7;
	wire      fdc_cmd = (m128 ? fdcW128 && fdcA128 == 2'd0 : fdcW48 && fdcA48 == 2'd0)
	                    && (m128 ? fdcD128[7:5] : fdcD48[7:5]) == 3'b100;
	always @(posedge clock) begin
		if(reset) begin dos_cnt <= 9'd0; dos_run <= 1'b0; end
		else if(cpu_ce && dos_rd && !dos_run) begin dos_cnt <= dos_cnt + 1'd1; if(&dos_cnt) dos_run <= 1'b1; end
		if(img_mounted || reset) disk_read <= 1'b0;
		else if(fdc_cmd) disk_read <= 1'b1;
	end

	wd1793 #(.EDSK(0), .RWMODE(1)) wd1793
	(
		.clk_sys            (clock                    ),
		.ce                 (m128 ? pe6M0 : pe04M     ),
		.reset              (m128 ? !reset128 : !reset48),
		.io_en              (1'b1                     ),
		.rd                 (m128 ? fdcR128 : fdcR48  ),
		.wr                 (m128 ? fdcW128 : fdcW48  ),
		.addr               (m128 ? fdcA128 : fdcA48  ),
		.din                (m128 ? fdcD128 : fdcD48  ),
		.dout               (fdcQ                     ),
		.drq                (                         ),
		.intrq              (                         ),
		.busy               (fdc_busy                 ),
		.wp                 (img_readonly             ),
		.size_code          (3'd4                     ),
		.layout             (1'b1                     ),
		.side               (m128 ? fdcSide128 : fdcSide48),
		.ready              (fdcSel && fdcDisk        ),
		.img_mounted        (img_mounted              ),
		.img_mounted_overide(1'b0                     ),
		.img_size           (img_size                 ),
		.prepare            (                         ),
		.sd_lba             (wd_lba                   ),
		.sd_rd              (wd_rd                    ),
		.sd_wr              (wd_wr                    ),
		.sd_ack             (sd_ack && !peek          ),
		.sd_buff_addr       (sd_buff_addr             ),
		.sd_buff_dout       (sd_buff_dout             ),
		.sd_buff_din        (sd_buff_din              ),
		.sd_buff_wr         (sd_buff_wr && !peek      ),
		.input_active       (1'b0                     ),
		.input_addr         (20'd0                    ),
		.input_data         (8'd0                     ),
		.input_wr           (1'b0                     ),
		.buff_addr          (                         ),
		.buff_read          (                         ),
		.buff_din           (8'd0                     )
	);

//--- Lynx 48K / 96K ------------------------------------------------------------------------------

	wire [13:0] mem2A1, mem2A2, mem3A1, mem3A2;
	wire [ 7:0] mem2Q1, mem2D2, mem2Q2, mem3Q1, mem3D2, mem3Q2;
	wire        mem2W2, mem3W2;

	vram #(16) vram2(clock, mem2A1, mem2Q1, mem2A2, mem2D2, mem2Q2, mem2W2);
	vram #(16) vram3(clock, mem3A1, mem3Q1, mem3A2, mem3D2, mem3Q2, mem3W2);

	wire       de48, hs48, vs48, r48, g48, b48, motor48;
	wire [5:0] sound48;

	lynx_48k lynx48
	(
		.ramM   (ramM     ),
		.casM   (casM     ),
		.dosM   (ramM     ),   // disk interface on the 96K models (MAME lynx96k); none on the 48K
		.brk    (esc      ),
		.clock  (clock    ),
		.pe06M  (pe06M    ),
		.peM75  (peM75    ),
		.ne04M  (ne04M    ),
		.pe04M  (pe04M    ),
		.reset  (reset48  ),
		.rfsh   (         ),
		.de     (de48     ),
		.motor  (motor48  ),
		.hSync  (hs48     ),
		.vSync  (vs48     ),
		.r      (r48      ),
		.g      (g48      ),
		.b      (b48      ),
		.tape   (tape_q   ),
		.sound  (sound48  ),
		.row    (row48    ),
		.col    (col      ),
		.joy0   (joy0     ),
		.joy1   (joy1     ),
		.mem0A  (mem0A48  ),
		.mem0Q  (rom48Q   ),
		.mem0R  (mem0R48  ),
		.mem1A  (mem1A48  ),
		.mem1D  (mem1D48  ),
		.mem1Q  (ram1Q    ),
		.mem1R  (mem1R48  ),
		.mem1W  (mem1W48  ),
		.mem2A1 (mem2A1   ),
		.mem2Q1 (mem2Q1   ),
		.mem2A2 (mem2A2   ),
		.mem2D2 (mem2D2   ),
		.mem2Q2 (mem2Q2   ),
		.mem2W2 (mem2W2   ),
		.mem3A1 (mem3A1   ),
		.mem3Q1 (mem3Q1   ),
		.mem3A2 (mem3A2   ),
		.mem3D2 (mem3D2   ),
		.mem3Q2 (mem3Q2   ),
		.mem3W2 (mem3W2   ),
		.fdcA   (fdcA48   ),
		.fdcD   (fdcD48   ),
		.fdcQ   (fdcQ     ),
		.fdcR   (fdcR48   ),
		.fdcW   (fdcW48   ),
		.fdcSel (fdcSel48 ),
		.fdcSide(fdcSide48)
	);

//--- Lynx 128K -----------------------------------------------------------------------------------

	wire [15:0] vramA1, vramA2;
	wire [ 7:0] vramQ1, vramD2, vramQ2;
	wire        vramW2;

	vram #(64) vram128(clock, vramA1, vramQ1, vramA2, vramD2, vramQ2, vramW2);

	wire       de128, hs128, vs128, r128, g128, b128, motor128;
	wire [5:0] sound128;

	lynx_128k lynx128
	(
		.clock  (clock     ),
		.pe12M  (pe12M     ),
		.ne6M0  (ne6M0     ),
		.pe6M0  (pe6M0     ),
		.pe1M5  (pe1M5     ),
		.brk    (esc       ),
		.reset  (reset128  ),
		.rfsh   (          ),
		.de     (de128     ),
		.motor  (motor128  ),
		.hsync  (hs128     ),
		.vsync  (vs128     ),
		.r      (r128      ),
		.g      (g128      ),
		.b      (b128      ),
		.tape   (tape_q    ),
		.sound  (sound128  ),
		.row    (row128    ),
		.col    (col       ),
		.joy0   (joy0      ),
		.joy1   (joy1      ),
		.mem0A  (mem0A128  ),
		.mem0Q  (rom128Q   ),
		.mem0R  (mem0R128  ),
		.mem1A  (mem1A128  ),
		.mem1D  (mem1D128  ),
		.mem1Q  (ram1Q     ),
		.mem1R  (mem1R128  ),
		.mem1W  (mem1W128  ),
		.mem2A1 (vramA1    ),
		.mem2Q1 (vramQ1    ),
		.mem2A2 (vramA2    ),
		.mem2D2 (vramD2    ),
		.mem2Q2 (vramQ2    ),
		.mem2W2 (vramW2    ),
		.mem4A  (mem4A128  ),
		.mem4D  (mem4D128  ),
		.mem4Q  (ram4Q     ),
		.mem4R  (mem4R128  ),
		.mem4W  (mem4W128  ),
		.fdcA   (fdcA128   ),
		.fdcD   (fdcD128   ),
		.fdcQ   (fdcQ      ),
		.fdcR   (fdcR128   ),
		.fdcW   (fdcW128   ),
		.fdcSel (fdcSel128 ),
		.fdcSide(fdcSide128)
	);

	assign motor  = m128 ? motor128 : motor48;
	assign cpu_ce = m128 ? pe6M0 : pe04M;
	assign sound = m128 ? sound128 : sound48;
	assign dbg_a = m128 ? mem0A128 : mem0A48;


//--- video out -----------------------------------------------------------------------------------
// From Shaeon's Lynx.sv: video.v shifts each character (8 pixels) out one character after the
// 6845 addresses it, so DE is delayed the same for the horizontal blank; the vertical blank is
// the range of lines that had DE in the previous frame (the ROM programs the 6845).

	wire       cePixel = m128 ? pe12M : pe06M;
	wire       hsync   = m128 ? hs128 : hs48;
	wire       vsync   = m128 ? vs128 : vs48;
	wire       de      = m128 ? de128 : de48;
	wire [2:0] rgb     = m128 ? { r128, g128, b128 } : { r48, g48, b48 };

	reg [7:0] deDly = 8'd0;
	always @(posedge clock) if(cePixel) deDly <= { deDly[6:0], de };
	wire deOut = deDly[7];

	reg      hsP = 1'b0, vsP = 1'b0, lineDe = 1'b0, gotFirst = 1'b0;
	reg[9:0] line = 10'd0, curFirst = 10'd0, curLast = 10'd0, deFirst = 10'd0, deLast = 10'd1023;

	always @(posedge clock) if(cePixel) begin
		hsP <= hsync;
		vsP <= vsync;
		if(deOut) lineDe <= 1'b1;
		if(hsync && !hsP) begin
			if(lineDe) begin
				if(!gotFirst) begin curFirst <= line; gotFirst <= 1'b1; end
				curLast <= line;
			end
			lineDe <= 1'b0;
			if(line != 10'h3FF) line <= line + 1'd1;
		end
		if(vsync && !vsP) begin
			deFirst  <= curFirst;
			deLast   <= curLast;
			gotFirst <= 1'b0;
			line     <= 10'd0;
		end
	end

	wire vblank = line < deFirst || line > deLast;

	always @(posedge clock) begin
		ce_pix <= cePixel;
		if(cePixel) begin
			HSync  <= hsync;
			VSync  <= vsync;
			HBlank <= !deOut;
			VBlank <= vblank;
			{ R, G, B } <= rgb;
		end
	end

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
