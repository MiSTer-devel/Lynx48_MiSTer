//-------------------------------------------------------------------------------------------------
module spr
//-------------------------------------------------------------------------------------------------
#
(
	parameter DW = 8,
	parameter AW = 14
)
(
	input  wire         clock_a,
	//input  wire         clock_b,
	input  wire         ce_a,
	input  wire         ce_b,
	input  wire         we_a,
	input  wire         we_b,
	input  wire[   7:0] di_a,
	input  wire[   7:0] di_b,
	output reg [   7:0] do_a,
	output reg [   7:0] do_b,
	input  wire[AW-1:0] a_a,
	input  wire[AW-1:0] a_b
);
//-------------------------------------------------------------------------------------------------

reg[7:0] d[(2**AW)-1:0];

always @(posedge clock_a) if(ce_a) if(!we_a) d[a_a] <= di_a; else do_a <= d[a_a];
always @(posedge clock_a) if(ce_b) if(!we_b) d[a_b] <= di_b; else do_b <= d[a_b];

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
