//-------------------------------------------------------------------------------------------------
// Lynx keyboard matrix from MiSTer's ps2_key. Key table from Kyp's matrix.v (Kyp069/lynx 48398cb),
// plus End (row 9 d4, as in MAME), right Ctrl and keypad Enter. Keys are active low; col = key[row].
//-------------------------------------------------------------------------------------------------
module matrix
//-------------------------------------------------------------------------------------------------
(
	input  wire       clock,
	input  wire[10:0] ps2_key,       // [10] toggles per event, [9] pressed, [8] extended, [7:0] code
	input  wire[ 3:0] row,
	output wire[ 7:0] col,
	output wire       esc,           // ESC held (active high): BREAK
	output reg        F9,            // active low
	output reg        play,          // PgUp, active low
	output reg        stop           // PgDn, active low
);
//-------------------------------------------------------------------------------------------------

reg[7:0] key[9:0];
initial begin
	{ F9, play, stop } = {3{ 1'b1 }};
	key[0] = 8'hFF; key[1] = 8'hFF; key[2] = 8'hFF; key[3] = 8'hFF; key[4] = 8'hFF;
	key[5] = 8'hFF; key[6] = 8'hFF; key[7] = 8'hFF; key[8] = 8'hFF; key[9] = 8'hFF;
end

reg  old_toggle = 1'b0;
wire strb     = ps2_key[10] != old_toggle;
wire pressed  = ps2_key[9];
wire extended = ps2_key[8];
wire[7:0] code = ps2_key[7:0];

always @(posedge clock) begin
	old_toggle <= ps2_key[10];
	if(strb) begin
		if(extended)
			case(code)
				8'h7D: play <= ~pressed; // PgUp
				8'h7A: stop <= ~pressed; // PgDown

				8'h75: key[0][4] <= ~pressed; // up
				8'h72: key[0][5] <= ~pressed; // down
				8'h6B: key[9][2] <= ~pressed; // left
				8'h74: key[9][5] <= ~pressed; // right
				8'h69: key[9][4] <= ~pressed; // end (MAME "End")
				8'h14: key[2][6] <= ~pressed; // right control
				8'h5A: key[9][3] <= ~pressed; // keypad enter = return
			endcase
		else
			case(code)
				8'h01: F9 <= ~pressed; // F9 (Lynx reset)

				8'h16: key[0][0] <= ~pressed; // 1
		//		8'h00: key[0][1] <= ~pressed; // 
		//		8'h00: key[0][2] <= ~pressed; // 
				8'h58: key[0][3] <= ~pressed; // shiftlk (caps lock)
				8'h76: key[0][6] <= ~pressed; // escape
				8'h12: key[0][7] <= ~pressed; // shift (left shift)
				8'h59: key[0][7] <= ~pressed; // shift (right shift)

				8'h26: key[1][0] <= ~pressed; // 3
				8'h25: key[1][1] <= ~pressed; // 4
				8'h24: key[1][2] <= ~pressed; // E
				8'h22: key[1][3] <= ~pressed; // X
				8'h23: key[1][4] <= ~pressed; // D
				8'h21: key[1][5] <= ~pressed; // C
		//		8'h00: key[1][6] <= ~pressed; // 
		//		8'h00: key[1][7] <= ~pressed; // 

				8'h1E: key[2][0] <= ~pressed; // 2
				8'h15: key[2][1] <= ~pressed; // Q
				8'h1D: key[2][2] <= ~pressed; // W
				8'h1A: key[2][3] <= ~pressed; // Z
				8'h1B: key[2][4] <= ~pressed; // S
				8'h1C: key[2][5] <= ~pressed; // A
				8'h14: key[2][6] <= ~pressed; // control (left/right control)
		//		8'h00: key[2][7] <= ~pressed; // 

				8'h2E: key[3][0] <= ~pressed; // 5
				8'h2D: key[3][1] <= ~pressed; // R
				8'h2C: key[3][2] <= ~pressed; // T
				8'h2A: key[3][3] <= ~pressed; // V
				8'h34: key[3][4] <= ~pressed; // G
				8'h2B: key[3][5] <= ~pressed; // F
		//		8'h00: key[3][6] <= ~pressed; // 
		//		8'h00: key[3][7] <= ~pressed; // 

				8'h36: key[4][0] <= ~pressed; // 6
				8'h35: key[4][1] <= ~pressed; // Y
				8'h33: key[4][2] <= ~pressed; // H
				8'h29: key[4][3] <= ~pressed; // space
				8'h31: key[4][4] <= ~pressed; // N
				8'h32: key[4][5] <= ~pressed; // B
		//		8'h00: key[4][6] <= ~pressed; // 
		//		8'h00: key[4][7] <= ~pressed; // 

				8'h3D: key[5][0] <= ~pressed; // 7
				8'h3E: key[5][1] <= ~pressed; // 8
				8'h3C: key[5][2] <= ~pressed; // U
				8'h3A: key[5][3] <= ~pressed; // M
		//		8'h00: key[5][4] <= ~pressed; // 
				8'h3B: key[5][5] <= ~pressed; // J
		//		8'h00: key[5][6] <= ~pressed; // 
		//		8'h00: key[5][7] <= ~pressed; // 

				8'h46: key[6][0] <= ~pressed; // 9
				8'h43: key[6][1] <= ~pressed; // I
				8'h44: key[6][2] <= ~pressed; // O
				8'h41: key[6][3] <= ~pressed; // ,
		//		8'h00: key[6][4] <= ~pressed; // 
				8'h42: key[6][5] <= ~pressed; // K
		//		8'h00: key[6][6] <= ~pressed; // 
		//		8'h00: key[6][7] <= ~pressed; // 

				8'h45: key[7][0] <= ~pressed; // 0
				8'h4D: key[7][1] <= ~pressed; // P
				8'h4B: key[7][2] <= ~pressed; // L
				8'h49: key[7][3] <= ~pressed; // .
		//		8'h00: key[7][4] <= ~pressed; // 
				8'h4C: key[7][5] <= ~pressed; // ;
		//		8'h00: key[7][6] <= ~pressed; // 
		//		8'h00: key[7][7] <= ~pressed; // 

				8'h4E: key[8][0] <= ~pressed; // -
				8'h55: key[8][1] <= ~pressed; // @
				8'h54: key[8][2] <= ~pressed; // [
				8'h4A: key[8][3] <= ~pressed; // /
		//		8'h00: key[8][4] <= ~pressed; // 
				8'h52: key[8][5] <= ~pressed; // :
		//		8'h00: key[8][6] <= ~pressed; // 
		//		8'h00: key[8][7] <= ~pressed; // 

				8'h66: key[9][0] <= ~pressed; // backspace
				8'h5B: key[9][1] <= ~pressed; // ]
				8'h5A: key[9][3] <= ~pressed; // return
		//		8'h00: key[9][4] <= ~pressed; // 
		//		8'h00: key[9][6] <= ~pressed; // 
		//		8'h00: key[9][7] <= ~pressed; // 
			endcase
	end
end

//-------------------------------------------------------------------------------------------------

assign col = key[row];
assign esc = !key[0][6];

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
