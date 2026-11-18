//-------------------------------------------------------------------------------------------------
// Lynx .TAP player: plays a TAP image as the tape signal the Lynx ROM reads (port 80h d0 / 128K
// port 82h d2), so LOAD / MLOAD and every custom loader work as with a real tape.
//
// The TAP holds the bytes the ROM reads, without the leader and sync. This module puts them back
// as Jynx does (refs/emulators/jonathan-markland_Jynx/Portable/TapFileSplitter.cpp,
// SignalWriter.cpp), file by file:
//   named file ("NAME" then B or M):  sync, '"' NAME '"', 0x1F1 cycles high, sync, body
//   A file (Level 9 data, no name):    sync, body
//   sync = 768 zero bytes, 0x15 cycles high, A5
// TAP grammar (TapFileLexer): an optional A5, then "NAME" or nothing (A files), then the body:
//   B: 'B' len16 data[len] + 3 bytes   M: 'M' len16 data[len] + 7 bytes   A: 'A' load16 len16 + 12
// then any number of 00 bytes before the next file. A block that doesn't start with A5, '"' or 'A'
// (Mazeman's second part, its own leader and data) and everything after it is played as plain
// bytes, as they would be on the tape.
// Bits MSB first, each bit a low then a high phase, no start / stop bits. Lengths in 4 MHz Z80
// cycles at TAPE 0 (600 baud), from SignalWriter:
//   0: low 080Ch, high 0863h (092Bh after bit 0)    1: low 0FB1h, high 10D2h (11A8h after bit 0)
// Output level = the phase (low 0, high 1), as Jynx returns it in bit 0.
//
// Timebase: the CPU clock enable (cpu_ce), so turbo speeds the tape up with the CPU. 48K / 96K:
// one 4 MHz cycle per enable. 128K: the ROM reads tapes twice as fast (MAME camplynx_cas.cpp:
// 8000 Hz instead of 4000 Hz) and the CPU runs at 6 MHz, so one enable is 4/3 of a 48K cycle.
// Durations count in thirds of a 48K cycle: +3 per enable (48K), +4 (128K).
// The tape only moves while play (the motor relay) is on; it pauses where it is when it stops.
// TAPE n: Jynx's lengths scaled by 600 / baud (TapFileSplitter::GenerateWaveformForFile): a 0 is
// low Z, high Z+57h (Z+11Fh after bit 0), a 1 low O, high O+121h (O+1F7h); Z = 80Ch * 600 / baud,
// O = FB1h * 600 / baud. The speed is taken when the motor starts, as Jynx does per file.
//
// Bytes come from the image through a request / acknowledge port (DDR3 on MiSTer, an array in
// the sim): rd_addr is held while rd_req is high, the source answers rd_ack with rd_data.
//-------------------------------------------------------------------------------------------------
module lynx_tap
(
	input  wire        clock,
	input  wire        rewind,         // back to the start (mount, Rewind tape)
	input  wire        cpu_ce,
	input  wire        m128,
	input  wire        play,           // motor relay on
	input  wire [ 2:0] speed,          // BASIC TAPE n (0-5), read at each motor-on
	input  wire [24:0] size,           // image length in bytes, 0 = no tape

	output reg  [24:0] rd_addr,
	output reg         rd_req,
	input  wire        rd_ack,
	input  wire [ 7:0] rd_data,

	output reg         tape,           // the signal
	output wire        running,        // playing and not at the end
	output wire        eot,            // played past the last file
	output reg  [24:0] pos,            // next byte of the image to play
	output reg  [ 7:0] file_type,      // type letter of the file playing (B, M, A)
	output reg         in_file,        // between the first sync and the end of a body
	output wire [ 2:0] speed_used      // the TAPE n the tape is playing at
);

	localparam [3:0]
		S_START = 4'd0,   // read the byte at pos: A5 / '"' / 'A'
		S_SYNC  = 4'd1,   // 768 zero bytes, high 0x15, A5
		S_NAME  = 4'd2,   // '"' NAME '"' from the image
		S_GAP   = 4'd3,   // high 0x1F1
		S_BODY  = 4'd4,   // type letter .. end of body from the image
		S_ZEROS = 4'd5,   // skip trailing 00
		S_END   = 4'd6,
		S_RAW   = 4'd7;   // the rest of the image as plain bytes (custom loaders)

	reg  [3:0] st = S_END;
	reg  [3:0] after_sync;
	reg  [9:0] zcount;                  // leader bytes left
	reg  [1:0] sync_step;               // 0 leader, 1 extra high, 2 A5
	reg        named;                   // the file has a name (two syncs)
	reg        name_quote;              // seen the closing quote of the name
	reg [17:0] body_left;               // body bytes left to play
	reg  [2:0] body_idx;                // bytes of the body played so far (up to 5)
	reg  [7:0] len_lo;

	// byte fetch: one byte buffered at pos
	reg        have = 1'b0;
	reg  [7:0] cur;
	wire       at_end = pos >= size;

	// bit emitter
	reg  [7:0] sh;                      // byte being sent
	reg  [3:0] bitn;                    // bits left in it (0 = idle)
	reg        phase;                   // 0 low, 1 high
	reg [16:0] remain;                  // thirds of a 48K cycle left in this phase
	reg        busy = 1'b0;             // emitter has a byte or a high pulse running

	assign eot     = st == S_END;
	assign running = play && !eot;

	wire [2:0] step = m128 ? 3'd4 : 3'd3;
	wire       done = remain <= step;

	function [16:0] x3(input [12:0] c); x3 = { c, 1'b0 } + c; endfunction

	// bit lengths for TAPE 0-5 (600, 900, 1200, 1500, 1800, 2100 baud)
	reg  [2:0] spd = 3'd0;
	assign speed_used = spd;
	reg        play_d = 1'b0;
	always @(posedge clock) begin play_d <= play; if(play && !play_d) spd <= speed > 3'd5 ? 3'd0 : speed; end
	reg [12:0] zs, os;
	always @* case(spd)
		3'd1: begin zs = 13'd1373; os = 13'd2678; end
		3'd2: begin zs = 13'd1030; os = 13'd2008; end
		3'd3: begin zs = 13'd824;  os = 13'd1606; end
		3'd4: begin zs = 13'd686;  os = 13'd1339; end
		3'd5: begin zs = 13'd588;  os = 13'd1147; end
		default: begin zs = 13'h080C; os = 13'h0FB1; end
	endcase

	// next phase length of the current byte (bit 7 first)
	wire       b      = sh[7];
	wire       lastb  = bitn == 4'd1;
	wire [12:0] highc = b ? os + (lastb ? 13'h1F7 : 13'h121) : zs + (lastb ? 13'h11F : 13'h057);

	// start a byte or a high pulse (from the state machine)
	reg        go_byte, go_high;
	reg  [7:0] go_val;
	reg [12:0] go_cyc;

	always @(posedge clock) begin
		// fetch the byte at pos when it isn't buffered
		if(!have && !rd_req && !at_end) begin rd_addr <= pos; rd_req <= 1'b1; end
		if(rd_req && rd_ack) begin rd_req <= 1'b0; cur <= rd_data; have <= 1'b1; end

		go_byte = 1'b0; go_high = 1'b0;

		if(rewind) begin
			st <= size != 0 ? S_START : S_END;
			pos <= 25'd0; have <= 1'b0; rd_req <= 1'b0;
			busy <= 1'b0; bitn <= 4'd0; tape <= 1'b0; in_file <= 1'b0; file_type <= 8'd0;
		end
		else begin
			// emitter: advance on the CPU enable while the motor runs
			if(busy && play && cpu_ce) begin
				if(!done) remain <= remain - step;
				else if(bitn == 4'd0) begin busy <= 1'b0; tape <= 1'b0; end        // high pulse over
				else if(!phase) begin phase <= 1'b1; tape <= 1'b1; remain <= x3(highc) - (step - remain); end
				else if(!lastb) begin
					sh <= { sh[6:0], 1'b0 }; bitn <= bitn - 1'd1;
					phase <= 1'b0; tape <= 1'b0;
					remain <= x3(sh[6] ? os : zs) - (step - remain);
				end
				else begin bitn <= 4'd0; busy <= 1'b0; tape <= 1'b0; end         // byte over
			end

			// sequencer: queue the next byte / pulse when the emitter is free
			if(!busy) case(st)
				S_START:
					if(at_end) begin st <= S_END; in_file <= 1'b0; end
					else if(have) begin
						if(cur == 8'hA5) begin pos <= pos + 1'd1; have <= 1'b0; end  // spurious A5
						else if(cur == 8'h22) begin
							named <= 1'b1; name_quote <= 1'b0; in_file <= 1'b1;
							st <= S_SYNC; after_sync <= S_NAME; zcount <= 10'd768; sync_step <= 2'd0;
						end
						else if(cur == "A") begin
							named <= 1'b0; in_file <= 1'b1;
							st <= S_SYNC; after_sync <= S_BODY; zcount <= 10'd768; sync_step <= 2'd0;
							body_idx <= 3'd0; body_left <= 18'd5;
						end
						else begin st <= S_RAW; in_file <= 1'b0; end  // not the TAP grammar: raw bytes
					end
				S_SYNC:
					case(sync_step)
						2'd0: begin go_byte = 1'b1; go_val = 8'h00; zcount <= zcount - 1'd1; if(zcount == 10'd1) sync_step <= 2'd1; end
						2'd1: begin go_high = 1'b1; go_cyc = 13'h0015; sync_step <= 2'd2; end
						default: begin
							go_byte = 1'b1; go_val = 8'hA5; st <= after_sync;
							if(after_sync == S_BODY) begin body_idx <= 3'd0; body_left <= named ? 18'd3 : 18'd5; end
						end
					endcase
				S_NAME:                              // '"' name '"' from the image
					if(have) begin
						go_byte = 1'b1; go_val = cur; pos <= pos + 1'd1; have <= 1'b0;
						if(cur == 8'h22 && name_quote) st <= S_GAP;
						name_quote <= 1'b1;          // the first quote opens the name
					end
					else if(at_end) st <= S_END;
				S_GAP: begin
					go_high = 1'b1; go_cyc = 13'h01F1;
					st <= S_SYNC; after_sync <= S_BODY; zcount <= 10'd768; sync_step <= 2'd0;
				end
				S_BODY:
					// an A5 between the name and the type letter (some dumps, e.g. 3D City, Compass):
					// the second sync's own A5 saved into the file; the sync has just sent one
					if(have && named && body_idx == 3'd0 && cur == 8'hA5) begin pos <= pos + 1'd1; have <= 1'b0; end
					else if(have) begin
						go_byte = 1'b1; go_val = cur; pos <= pos + 1'd1; have <= 1'b0;
						if(body_idx != 3'd7) body_idx <= body_idx + 1'd1;
						if(body_idx == 3'd0) file_type <= cur;
						// length: bytes 1-2 (B, M) or 3-4 (A); body = header + len + tail
						if(named ? body_idx == 3'd1 : body_idx == 3'd3) len_lo <= cur;
						if(named ? body_idx == 3'd2 : body_idx == 3'd4)
							body_left <= { 2'b00, cur, len_lo } + (file_type == "B" ? 18'd3 : file_type == "M" ? 18'd7 : 18'd12);
						else if(body_left == 18'd1) begin st <= S_ZEROS; in_file <= 1'b0; end
						else body_left <= body_left - 1'd1;
					end
					else if(at_end) begin st <= S_END; in_file <= 1'b0; end
				S_RAW:                               // e.g. Mazeman: 40h, its own 765-byte leader, data
					if(at_end) st <= S_END;
					else if(have) begin go_byte = 1'b1; go_val = cur; pos <= pos + 1'd1; have <= 1'b0; end
				S_ZEROS:
					if(at_end) st <= S_END;
					else if(have) begin
						if(cur == 8'h00) begin pos <= pos + 1'd1; have <= 1'b0; end
						else st <= S_START;
					end
				default: ;
			endcase

			if(go_byte) begin
				sh <= go_val; bitn <= 4'd8; phase <= 1'b0; tape <= 1'b0; busy <= 1'b1;
				remain <= x3(go_val[7] ? os : zs);
			end
			if(go_high) begin
				bitn <= 4'd0; phase <= 1'b1; tape <= 1'b1; busy <= 1'b1;
				remain <= x3(go_cyc);
			end
		end
	end

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
