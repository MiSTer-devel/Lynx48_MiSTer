//-------------------------------------------------------------------------------------------------
// ZXP3 para MiSTer - reproductor TZX con el fichero guardado en la DDR3 del HPS.
// Equivalente al tzx.v de Kyp (que usa BRAM), pero en MiSTer no hay BRAM para un TZX de cientos
// de KB, así que la cinta va a la DDR3 (zona del core, a partir de 0x30000000) y se lee byte a
// byte con una caché de una palabra de 64 bits. El protocolo req/ack de tzxplayer permite esperar
// a que llegue el dato, así que la latencia de la DDR3 no afecta.
//
// Además: bucles de la cinta (0x24/0x25), el bloque 0x2A solo para la cinta si stop48 = 1, y
// ficheros TAP: si el fichero no empieza por "ZXTape!", se le entrega a tzxplayer un TZX
// equivalente generado al vuelo (cabecera y un bloque 0x10 con 1 s de pausa por cada bloque).
//
// Lynx core (Lynx48_MiSTer): a file that is not a TZX is a Lynx .TAP, played by rtl/lynx_tap.sv
// through the ext_* byte port below (same DDR3 buffer and cache); the Spectrum TAP -> TZX
// conversion of the ZXP3 version is not used here (tzxplayer does not start for a TAP).
//-------------------------------------------------------------------------------------------------
module tape_ddr
#(
	parameter MS = 56000                // ciclos de ce por milisegundo
)
(
	input  wire        clock,
	input  wire        ce,              // habilita el reloj de tzxplayer

	// carga del fichero (hps_io)
	input  wire        dl,              // descarga del TZX en curso
	input  wire [26:0] dlA,
	input  wire [ 7:0] dlD,
	input  wire        dlW,
	output reg         dlWait,

	// control
	input  wire        play,            // pulso o nivel, activo a nivel alto
	input  wire        stop,            // pulso o nivel, activo a nivel alto
	input  wire        stop48,          // 1: el bloque 0x2A ("parar si es un 48K") para la cinta
	output wire        busy,            // cinta en marcha
	output wire        tape,            // señal EAR

	// Lynx TAP: byte port for rtl/lynx_tap.sv (used while the image is not a TZX)
	output wire        is_tap,          // the image is not a TZX
	output wire [27:0] tap_size,        // bytes loaded
	input  wire [24:0] ext_a,
	input  wire        ext_req,
	output wire        ext_ack,
	output wire [ 7:0] ext_q,

	// DDR3
	output wire        DDRAM_CLK,
	input  wire        DDRAM_BUSY,
	output wire [ 7:0] DDRAM_BURSTCNT,
	output wire [28:0] DDRAM_ADDR,
	input  wire [63:0] DDRAM_DOUT,
	input  wire        DDRAM_DOUT_READY,
	output wire        DDRAM_RD,
	output wire [63:0] DDRAM_DIN,
	output wire [ 7:0] DDRAM_BE,
	output wire        DDRAM_WE
);
//--- ddram ---------------------------------------------------------------------------------------

	reg [27:3] ramA;
	reg [63:0] ramD;
	reg [ 7:0] ramBE;
	reg        ramWE = 1'b0;
	reg        ramRD = 1'b0;

	assign DDRAM_CLK      = clock;
	assign DDRAM_BURSTCNT = 8'd1;
	assign DDRAM_ADDR     = { 4'b0011, ramA };
	assign DDRAM_DIN      = ramD;
	assign DDRAM_BE       = ramBE;
	assign DDRAM_WE       = ramWE;
	assign DDRAM_RD       = ramRD;

	reg [27:0] size = 1'd0;     // bytes cargados
	reg [27:0] a = 1'd0;        // byte que toca leer

	reg [27:3] cacheA;
	reg [63:0] cacheD;
	reg        cacheV = 1'b0;
	reg        reading = 1'b0;

	wire       isTap;
	wire [27:0] rdA = isTap ? { 3'b000, ext_a } : a;   // cache address: lynx_tap or tzxplayer
	wire       hit = cacheV && cacheA == rdA[27:3];

	// cabecera TZX: "ZXTape!" + 0x1A + versión 1.20
	function [7:0] tzxHdr(input [3:0] i);
		case(i)
			0: tzxHdr = "Z"; 1: tzxHdr = "X"; 2: tzxHdr = "T"; 3: tzxHdr = "a"; 4: tzxHdr = "p";
			5: tzxHdr = "e"; 6: tzxHdr = "!"; 7: tzxHdr = 8'h1A; 8: tzxHdr = 8'h01; default: tzxHdr = 8'h14;
		endcase
	endfunction

	// formato: TZX si los 8 primeros bytes son la firma, TAP en otro caso
	reg dlP = 1'b0, sigOk = 1'b0;
	always @(posedge clock) begin
		dlP <= dl;
		if(dl && !dlP) sigOk <= 1'b1;
		else if(dlW && dl && dlA < 8 && dlD != tzxHdr(dlA[3:0])) sigOk <= 1'b0;
		else if(!dl && dlP && size < 8) sigOk <= 1'b0;
	end
	assign isTap = !sigOk;
	wire [7:0] q = cacheD[{ rdA[2:0], 3'b000 } +: 8];

	assign is_tap   = isTap;
	assign tap_size = size;
	assign ext_ack  = isTap && ext_req && hit && !dl;
	assign ext_q    = q;

	always @(posedge clock) begin
		if(!DDRAM_BUSY) begin
			if(ramWE) dlWait <= 1'b0;
			ramWE <= 1'b0;
			ramRD <= 1'b0;
		end

		if(dl) begin
			cacheV <= 1'b0;
			if(dlW) begin
				ramA   <= { 1'b0, dlA[26:3] };
				ramD   <= {8{ dlD }};
				ramBE  <= 8'd1 << dlA[2:0];
				ramWE  <= 1'b1;
				dlWait <= 1'b1;
				size   <= { 1'b0, dlA } + 1'd1;
			end
		end
		else if(!ramWE && !ramRD && !reading && !hit) begin
			ramA    <= rdA[27:3];
			cacheA  <= rdA[27:3];
			cacheV  <= 1'b0;
			ramRD   <= 1'b1;
			reading <= 1'b1;
		end

		if(reading && DDRAM_DOUT_READY) begin
			cacheD  <= DDRAM_DOUT;
			cacheV  <= 1'b1;
			reading <= 1'b0;
		end
	end

//--- tzx -----------------------------------------------------------------------------------------

	wire       req;
	reg        ack = 1'b0;
	reg        motor = 1'b0;
	reg        restart = 1'b0;
	reg  [7:0] data;
	reg        fetch = 1'b0;
	wire       eot;
	wire       eot48;
	wire       loopStart, loopNext;
	reg [27:0] loopA = 1'd0;

	// TAP: generador del TZX equivalente
	localparam [2:0] sHDR = 3'd0, sID = 3'd1, sP0 = 3'd2, sP1 = 3'd3, sLEN0 = 3'd4, sLEN1 = 3'd5, sDATA = 3'd6;
	reg  [2:0] tapSt = sHDR;
	reg  [3:0] tapHi = 4'd0;
	reg [15:0] tapLen = 16'd0;

	always @(posedge clock) begin
		restart <= 1'b0;

		if(play && !dl && !isTap) begin
			a <= 1'd0;
			fetch <= 1'b0;
			tapSt <= sHDR;
			tapHi <= 4'd0;
			motor <= 1'b1;
			restart <= 1'b1;
		end
		else if(stop || eot || (eot48 && stop48) || dl || (isTap ? (tapSt == sID && a >= size) : a >= size)) motor <= 1'b0;
		else if(loopStart) loopA <= a;
		else if(loopNext)  a <= loopA;
		else if(req != ack && !fetch && isTap && tapSt <= sP1) begin
			// TAP: bytes que no están en el fichero (cabecera TZX, ID 0x10 y pausa de 1000 ms)
			ack <= req;
			case(tapSt)
				sHDR: begin data <= tzxHdr(tapHi); tapHi <= tapHi+1'd1; if(tapHi == 9) tapSt <= sID; end
				sID:  begin data <= 8'h10; tapSt <= sP0; end
				sP0:  begin data <= 8'hE8; tapSt <= sP1; end
				default: begin data <= 8'h03; tapSt <= sLEN0; end
			endcase
		end
		else if(req != ack && !fetch) fetch <= 1'b1;
		else if(fetch && hit) begin
			data  <= q;
			ack   <= req;
			a     <= a+1'd1;
			fetch <= 1'b0;
			// TAP: longitud del bloque (2 bytes) y datos
			case(tapSt)
				sLEN0: begin tapLen[7:0] <= q; tapSt <= sLEN1; end
				sLEN1: begin tapLen[15:8] <= q; tapSt <= (tapLen[7:0] == 0 && q == 0) ? sID : sDATA; end
				sDATA: begin tapLen <= tapLen-1'd1; if(tapLen == 1) tapSt <= sID; end
				default: ;
			endcase
		end
	end

	tzxplayer #(.TZX_MS(MS)) tzxplayer
	(
		.clk         (clock  ),
		.ce          (ce     ),
		.tzx_ack     (ack    ),
		.tzx_req     (req    ),
		.host_tap_in (data   ),
		.cass_motor  (motor  ),
		.restart_tape(restart),
		.loop_start  (loopStart),
		.loop_next   (loopNext ),
		.stop        (eot    ),
		.stop48k     (eot48  ),
		.cass_read   (tape   ),
		.cass_running(busy   )
	);

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
