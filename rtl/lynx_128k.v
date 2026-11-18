//-------------------------------------------------------------------------------------------------
// Camputers Lynx 128K machine.
// From Kyp's lynx128 (https://github.com/Kyp069/lynx128, commit 439d50e, 2026-02-06, GPL v3), as merged
// for MiSTer by Shaeon (https://github.com/shaeon/Lynx_MiSTer, 1f05be1). Changes from Kyp's lynx.v:
// module names (lynx_128k, video_128k), outputs de (6845 display enable) and motor (port 80h d3);
// 6845 chip select on reads too (Kyp decoded writes only, so the crtcQ read returned FF); ESC -> /INT.
//-------------------------------------------------------------------------------------------------
//-------------------------------------------------------------------------------------------------
module lynx_128k
//-------------------------------------------------------------------------------------------------
(
	input  wire      clock,
	input  wire      pe12M,
	input  wire      ne6M0,
	input  wire      pe6M0,
	input  wire      pe1M5,
	input  wire      brk,     // ESC held: /INT (MAME brk_key)

	input  wire      reset,
	output wire      rfsh,
	output wire       de,
	output wire       motor,

	output wire      hsync,
	output wire      vsync,
	output wire      r,
	output wire      g,
	output wire      b,

	input  wire      tape,
	output wire[5:0] sound,

	output wire[3:0] row,
	input  wire[7:0] col,

	input  wire[7:0] joy0,
	input  wire[7:0] joy1,

	output wire[15:0] mem0A,
	input  wire[ 7:0] mem0Q,
	output wire       mem0R,

	output wire[15:0] mem1A,
	output wire[ 7:0] mem1D,
	input  wire[ 7:0] mem1Q,
	output wire       mem1R,
	output wire       mem1W,

	output wire[15:0] mem2A1,
	input  wire[ 7:0] mem2Q1,

	output wire[15:0] mem2A2,
	output wire[ 7:0] mem2D2,
	input  wire[ 7:0] mem2Q2,
	output wire       mem2W2,

	output wire[15:0] mem4A,
	output wire[ 7:0] mem4D,
	input  wire[ 7:0] mem4Q,
	output wire       mem4R,
	output wire       mem4W,

	output wire[ 1:0] fdcA,
	output wire[ 7:0] fdcD,
	input  wire[ 7:0] fdcQ,
	output wire       fdcR,
	output wire       fdcW,
	output wire       fdcSel,
	output wire       fdcSide
);
//--- cpu -----------------------------------------------------------------------------------------

	localparam IW = 8;

	reg[IW-1:0] irq = {IW{1'b0}};
	always @(posedge clock, posedge cursor) if(cursor) irq <= {IW{1'b1}}; else if(ne6M0) irq <= { irq[IW-2:0], 1'b0 };

	wire iorq;
	wire mreq;
	wire m1;
	wire rd;
	wire wr;

	wire[15:0] a;
	wire[ 7:0] d;
	wire[ 7:0] q;

	cpu cpu
	(
		.clock  (clock  ),
		.ne     (ne6M0  ),
		.pe     (pe6M0  ),
		.reset  (reset  ),
		.iorq   (iorq   ),
		.mreq   (mreq   ),
		.rfsh   (rfsh   ),
		.irq    (~(irq[IW-1] | brk)),
		.m1     (m1     ),
		.rd     (rd     ),
		.wr     (wr     ),
		.a      (a      ),
		.d      (d      ),
		.q      (q      )
	);

//--- crtc ----------------------------------------------------------------------------------------

	wire crtcCs = !(!iorq && (!wr || !rd) && !a[6] && a[2:1] == 2'b11);   // reads too: crtcQ is read at 86h / 87h
	wire crtcRs = a[0];
	wire crtcRw = wr;
	wire crtcDe;
	assign de = crtcDe;
	wire cursor;

	wire[13:0] crtcMa;
	wire[ 4:0] crtcRa;
	wire[ 7:0] crtcQ;

	UM6845R crtc
	(
		.TYPE   (1'b0   ),
		.CLOCK  (clock  ),
		.CLKEN  (pe1M5  ),
		.nRESET (reset  ),
		.ENABLE (1'b1   ),
		.nCS    (crtcCs ),
		.R_nW   (crtcRw ),
		.RS     (crtcRs ),
		.DI     (q      ),
		.DO     (crtcQ  ),
		.HSYNC  (hsync  ),
		.VSYNC  (vsync  ),
		.DE     (crtcDe ),
		.FIELD  (       ),
		.CURSOR (cursor ),
		.MA     (crtcMa ),
		.RA     (crtcRa )
	);

//---- io -----------------------------------------------------------------------------------------

	reg[4:0] reg58;
	wire wr58 = !iorq && m1 && a[6:0] == 7'h58;
	always @(posedge clock, negedge reset) if(!reset) reg58 <= 1'd0; else if(pe6M0) if(wr58) reg58 <= q[4:0];

	reg[7:0] reg80;
	wire wr80 = !iorq && !wr && !a[6] && a[2:1] == 2'b00;
	always @(posedge clock, negedge reset) if(!reset) reg80 <= 1'd0; else if(pe6M0) if(wr80) reg80 <= q;

	reg[7:0] reg82;
	wire wr82 = !iorq && !wr && !a[6] && a[2:1] == 2'b01;
	always @(posedge clock, negedge reset) if(!reset) reg82 <= 1'd0; else if(pe6M0) if(wr82) reg82 <= q;

	reg[5:0] reg84;
	wire wr84 = !iorq && !wr && !a[6] && a[2:1] == 2'b10;
	always @(posedge clock, negedge reset) if(!reset) reg84 <= 1'd0; else if(pe6M0) if(wr84) reg84 <= q[5:0];

	assign motor = reg80[3];

//--- video ---------------------------------------------------------------------------------------

	wire      altg = reg80[4];
	wire[1:0] vduA;

	video_128k video
	(
		.clock  (clock  ),
		.hsync  (hsync  ),
		.ce     (pe12M  ),
		.de     (crtcDe ),
		.altg   (altg   ),
		.a      (vduA   ),
		.d      (mem2Q1 ),
		.r      (r      ),
		.g      (g      ),
		.b      (b      )
	);

//--- sound ---------------------------------------------------------------------------------------

	assign sound =  reg84;

//--- bank 0 --------------------------------------------------------------------------------------

	assign mem0A = a;
	assign mem0R = !mreq && !rd && !reg82[3] && ((a[15:13] <= 2) || (a[15:13] == 7 && !reg58[4]));

//--- bank 1 --------------------------------------------------------------------------------------

	assign mem1A = a;
	assign mem1D = q;
	assign mem1R = !mreq && !rd && !reg82[2];
	assign mem1W = !mreq && !wr && !reg82[7];

//--- bank 2 --------------------------------------------------------------------------------------

	assign mem2A1 = { vduA, crtcMa[11:6], crtcRa[1:0], crtcMa[5:0] };

	assign mem2A2 = a;
	assign mem2D2 = q;
	assign mem2W2 = !mreq && !wr && reg82[6] && reg80[5];

//--- bank 4 --------------------------------------------------------------------------------------

	assign mem4A = a;
	assign mem4D = q;
	assign mem4R = !mreq && !rd && reg82[0];
	assign mem4W = !mreq && !wr && reg82[4];

//-------------------------------------------------------------------------------------------------

	assign row = a[11:8];

	assign fdcA = a[1:0];
	assign fdcD = q;
	assign fdcR = !iorq && m1 && a[6:2] == 5'h14;
	assign fdcW = !iorq && m1 && a[6:2] == 5'h15;
	assign fdcSel = !reg58[3] && reg58[1:0] == 0;
	assign fdcSide = reg58[2];

	assign d
		= !mreq && reg82[1] ? mem2Q2
		: mem0R ? mem0Q
		: mem1R ? mem1Q
		: mem4R ? mem4Q
		: !iorq && !a[6] && a[2:1] == 2'b00 ? col
		: !iorq && !a[6] && a[2:1] == 2'b01 ? { 5'b00000, tape, 2'b00 }
		: !iorq && !a[6] && a[2:1] == 2'b11 ? crtcQ
		: !iorq && a[6:0] == 8'h7A ? joy0
		: !iorq && a[6:0] == 8'h7B ? joy1
		: !iorq && a[6:2] == 5'h14 && !reg58[3] ? fdcQ
		: 8'hFF;

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
