//-------------------------------------------------------------------------------------------------
// Lynx .WAV player: a tape recording (a real cassette capture or a TAP converted with lynx2wav)
// played into the tape input, as the line-in would, from the image in DDR3.
//
// The RIFF header is read through the byte port: "fmt " gives channels, sample rate and bits
// (8-bit unsigned or 16-bit signed PCM), "data" the samples. The first channel goes through a
// Schmitt trigger (hysteresis: 8-bit +-6, 16-bit +-1536) and is inverted as MAME reads the
// cassette (camplynx.cpp port80_r: input > +0.02 -> d0 = 0), which matches lynx_tap's levels.
//
// Timebase: the CPU clock enable, so turbo plays the recording with the CPU: one sample every
// cpu_hz / rate enables (4 MHz 48K / 96K, 6 MHz 128K), with a phase accumulator. The recording
// only moves while play (the motor) is on.
//-------------------------------------------------------------------------------------------------
module lynx_wav
(
	input  wire        clock,
	input  wire        rewind,
	input  wire        cpu_ce,
	input  wire        m128,
	input  wire        play,
	input  wire [24:0] size,            // image length, 0 = none

	output reg  [24:0] rd_addr,
	output reg         rd_req,
	input  wire        rd_ack,
	input  wire [ 7:0] rd_data,

	output reg         tape,
	output wire        running,
	output wire        eot,
	output reg  [24:0] pos,
	output reg         valid,           // a PCM WAV header was found
	output reg  [31:0] rate,
	output reg  [31:0] data_len,
	output wire [ 2:0] align           // bytes per sample frame
);

	localparam [3:0] H_ID = 4'd0, H_SIZE = 4'd1, H_FMT = 4'd2, H_SKIP = 4'd3, H_PLAY = 4'd4, H_END = 4'd5;
	reg  [3:0] st = H_END;
	reg [31:0] word;                     // little-endian collector
	reg  [2:0] nb;                       // bytes collected
	reg [31:0] cid, csize;               // chunk id / size
	reg [31:0] skip;
	reg  [4:0] fi;                       // byte index inside "fmt "
	reg [15:0] chans, bits;
	reg [31:0] data_end;
	reg  [2:0] bps;                      // bytes per sample frame (block align, up to 4)
	assign align = bps;
	reg  [2:0] bidx;                     // byte of the frame being read
	reg [15:0] smp;
	reg        need;                     // fetch the next frame
	reg [31:0] acc;
	reg        have = 1'b0;
	reg  [7:0] cur;

	assign eot     = st == H_END;
	assign running = play && st == H_PLAY;

	wire [31:0] cpu_hz = m128 ? 32'd6000000 : 32'd4000000;
	wire        at_end = pos >= size;

	always @(posedge clock) begin
		if(!have && !rd_req && !at_end) begin rd_addr <= pos; rd_req <= 1'b1; end
		if(rd_req && rd_ack) begin rd_req <= 1'b0; cur <= rd_data; have <= 1'b1; end

		if(rewind) begin
			st <= size >= 25'd44 ? H_ID : H_END; pos <= 25'd12; have <= 1'b0; rd_req <= 1'b0;
			nb <= 3'd0; valid <= 1'b0; tape <= 1'b0; acc <= 32'd0; need <= 1'b1;
		end
		else case(st)
			// chunk header: id, size (after "RIFF" size "WAVE")
			H_ID, H_SIZE:
				if(at_end) st <= H_END;
				else if(have) begin
					word <= { cur, word[31:8] }; nb <= nb + 1'd1; pos <= pos + 1'd1; have <= 1'b0;
					if(nb == 3'd3) begin
						nb <= 3'd0;
						if(st == H_ID) begin cid <= { cur, word[31:8] }; st <= H_SIZE; end
						else begin
							csize <= { cur, word[31:8] };
							if(cid == "atad") begin                 // "data" read little-endian
								data_end <= { 7'd0, pos } + 1'd1 + { cur, word[31:8] };
								data_len <= { cur, word[31:8] };
								st <= H_PLAY; valid <= 1'b1; bidx <= 3'd0; need <= 1'b1;
							end
							else if(cid == " tmf") begin fi <= 5'd0; st <= H_FMT; end
							else begin skip <= { cur, word[31:8] }; st <= H_SKIP; end
						end
					end
				end
			H_FMT:                               // format(2) channels(2) rate(4) byterate(4) align(2) bits(2)
				if(at_end) st <= H_END;
				else if(have) begin
					pos <= pos + 1'd1; have <= 1'b0; fi <= fi + 1'd1;
					case(fi)
						5'd2:  chans[7:0]  <= cur;  5'd3:  chans[15:8] <= cur;
						5'd4:  rate[7:0]   <= cur;  5'd5:  rate[15:8]  <= cur;
						5'd6:  rate[23:16] <= cur;  5'd7:  rate[31:24] <= cur;
						5'd12: bps <= cur[2:0];
						5'd14: bits[7:0]   <= cur;  5'd15: bits[15:8]  <= cur;
						default: ;
					endcase
					if({ 27'd0, fi } + 1'd1 == csize) st <= H_ID;
					else if(fi == 5'd15) begin skip <= csize - 32'd16; st <= H_SKIP; end
				end
			H_SKIP:
				if(skip == 32'd0) st <= H_ID;
				else if(at_end) st <= H_END;
				else begin pos <= pos + 1'd1; have <= 1'b0; skip <= skip - 1'd1; end
			H_PLAY: begin
				if({ 7'd0, pos } >= data_end || at_end) begin st <= H_END; tape <= 1'b0; end
				// read the next frame: its first (one or two) bytes are channel 1, skip the rest
				else if(need && have) begin
					pos <= pos + 1'd1; have <= 1'b0; bidx <= bidx + 1'd1;
					if(bidx == 3'd0) smp[7:0]  <= cur;
					if(bidx == 3'd1) smp[15:8] <= cur;
					if(bidx + 1'd1 >= bps) begin bidx <= 3'd0; need <= 1'b0; end
				end
				// one frame every cpu_hz / rate CPU enables, while the motor runs
				if(play && cpu_ce && !need) begin
					if(acc + rate >= cpu_hz) begin
						acc <= acc + rate - cpu_hz; need <= 1'b1;
						if(bits == 16'd8) begin
							if(smp[7:0] > 8'd134) tape <= 1'b0; else if(smp[7:0] < 8'd122) tape <= 1'b1;
						end
						else begin
							if(!smp[15] && smp > 16'd1536) tape <= 1'b0; else if(smp[15] && smp < 16'hFA00) tape <= 1'b1;
						end
					end
					else acc <= acc + rate;
				end
			end
			default: ;
		endcase
	end

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
