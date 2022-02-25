//-------------------------------------------------------------------------------------------------
// Linkx48: Lynx 48K implementation for ZX-Uno board by Kyp
// MiSTer version by Yo_Me and rampa.
// https://github.com/Kyp069/lynx48
//-------------------------------------------------------------------------------------------------
// Z80 chip module implementation by Sorgelig
//-------------------------------------------------------------------------------------------------
module lynx48
//-------------------------------------------------------------------------------------------------
(
	input  wire      clock,
	output wire      led,
   	input  wire      reset_osd,
	output wire      hSync,
	output wire      vSync,
	output wire      hBlank,
	output wire      vBlank,
	output wire      crtcDe,
	output wire [8:0] rgb,
   	output wire      ce_pix,
	output wire [15:0]audio,
	input  wire      ear,
	
	input wire    	 autostart_basic,

	// roms, cartridges, etc
	input	wire [7:0]	ioctl_data,
	input	wire [24:0]	ioctl_addr,
	input	wire		ioctl_download,
	input	wire		ioctl_wr,
	input 	wire [7:0]	ioctl_index,
	
   	//
	input  wire [10:0] ps2,
	input  wire [7:0] joy_0,
   	input  wire [7:0] joy_1,
	
	// 
	input  wire [1:0] mode //0: lynx48k, 1: lynx96k, 2: lynx96k with scorpio rom
);


//-------------------------------------------------------------------------------------------------


assign ce_pix = ce600p;

reg[5:0] ce = 0;
always @(negedge clock) ce <= ce+1'd1;
reg[3:0] ce4 = 0;
always @(negedge clock) if(ce400p) ce4 <= 4'd0; else ce4 <= ce4+4'd1;

`ifdef VERILATOR
wire ce600p =  ce[0] ;
wire ce075p =  ~ce[0] & ~ce[1] & ~ce[2] & ce[3];

wire ce400p =            ce4[1];
wire ce400n =  ce4[0] & ~ce4[1];


`else
wire ce600p = ~ce[0] & ~ce[1] &  ce[2];
wire ce075p = ~ce[0] & ~ce[1] & ~ce[2] & ~ce[3] & ~ce[4] &  ce[5];

wire ce400p = ce4[0] &  ce4[1]          &  ce4[3];
wire ce400n = ce4[0] & ~ce4[1] & ce4[2] & ~ce4[3];

`endif


//-------------------------------------------------------------------------------------------------


wire reset = reset_osd && reset_kbd;

wire[ 7:0] di;
wire[ 7:0] data_out;
wire[15:0] a;
wire mreq;
wire iorq;
wire wr;
reg[15:0] dir;
reg dirset;

cpu Cpu
(
	.reset  (reset  ),
	.clock  (clock  ),
	.cep    (ce400p ),
	.cen    (ce400n ),
	.int_n  (1),
	.halt_n (),
	.mreq   (mreq   ),
	.iorq   (iorq   ),
	.wr     (wr     ),
	.di     (di     ),
	.data_out (data_out     ),
	.a      (a      ),
	.dir 	(dir	),
	.dirset (dirset	)
);

//-------------------------------------------------------------------------------------------------

wire [15:0]			tape_addr;
wire				tape_wr;
wire [7:0]			tape_dout;
wire				tape_complete;
cassette cassette
(
  .clk(clock),
  
  .ioctl_download(ioctl_download),
  .ioctl_wr(ioctl_wr),
  .ioctl_addr(ioctl_addr),
  .ioctl_dout(ioctl_data),

  .reset_n(reset),

  .autostart_basic(autostart_basic),

  .tape_addr(tape_addr),
  .tape_wr(tape_wr),
  .tape_dout(tape_dout),
  .tape_complete(tape_complete)
);

always @(posedge clock) 
begin
	if (tape_complete == 1'b1)
		begin
            $display( "(tc %x tape_addr %x)", tape_complete,tape_addr);
			dir <= tape_addr;
			dirset <= 1'b1;
		end
	else
		begin
			dirset <= 1'b0;
		end
end

//-------------------------------------------------------------------------------------------------

wire[ 7:0] romDo_48;
wire[ 7:0] romDo_96;
wire[ 7:0] romDo_96s;
wire[14:0] romA;

rom #(.AW(14), .FN("48K-1+2.hex")) Rom_48
(
	.clock  (clock  ),
	.ce     (ce400p   ),
	.data_out     (romDo_48),
	.a      (romA[13:0]   )
);

rom #(.AW(15), .FN("96K-1+2+3.hex")) Rom_96
(
	.clock  (clock  ),
	.ce     (ce400p   ),
	.data_out(romDo_96),
	.a      (romA   )
);

rom #(.AW(15), .FN("96K-1+2+3s.hex")) Rom_96s
(
	.clock  (clock  ),
	.ce     (ce400p   ),
	.data_out(romDo_96s),
	.a      (romA   )
);

wire[ 7:0] ramDi;
wire[ 7:0] ramDo;
wire[15:0] ramA;

wire ramWe;

bram #(.widthad_a(16)) Ram
(
    .clock_a  	(clock  ),
    .enable_a 	(ce400p  ),
    .wren_a   	(~ramWe  ),
    .data_a   	(ramDi  ),
    .q_a     	(ramDo  ),
    .address_a	(ramA  ),

    .clock_b  	 (clock  	),
    .enable_b   (1			),
    .wren_b     (tape_wr	),
    .data_b     (tape_dout	),
    .address_b  (tape_addr	)	
);

wire[ 7:0] vrbDo1;
wire[13:0] vrbA1;
wire[ 7:0] vrbDi2;
wire[ 7:0] vrbDo2;
wire[13:0] vrbA2;
wire vrbWe2;

dpr #(.AW(14)) Vrb
(
	.clock  (clock  ),
	.ce1    (ce600p ),
	.do1    (vrbDo1 ),
	.a1     (vrbA1  ),
	.ce2    (ce400p ),
	.we2    (vrbWe2 ),
	.di2    (vrbDi2 ),
	.do2    (vrbDo2 ),
	.a2     (vrbA2  )
);

wire[ 7:0] vggDo1;
wire[13:0] vggA1;
wire[ 7:0] vggDi2;
wire[ 7:0] vggDo2;
wire[13:0] vggA2;
wire vggWe2;

dpr #(.AW(14)) Vgg
(
	.clock  (clock  ),
	.ce1    (ce600p ),
	.do1    (vggDo1 ),
	.a1     (vggA1  ),
	.ce2    (ce400p ),
	.we2    (vggWe2 ),
	.di2    (vggDi2 ),
	.do2    (vggDo2 ),
	.a2     (vggA2  )
);

//-------------------------------------------------------------------------------------------------

wire io7F = !(!iorq && !wr && a[6:0] == 7'h7F);

reg[7:0] reg7F;
always @(negedge reset, posedge clock) if(!reset) reg7F <= 1'd0; else if(ce400p) if(!io7F) reg7F <= data_out;
	  
//-------------------------------------------------------------------------------------------------

wire io80 = !(!iorq && !wr && a[7] && !a[6] && !a[2] && !a[1]);

reg[5:1] reg80;
reg motor;
reg speaker;

always @(negedge reset, posedge  clock) if(!reset) reg80 <= 8'h0c; else if(ce400p) if(!io80) reg80 <= data_out[5:1];
		
//-------------------------------------------------------------------------------------------------

wire io84 = !(!iorq && !wr && a[7] && !a[6] &&  a[2] && !a[1]);

reg[5:0] reg84;
always @(posedge clock) if(ce400p) if(!io84) reg84 <= data_out[5:0];

//-------------------------------------------------------------------------------------------------

wire crtcCs = !(!iorq && !wr && a[7] && !a[6] &&  a[2] && a[1]);
wire crtcRs = a[0];
wire crtcRw = wr;

wire[ 7:0] crtcDi = data_out;

wire[13:0] crtcMa;
wire[ 4:0] crtcRa;
wire cursor;

UM6845R Crtc
(
        .TYPE   (1'b0   ),
        .CLOCK  (clock  ),
        .CLKEN  (ce075p ),
        .nRESET (reset  ),
        .ENABLE (1'b1   ),
        .nCS    (crtcCs ),
        .R_nW   (crtcRw ),
        .RS     (crtcRs ),
        .DI     (crtcDi ),
        .DO     (       ),
        .VSYNC  (vSync  ),
        .HSYNC  (hSync  ),
        .DE     (crtcDe ),
		.hBlank (hBlank ),   
	    .vBlank (vBlank ),

        .FIELD  (       ),
        .CURSOR (cursor ),
        .MA     (crtcMa ),
        .RA     (crtcRa )
);

wire 			altg = reg80[4];
wire [ 7:0] 	vduDi;
wire [1:0] 		vduB;

//-------------------------------------------------------------------------------------------------

wire[3:0] keybRow = a[11:8];
wire[7:0] keybDo;
wire reset_kbd;
wire cas;
wire boot;
keyboard Keyboard
(
	.clock  (clock  ),
	.ce     (ce600p   ),
	.ps2    (ps2    ),
	.reset  (reset_kbd),
	.cas    (cas    ),
	.boot   (boot   ),
	.row    (keybRow),
	.data_out (keybDo )
);

//-------------------------------------------------------------------------------------------------

video Video
(
		.reset  (~hSync ),
        .clock  (clock  ),
        .ce     (ce600p ),
        .de     (crtcDe ),
        .altg   (altg   ),
        .di     (vduDi  ),
        .rgb    (rgb    ),
        .b      (vduB   )
);

//-------------------------------------------------------------------------------------------------

audio Audio
(
        .clock  (clock  ),
        .reset  (reset  ),
        .ear    (!ear   ),
        .dac    (reg84  ),
        .audio  (audio  )
);

//-------------------------------------------------------------------------------------------------

assign romA = (mode != 2'b00 ? a[14:0] : a[13:0]);

assign ramWe = !(!mreq && !wr && !reg7F[0]);
assign ramDi = data_out;
assign ramA = mode == 2'b00 ? { 2'b00,  a[14], a[12:0] } : a ;

assign vrbA1 = { vduB[0], vmmA };
assign vrbWe2 = !(!mreq && !wr && reg7F[1] && reg80[5]);
assign vrbDi2 = data_out;
assign vrbA2 = { a[14], a[12:0] };

assign vggA1 = { vduB[0], vmmA };
assign vggWe2 = !(!mreq && !wr && reg7F[2] && reg80[5]);
assign vggDi2 = data_out;
assign vggA2 = { a[14], a[12:0] };

wire[12:0] vmmA = { crtcMa[10:5], crtcRa[1:0], crtcMa[4:0] };

reg casd;
reg cas23;

always @(posedge clock) if(ce600p)
begin
       casd <= cas;
       if(casd && !cas) cas23 <= ~cas23;
end

assign vduDi = vduB[1] ? (!cas23 || !reg80[3] ? vggDo1 : 8'h00) : (!cas23 || !reg80[2] ? vrbDo1 : 8'h00);

//-------------------------------------------------------------------------------------------------

assign di
        = !mreq && !reg7F[4] && a[15:14] == 2'b00  && mode == 2'b00 ? romDo_48
		  : !mreq && !reg7F[4] && a[15:13] == 3'b010 && mode == 2'b00 ? 8'hFF 
		  : (!mreq && !reg7F[4] && mode ==1 && a[15:14] == 2'b00 ) ||(mode ==1 && a[15:13] == 3'b010) ? romDo_96
		  : (!mreq && !reg7F[4] && mode ==2 && a[15:14] == 2'b00 ) ||(mode ==2 && a[15:13] == 3'b010) ? romDo_96s
        : !mreq && !reg7F[5] ? ramDo
        : !mreq &&  reg7F[6] && !reg80[2] ? vrbDo2
        : !mreq &&  reg7F[6] && !reg80[3] ? vggDo2
		  : !iorq &&  a[7:0] == 8'h80 ? { keybDo[7:1], reg80[1] ? ear : keybDo[0] }
        : !iorq &&  a[6:0] == 8'h7A ? { 2'b00, joy_0 }
        : !iorq &&  a[6:0] == 8'h7B ? { 2'b00, joy_1 }
        : 8'hFF;

assign led=ear;

//-------------------------------------------------------------------------------------------------

endmodule

//-------------------------------------------------------------------------------------------------
