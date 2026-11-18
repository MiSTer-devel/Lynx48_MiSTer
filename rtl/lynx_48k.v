//-------------------------------------------------------------------------------------------------
// Camputers Lynx 48K / 96K machine.
// From Kyp's lynx (https://github.com/Kyp069/lynx, commit 48398cb, 2026-02-01, GPL v3), as merged
// for MiSTer by Shaeon (https://github.com/shaeon/Lynx_MiSTer, 1f05be1). Changes from Kyp's lynx.v:
// module names (lynx_48k, video_48k), outputs de (6845 display enable) and motor (port 80h d1);
// 6845 readable at 86h / 87h (MAME); ESC -> /INT (brk); disk interface only with dosM;
// 48K: ROM read space 0000-5FFF like the 96K (the 4000-5FFF socket is empty and reads FF);
// the tape replaces keyboard d0 of port 80h while the 6845's MA13 is high (Jynx; the 48K schematic
// gates CASS_SER_IN with MA13), not while the motor bit is set: Level 9 leaves the motor bit on
// and its keyboard then read the tape level as keys.
//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------
module lynx_48k
//-------------------------------------------------------------------------------------------------
(
	input  wire       ramM,  // 0: 48K, 1: 96K
	input  wire       casM,  // 0: off, 1: on
	input  wire       dosM,  // 1: disk interface (WD1793 at 50h-58h, LynxDOS ROM at E000h); MAME's lynx48k has none
	input  wire       brk,   // ESC held: /INT (MAME brk_key)

	input  wire       clock, // 48 MHz
	input  wire       pe06M,
	input  wire       peM75,
	input  wire       pe04M,
	input  wire       ne04M,

	input  wire       reset,
	output wire       rfsh,
	output wire       de,
	output wire       motor,

	output wire       hSync,
	output wire       vSync,
	output wire       r,
	output wire       g,
	output wire       b,

	input  wire       tape,
	output wire[ 5:0] sound,

	output wire[ 3:0] row,
	input  wire[ 7:0] col,

	input  wire[ 7:0] joy0,
	input  wire[ 7:0] joy1,

	output wire[15:0] mem0A,
	input  wire[ 7:0] mem0Q,
	output wire       mem0R,

	output wire[15:0] mem1A,
	output wire[ 7:0] mem1D,
	input  wire[ 7:0] mem1Q,
	output wire       mem1R,
	output wire       mem1W,

	output wire[13:0] mem2A1,
	input  wire[ 7:0] mem2Q1,

	output wire[13:0] mem2A2,
	output wire[ 7:0] mem2D2,
	input  wire[ 7:0] mem2Q2,
	output wire       mem2W2,

	output wire[13:0] mem3A1,
	input  wire[ 7:0] mem3Q1,

	output wire[13:0] mem3A2,
	output wire[ 7:0] mem3D2,
	input  wire[ 7:0] mem3Q2,
	output wire       mem3W2,

	output wire[ 1:0] fdcA,
	output wire[ 7:0] fdcD,
	input  wire[ 7:0] fdcQ,
	output wire       fdcR,
	output wire       fdcW,
	output wire       fdcSel,
	output wire       fdcSide
);
//--- cpu -----------------------------------------------------------------------------------------

	wire mreq;
	wire iorq;
	wire irq = ~(cursor | brk);
	wire m1;
	wire rd;
	wire wr;

	wire[15:0] a;
	wire[ 7:0] d;
	wire[ 7:0] q;

	cpu cpu
	(
		.clock  (clock  ),
		.reset  (reset  ),
		.ne     (ne04M  ),
		.pe     (pe04M  ),
		.rfsh   (rfsh   ),
		.iorq   (iorq   ),
		.mreq   (mreq   ),
		.irq    (irq    ),
		.m1     (m1     ),
		.rd     (rd     ),
		.wr     (wr     ),
		.a      (a      ),
		.d      (d      ),
		.q      (q      )
	);

//--- crtc ----------------------------------------------------------------------------------------

	wire crtcCs = !(!iorq && (!wr || !rd) && a[7] && !a[6] && a[2] && a[1]);   // reads too (MAME: 86h status, 87h register)
	wire[ 7:0] crtcQ;
	wire crtcRs = a[0];
	wire crtcRw = wr;
	wire crtcDe;
	assign de = crtcDe;
	wire cursor;

	wire[13:0] crtcMa;
	wire[ 4:0] crtcRa;
	wire[12:0] crtcA = { crtcMa[10:5], crtcRa[1:0], crtcMa[4:0] };

	UM6845R crtc
	(
		.TYPE   (1'b0   ),
		.CLOCK  (clock  ),
		.CLKEN  (peM75  ),
		.nRESET (reset  ),
		.ENABLE (1'b1   ),
		.nCS    (crtcCs ),
		.R_nW   (crtcRw ),
		.RS     (crtcRs ),
		.DI     (q      ),
		.DO     (crtcQ  ),
		.HSYNC  (hSync  ),
		.VSYNC  (vSync  ),
		.DE     (crtcDe ),
		.FIELD  (       ),
		.CURSOR (cursor ),
		.MA     (crtcMa ),
		.RA     (crtcRa )
	);

//--- io ------------------------------------------------------------------------------------------

	reg[4:0] reg58;
	wire wr58 = !iorq && !wr && m1 && dosM && a[6:0] == 7'h58;
	always @(posedge clock, negedge reset) if(!reset) reg58 <= 1'd0; else if(pe04M) if(wr58) reg58 <= q[4:0];

	reg[7:0] reg7F;
	wire wr7F = !iorq && !wr && a[13] && a[6:0] == 7'h7F;
	always @(posedge clock, negedge reset) if(!reset) reg7F <= 1'd0; else if(pe04M) if(wr7F) reg7F <= q;

	reg[5:1] reg80;
	wire wr80 = !iorq && !wr && a[7] && !a[6] && !a[2] && !a[1];
	always @(posedge clock, negedge reset) if(!reset) reg80 <= 1'd0; else if(pe04M) if(wr80) reg80 <= q[5:1];

	reg[5:0] reg84;
	wire wr84 = !iorq && !wr && a[7] && !a[6] &&  a[2] && !a[1];
	always @(posedge clock) if(pe04M) if(wr84) reg84 <= q[5:0];

	assign motor = reg80[1];

//--- video ---------------------------------------------------------------------------------------

	wire altg = reg80[4];

	wire[7:0] vduDi = vduB[1] ? (!casM || !reg80[3] ? mem3Q1 : 8'h00) : (!casM || !reg80[2] ? mem2Q1 : 8'h00);
	wire[1:0] vduB;

	video_48k video
	(
		.clock  (clock  ),
		.hSync  (hSync  ),
		.ce     (pe06M  ),
		.de     (crtcDe ),
		.altg   (altg   ),
		.d      (vduDi  ),
		.r      (r      ),
		.g      (g      ),
		.b      (b      ),
		.bank   (vduB   )
	);

//--- sound ---------------------------------------------------------------------------------------

	assign sound =  reg84;

//--- bank 0 --------------------------------------------------------------------------------------

	assign mem0A = a;
	assign mem0R = !mreq && !rd && !reg7F[4] && ((a[15:13] < 3) || (a[15:13] == 7 && !reg58[4] && dosM)); // 48K: 4000-5FFF = empty ic44 socket, reads FF (romP page 7), as the 2022 core

//--- bank 1 --------------------------------------------------------------------------------------

	assign mem1A = ramM ? a : { 2'b00, a[14], a[12:0] };
	assign mem1D = q;
	assign mem1R = !mreq && !rd && !reg7F[5];
	assign mem1W = !mreq && !wr && !reg7F[0];

//--- bank 2 --------------------------------------------------------------------------------------

	assign mem2A1 = { vduB[0], crtcA };

	assign mem2A2 = { a[14], a[12:0] };
	assign mem2D2 = q;
	assign mem2W2 = !mreq && !wr && reg7F[1] && reg80[5] && !reg80[2];   // /CASEN gates the bank's /CAS (48K v3 IC41)

//--- bank 3 --------------------------------------------------------------------------------------

	assign mem3A1 = { vduB[0], crtcA };

	assign mem3A2 = { a[14], a[12:0] };
	assign mem3D2 = q;
	assign mem3W2 = !mreq && !wr && reg7F[2] && reg80[5] && !reg80[3];   // as bank 2

//-------------------------------------------------------------------------------------------------

	assign row = a[11:8];

	assign fdcA = a[1:0];
	assign fdcD = q;
	assign fdcR = !iorq && m1 && dosM && a[6:2] == 5'h14;
	assign fdcW = !iorq && m1 && dosM && a[6:2] == 5'h15;
	assign fdcSel = !reg58[3] && reg58[1:0] == 0;
	assign fdcSide = reg58[2];

	assign d
		= mem0R ? mem0Q
		: mem1R ? mem1Q
		: !mreq && reg7F[6] && !reg80[2] ? mem2Q2
		: !mreq && reg7F[6] && !reg80[3] ? mem3Q2
		: !iorq && a[6:2] == 5'h14 && !reg58[3] && dosM ? fdcQ
		: !iorq && a[7] && !a[6] && a[2] && a[1] ? crtcQ
		: !iorq && a[7:0] == 8'h80 ? { col[7:1], crtcMa[13] ? tape : col[0] }   // tape on d0 while 6845 MA13 is high (R12 d5): Jynx, 48K schematic
		: !iorq && a[6:0] == 8'h7A ? joy0
		: !iorq && a[6:0] == 8'h7B ? joy1
		: 8'hFF;

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
