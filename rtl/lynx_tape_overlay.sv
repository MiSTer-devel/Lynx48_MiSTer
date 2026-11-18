// lynx_tape_overlay.sv - tape status bar and next-step hint over the picture (OSD "Tape overlay"),
// after the MiSTer tape standard (~/dev2/tape-standard.md rules 19-28). Structure from the SVI-328
// core's rtl/tape_overlay.sv, itself from the Basic Master Jr and Sharp X1 cores (GPL-2.0).
//
// While the deck plays (the motor relay is on), the bottom-left corner shows
//
//     TAPE > 0:09/ 2:24 x4
//     [=========---------]
//
// elapsed / total time at the real tape speed, the turbo factor while turbo is on and a 64-step
// progress bar. While the deck is stopped it shows what to type next, read from the TAP itself:
//
//     tape at (or just before) a named file      TYPE LOAD "SNAKE"<ret>   (B file)
//                                                TYPE MLOAD "OH MUMMY"<ret> (M file)
//     a BASIC file has just been loaded          TYPE RUN<ret>, until Return is pressed
//     anywhere else, or an A file (Level 9)      nothing
//
// The Lynx has no wildcard load (MAME camplynx.cpp: "there's no wildcard; you must specify the
// name"), and on about 40 % of the tapes the name to type differs from the file name, which is
// what the hint is for. Names are shown exactly as on the tape (case matters). Text is drawn with
// the Lynx's own font (rtl/lynx_font.vh, from the 48K ROM). Only for TAP images: a TZX shows the
// status bar without times.
//
// Times: lynx_tap plays every byte as 8 bits of Jynx's TAPE 0 lengths in 4 MHz cycles
// (0: 080Ch + 0863h, 1: 0FB1h + 10D2h, the last bit's high 092Bh / 11A8h); a named file is
// sync + '"' name '"' + 1F1h high + sync + body, an A file sync + body, sync = 768 x 00 + 15h
// high + A5. lynx_tape_status adds this up while the image downloads, so the total is exact for
// what the player sends; the 128K plays it twice as fast. Elapsed time counts clk_sys cycles
// while the tape moves, 4 per cycle in turbo.

`define TH_RETURN 8'h01
`define TH_PLAY   8'h03

module lynx_tape_status #(
	parameter int NF    = 8,             // files in the hint table
	parameter int NAME  = 14,            // longest name the hint shows
	parameter int CHARS = 28             // hint text width
)(
	input  logic         clk,             // clk_sys, 48 MHz
	input  logic         dl_start,        // a new image starts downloading
	input  logic         dl_wr,           // image byte written (sequential addresses from 0)
	input  logic   [7:0] dl_data,
	input  logic         dl_busy,
	input  logic         is_tap,          // the image is a Lynx TAP (not a TZX or WAV)
	input  logic         wav,             // a WAV header was read: total = data length / byte rate
	input  logic  [31:0] wav_rate,        // samples per second
	input  logic  [31:0] wav_len,         // data bytes
	input  logic   [2:0] wav_align,       // bytes per frame
	input  logic         loaded,          // a tape is mounted
	input  logic         m128,
	input  logic   [2:0] speed,           // lynx_tap speed_used: TAPE n (total time scales with it)
	input  logic         playing,         // motor relay on
	input  logic         moving,          // the tape is playing (motor on, not at the end)
	input  logic         fast,            // turbo active
	input  logic  [24:0] position,        // lynx_tap pos (0 after mount / rewind)
	input  logic  [24:0] length,
	input  logic         in_file,         // lynx_tap: between a file's first sync and its end
	input  logic   [7:0] file_type,       // lynx_tap: type letter of that file
	input  logic  [10:0] ps2_key,
	// disk hint (lynx_core): shown while no tape hint is
	input  logic         disk_loaded,     // a disk image is mounted
	input  logic         disk_iface,      // the model has the disk interface (96K, 128K)
	input  logic         disk_cpm,        // CP/M boot disk
	input  logic         dos_run,         // XROM has run
	input  logic         disk_read,       // the disk has been read (EXT DIR / EXT BOOT done)
	// to the video clock
	output logic [CHARS*8+48:0] status,  // held while req != ack
	output logic         req,
	input  logic         ack
);
	localparam int W = CHARS*8+49;   // {hint_show, hint_len[4:0], hint_text, loaded, playing, fast, is_tap, fill[6:0], elapsed, total}

	// ---- the image as lynx_tap will play it (TapFileLexer on the download stream) ----
	typedef enum logic [2:0] { P_START, P_NAME, P_BODY, P_BAD } pst_t;
	pst_t        pst;
	logic [24:0] a;                      // download address of the byte being parsed
	logic  [3:0] nf;                     // files found
	logic [24:0] f_start[NF], f_end[NF];
	logic  [7:0] f_type[NF];
	logic  [7:0] f_name[NF][NAME];
	logic  [4:0] f_len[NF];
	logic        f_ok[NF];               // name fits and the type is B or M
	logic        f_auto[NF];             // B saved with a line number: runs by itself after LOAD
	logic  [4:0] nlen;
	logic        named;
	logic  [2:0] bidx;
	logic [17:0] bleft;
	logic  [7:0] blo, btype;
	logic [35:0] cyc;                    // 4 MHz cycles of the whole tape
	logic        computing, was_busy;
	logic  [2:0] speed_d;
	logic        wav_d;
	wire  [31:0] wav_bps = wav_rate * {29'd0, wav_align};   // bytes per second
	logic        m128_d;
	// cycles of one second of tape: 4 MHz (48K) or 8 MHz (128K) x baud / 600
	wire  [35:0] sec_cyc = (m128 ? 36'd8000000 : 36'd4000000) * (36'd2 + 36'(speed)) / 36'd2;
	logic [35:0] rem;
	logic [15:0] total, elapsed;         // BCD m1 m0 s1 s0
	logic [25:0] efrac;
	logic [24:0] last_pos, thresh;
	logic  [6:0] fill;
	wire  [24:0] step_bytes = length[24:6] == 0 ? 25'd1 : {6'd0, length[24:6]};

	localparam logic [35:0] SYNC_CYC = 36'd768 * 36'd33856 + 36'h15 + 36'd52190; // 768 x 00, high, A5
	function automatic logic [16:0] byte_cyc(input logic [7:0] d);
		logic [3:0] ones;
		ones = 0;
		for (int i = 0; i < 8; i++) ones = ones + {3'd0, d[i]};
		// 8 x (080Ch + 0863h) + ones x (0FB1h + 10D2h - 080Ch - 0863h) + the last bit's longer high
		return 17'd33656 + 17'(ones) * 17'd4116 + (d[0] ? 17'd214 : 17'd200);
	endfunction

	function automatic logic [15:0] bcd_tick(input logic [15:0] t);
		logic [15:0] n;
		n = t;
		if (t == 16'h9959) return t;
		if (t[3:0] != 4'd9) n[3:0] = t[3:0] + 4'd1;
		else begin
			n[3:0] = 0;
			if (t[7:4] != 4'd5) n[7:4] = t[7:4] + 4'd1;
			else begin
				n[7:4] = 0;
				if (t[11:8] != 4'd9) n[11:8] = t[11:8] + 4'd1;
				else begin n[11:8] = 0; n[15:12] = t[15:12] + 4'd1; end
			end
		end
		return n;
	endfunction

	// ---- hint state ----
	logic        run_pending;            // a BASIC file has been loaded: RUN
	logic        in_file_d;
	logic  [7:0] ftype_d;
	logic [10:0] old_key;
	logic [23:0] stop_cnt;               // the deck has been stopped this long (debounce)
	wire         stopped = stop_cnt[23];  // ~0.17 s

	// a BASIC file just finished: the ROM stops the motor at (or a byte or two before) its end
	logic        near_b_end;
	always_comb begin
		near_b_end = 0;
		for (int i = 0; i < NF; i++)
			if (4'(i) < nf && f_type[i] == "B" && !f_auto[i] && position > f_start[i] && position + 25'd4 >= f_end[i]
			    && position <= f_end[i])
				near_b_end = 1;
	end
	logic playing_d;

	// file the tape is at: prev_end <= position <= start
	logic        at_file;
	logic  [3:0] at_idx;
	always_comb begin
		at_file = 0; at_idx = 0;
		for (int i = NF - 1; i >= 0; i--)
			if (4'(i) < nf && position <= f_start[i] && (i == 0 || position >= f_end[i == 0 ? 0 : i - 1])) begin
				at_file = 1; at_idx = 4'(i);
			end
	end

	// hint text
	logic        hint_show;
	logic  [4:0] hint_len;
	logic [CHARS*8-1:0] hint_text;
	always_comb begin
		logic [7:0] t[CHARS];
		logic [4:0] n;
		for (int i = 0; i < CHARS; i++) t[i] = " ";
		t[0] = "T"; t[1] = "Y"; t[2] = "P"; t[3] = "E";
		n = 5'd5;
		hint_show = 0;
		if (is_tap && loaded && stopped && run_pending) begin
			t[5] = "R"; t[6] = "U"; t[7] = "N"; t[8] = `TH_RETURN; n = 5'd9; hint_show = 1;
		end
		else if (is_tap && loaded && stopped && at_file && f_ok[at_idx]) begin
			if (f_type[at_idx] == "M") begin t[n] = "M"; n = n + 1'd1; end
			t[n] = "L"; t[n+1] = "O"; t[n+2] = "A"; t[n+3] = "D"; t[n+4] = " "; t[n+5] = 8'h22;
			n = n + 5'd6;
			for (int j = 0; j < NAME; j++)
				if (5'(j) < f_len[at_idx]) begin t[n] = f_name[at_idx][j]; n = n + 1'd1; end
			t[n] = 8'h22; t[n+1] = `TH_RETURN; n = n + 5'd2;
			hint_show = 1;
		end
		if (!hint_show && disk_loaded && !disk_read && !(loaded && playing)) begin
			hint_show = 1;
			if (!disk_iface) begin       // "DISK: MODEL 96K / 128K"
				t[0] = "D"; t[1] = "I"; t[2] = "S"; t[3] = "K"; t[4] = ":"; t[5] = " ";
				t[6] = "M"; t[7] = "O"; t[8] = "D"; t[9] = "E"; t[10] = "L"; t[11] = " ";
				t[12] = "9"; t[13] = "6"; t[14] = "K"; t[15] = " "; t[16] = "/"; t[17] = " ";
				t[18] = "1"; t[19] = "2"; t[20] = "8"; t[21] = "K"; n = 5'd22;
			end
			else if (!dos_run) begin
				t[5] = "X"; t[6] = "R"; t[7] = "O"; t[8] = "M"; t[9] = `TH_RETURN; n = 5'd10;
			end
			else begin
				t[5] = "E"; t[6] = "X"; t[7] = "T"; t[8] = " ";
				if (disk_cpm) begin t[9] = "B"; t[10] = "O"; t[11] = "O"; t[12] = "T"; t[13] = `TH_RETURN; n = 5'd14; end
				else          begin t[9] = "D"; t[10] = "I"; t[11] = "R"; t[12] = `TH_RETURN; n = 5'd13; end
			end
		end
		hint_len = n;
		for (int i = 0; i < CHARS; i++) hint_text[(CHARS-1-i)*8 +: 8] = t[i];
	end

	wire [W-1:0] pack = {hint_show, hint_len, hint_text, loaded, playing, fast, is_tap || wav, fill, elapsed > total && total != 0 ? total : elapsed, total};  // BCD compares as a number
	logic [1:0] ack_sync;

	initial begin
		pst = P_START; nf = 0; cyc = 0; total = 0; elapsed = 0; efrac = 0; computing = 0;
		was_busy = 0; req = 0; status = 0; ack_sync = 0; run_pending = 0; stop_cnt = 0;
		last_pos = 0; thresh = 0; fill = 0; in_file_d = 0; old_key = 0;
	end

	always_ff @(posedge clk) begin
		ack_sync <= {ack_sync[0], ack};

		// ---- parse the download ----
		was_busy <= dl_busy;
		if (dl_start) begin
			pst <= P_START; a <= 0; nf <= 0; cyc <= 0; total <= 0; computing <= 0;
		end
		else if (dl_wr) begin
			a <= a + 1'd1;
			case (pst)
				P_START:
					if (dl_data == 8'h22) begin
						if (nf != NF) begin f_start[nf] <= a; f_len[nf] <= 0; f_ok[nf] <= 1; f_auto[nf] <= 0; end
						named <= 1; nlen <= 0; pst <= P_NAME;
						cyc <= cyc + SYNC_CYC + {19'd0, byte_cyc(dl_data)};
					end
					else if (dl_data == "A") begin
						if (nf != NF) begin f_start[nf] <= a; f_len[nf] <= 0; f_ok[nf] <= 0; f_type[nf] <= "A"; end
						named <= 0; bidx <= 3'd1; bleft <= 18'd4; btype <= "A"; pst <= P_BODY;
						cyc <= cyc + SYNC_CYC + {19'd0, byte_cyc(dl_data)};
					end
					else if (dl_data != 8'hA5 && dl_data != 8'h00) begin pst <= P_BAD; cyc <= cyc + {19'd0, byte_cyc(dl_data)}; end
				P_NAME: begin
					cyc <= cyc + {19'd0, byte_cyc(dl_data)};
					if (dl_data == 8'h22) begin
						// closing quote, 1F1h high, second sync; the body starts with the next byte
						cyc <= cyc + {19'd0, byte_cyc(dl_data)} + 36'h1F1 + SYNC_CYC;
						bidx <= 3'd0; bleft <= 18'd3; pst <= P_BODY;
					end
					else begin
						if (nf != NF) begin
							if (nlen < 5'(NAME)) begin f_name[nf][nlen] <= dl_data; f_len[nf] <= nlen + 1'd1; end
							else f_ok[nf] <= 0;
						end
						nlen <= nlen + (nlen != 5'd31 ? 1'd1 : 1'd0);
					end
				end
				P_BODY: if (!(named && bidx == 3'd0 && dl_data == 8'hA5)) begin   // A5 after the name: lynx_tap skips it
					cyc <= cyc + {19'd0, byte_cyc(dl_data)};
					if (bidx != 3'd7) bidx <= bidx + 1'd1;
					if (bidx == 3'd0) begin
						btype <= dl_data;
						if (nf != NF) begin
							f_type[nf] <= dl_data;
							if (dl_data != "B" && dl_data != "M") f_ok[nf] <= 0;
						end
					end
					if (named ? bidx == 3'd1 : bidx == 3'd3) blo <= dl_data;
					if (named ? bidx == 3'd2 : bidx == 3'd4)
						bleft <= {2'b00, dl_data, blo} + (btype == "B" ? 18'd3 : btype == "M" ? 18'd7 : 18'd12);
					else if (bleft == 18'd1) begin
						if (nf != NF) begin f_end[nf] <= a + 1'd1; nf <= nf + 1'd1; end
						pst <= P_START;
					end
					else begin
						bleft <= bleft - 1'd1;
						// a B file ends with 3 bytes: 00 00 00, or (non-zero) when it was saved to
						// run itself (library sweep: those all autorun, the 00 ones stop at ">")
						if (btype == "B" && bidx > 3'd2 && (bleft == 18'd3 || bleft == 18'd2) && dl_data != 8'h00 && nf != NF)
							f_auto[nf] <= 1;
					end
				end
				default: cyc <= cyc + {19'd0, byte_cyc(dl_data)};   // P_BAD: lynx_tap plays the rest raw
			endcase
		end
		else if (wav && !wav_d) begin
			// WAV: frames of data / sample rate; the frame size comes from the length per frame
			rem <= {4'd0, wav_len}; total <= 0; computing <= 1;
		end
		else if (!wav && ((was_busy && !dl_busy) || speed != speed_d || m128 != m128_d)) begin
			// cycles -> seconds at the speed the tape plays (128K twice as fast, TAPE n x baud / 600;
			// the fixed parts of each bit don't scale, so TAPE 1-5 totals are a few % long)
			rem <= cyc; total <= 0; computing <= 1;
		end
		else if (computing) begin
			if (rem >= (wav ? {4'd0, wav_bps} : sec_cyc)) begin rem <= rem - (wav ? {4'd0, wav_bps} : sec_cyc); total <= bcd_tick(total); end
			else computing <= 0;
		end
		speed_d <= speed; m128_d <= m128; wav_d <= wav;

		// ---- elapsed time: clk_sys cycles while the tape moves, x4 in turbo ----
		last_pos <= position;
		if (dl_start || position < last_pos) begin elapsed <= 0; efrac <= 0; end
		else if (moving) begin
			if (efrac + (fast ? 26'd4 : 26'd1) >= 26'd48000000) begin
				efrac <= efrac + (fast ? 26'd4 : 26'd1) - 26'd48000000; elapsed <= bcd_tick(elapsed);
			end
			else efrac <= efrac + (fast ? 26'd4 : 26'd1);
		end

		// ---- fill: 64 steps of length / 64 bytes ----
		if (dl_start || position < last_pos || thresh == 0) begin fill <= 0; thresh <= step_bytes; end
		else if (position >= thresh && fill != 7'd64) begin fill <= fill + 7'd1; thresh <= thresh + step_bytes; end

		// ---- RUN after a BASIC file; cleared by Return, a rewind or a new tape ----
		in_file_d <= in_file; ftype_d <= file_type;
		old_key <= ps2_key;
		playing_d <= playing;
		if (dl_start || position < last_pos) run_pending <= 0;
		// the ROM stops the motor just before the end of a file it loaded; a tape that ran to its end
		// (a LOAD with the wrong name) loaded nothing
		else if (in_file_d && !in_file && ftype_d == "B" && near_b_end && position < length) run_pending <= 1;
		else if (playing_d && !playing && near_b_end && position < length) run_pending <= 1;
		else if (playing) run_pending <= 0;
		else if (ps2_key[10] != old_key[10] && ps2_key[9] && ps2_key[7:0] == 8'h5A) run_pending <= 0;

		if (playing) stop_cnt <= 0;
		else if (!stop_cnt[23]) stop_cnt <= stop_cnt + 1'd1;

		// ---- hand a changed status to the video clock ----
		if (req == ack_sync[1] && pack != status) begin status <= pack; req <= !req; end
	end
endmodule

module lynx_tape_overlay #(
	parameter logic [3:0] FACTOR = 4'd4,     // shown as "x4" while turbo is on
	parameter int CHARS = 28
)(
	input  logic         clk,              // video clock
	input  logic         ce_pix,
	input  logic         hblank, vblank,
	input  logic         enable,           // OSD Tape overlay: On
	input  logic [CHARS*8+48:0] status,
	input  logic         req,
	output logic         ack,
	input  logic  [23:0] rgb_in,
	output logic  [23:0] rgb_out
);
	localparam int BAR = 21;               // status bar characters
	logic [1:0]  req_sync;
	logic [CHARS*8+48:0] shown;
	logic [10:0] x, width;
	logic [9:0]  y, height;
	logic        line_active, old_hblank, old_vblank;
	// character column / pixel of the current pixel, stepped with x (no divide by 6 in the path)
	wire         sx;                     // doubled horizontally on the 128K's 512-pixel lines
	logic signed [11:0] dxc;             // x - x0
	logic  [4:0] colc;
	logic  [2:0] pxc;

	initial begin
		req_sync = 0; ack = 0; shown = 0; x = 0; y = 0; width = 0; height = 0;
		line_active = 0; old_hblank = 0; old_vblank = 0; dxc = -12'sd4; colc = 0; pxc = 0;
	end

	assign sx = width >= 11'd512;
	wire signed [11:0] ndx = dxc + 12'sd1;
	wire signed [11:0] nlx = sx ? (ndx >>> 1) : ndx;


	// measure the active picture every frame (256 or 512 x 252)
	always_ff @(posedge clk) begin
		req_sync <= {req_sync[0], req};
		if (req_sync[1] != ack) begin shown <= status; ack <= req_sync[1]; end
		if (ce_pix) begin
			old_hblank <= hblank; old_vblank <= vblank;
			if (!hblank && !vblank) begin
				x <= x + 11'd1; line_active <= 1;
				dxc <= ndx;
				if (!sx || !ndx[0]) begin                  // the logical x moves on
					if (nlx == 12'sd2) begin colc <= 0; pxc <= 0; end
					else if (nlx > 12'sd2) begin
						if (pxc == 3'd5) begin pxc <= 0; colc <= colc + 1'd1; end
						else pxc <= pxc + 1'd1;
					end
				end
			end
			if (hblank && !old_hblank) begin
				if (line_active) begin width <= x; y <= y + 10'd1; end
				x <= 0; line_active <= 0; dxc <= -12'sd4; colc <= 0; pxc <= 0;
			end
			if (vblank && !old_vblank) begin height <= y; y <= 0; end
		end
	end

	wire                 hint_show = shown[CHARS*8+48];
	wire [4:0]           hint_len  = shown[CHARS*8+47:CHARS*8+43];
	wire [CHARS*8-1:0]   hint_text = shown[CHARS*8+42:43];
	wire                 tape_bar  = enable && shown[42] && shown[41];    // loaded, playing
	wire                 hint      = enable && hint_show && !tape_bar;
	wire                 visible   = tape_bar || hint;
	wire                 fast      = shown[40];
	wire                 times     = shown[39];                           // a TAP: times known
	wire [6:0]           fill      = shown[38:32];
	wire [15:0]          elapsed_t = shown[31:16];
	wire [15:0]          total_t   = shown[15:0];

	// Lynx characters are 6 x 10
	wire [4:0]   chars = tape_bar ? 5'(BAR) : hint_len;
	wire [10:0]  box_w = 11'(chars) * 11'd6 + 11'd4;
	wire [9:0]   box_h = tape_bar ? 10'd20 : 10'd14;
	wire [10:0]  x0 = 11'd4;
	wire [9:0]   y0 = height - box_h - 10'd4;
	wire [10:0]  dx = x - x0;
	wire [9:0]   dy = y - y0;
	wire [10:0]  lx = sx ? {1'b0, dx[10:1]} : dx;
	wire [9:0]   ly = dy;
	wire         in_box = x >= x0 && y >= y0 && lx < box_w && ly < box_h;

	wire [10:0]  tx = lx - 11'd2;
	wire [9:0]   ty = ly - 10'd2;
	wire [4:0]   col = colc;
	wire [2:0]   px  = pxc;

	`include "lynx_font.vh"

	function automatic logic [7:0] digit(input logic [3:0] d, input logic blank_zero);
		return blank_zero && d == 0 ? 8'h20 : 8'h30 + {4'd0, d};
	endfunction

	logic [7:0] ch;
	always_comb begin
		if (!tape_bar) ch = hint_text[(CHARS*8-1) - 8*col -: 8];
		else case (col)
			5'd0: ch = "T";  5'd1: ch = "A";  5'd2: ch = "P";  5'd3: ch = "E";
			5'd5: ch = `TH_PLAY;
			5'd7: ch = times ? digit(elapsed_t[15:12], 1'b1) : " ";
			5'd8: ch = times ? digit(elapsed_t[11:8], 1'b0) : " ";
			5'd9: ch = times ? ":" : " ";
			5'd10: ch = times ? digit(elapsed_t[7:4], 1'b0) : " ";
			5'd11: ch = times ? digit(elapsed_t[3:0], 1'b0) : " ";
			5'd12: ch = times ? "/" : " ";
			5'd13: ch = times ? digit(total_t[15:12], 1'b1) : " ";
			5'd14: ch = times ? digit(total_t[11:8], 1'b0) : " ";
			5'd15: ch = times ? ":" : " ";
			5'd16: ch = times ? digit(total_t[7:4], 1'b0) : " ";
			5'd17: ch = times ? digit(total_t[3:0], 1'b0) : " ";
			5'd19: ch = fast ? "x" : " ";
			5'd20: ch = fast ? digit(FACTOR, 1'b0) : " ";
			default: ch = " ";
		endcase
	end

	function automatic logic [4:0] glyph(input logic [7:0] c, input logic [3:0] r);
		logic [49:0] g;
		if (c == `TH_RETURN) begin g = 50'b00000_00001_00001_00001_01001_11111_01000_00000_00000_00000; return g[49 - 5*r -: 5]; end
		if (c == `TH_PLAY)   begin g = 50'b00000_01000_01100_01110_01111_01110_01100_01000_00000_00000; return g[49 - 5*r -: 5]; end
		if (c >= 8'h20 && c < 8'h80) return lynx_font(c[6:0], r);
		return 5'd0;
	endfunction

	wire [4:0] glyph_row = glyph(ch, ty[3:0]);
	wire text_on = ty < 10'd10 && tx < 11'(chars) * 11'd6 && px != 3'd5 && glyph_row[3'd4 - px];
	// progress bar at ly 14..17, 128 px for 64 steps
	wire bar_area = tape_bar && ly >= 10'd14 && ly < 10'd18 && lx >= 11'd2 && lx < 11'd130;
	wire bar_on   = bar_area && (lx - 11'd2) < {3'd0, fill, 1'b0};

	always_comb begin
		rgb_out = rgb_in;
		if (visible && in_box)
			rgb_out = text_on ? 24'hFFFFFF : bar_on ? 24'h44CC44 : bar_area ? 24'h333333 : 24'h000000;
	end
endmodule
