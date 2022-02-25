//-------------------------------------------------------------------------------------------------
module video
//-------------------------------------------------------------------------------------------------
(
   input  wire      reset,
	input  wire      clock,
	input  wire      ce,
	input  wire      de,
	input  wire      altg,
	input  wire[7:0] di,
	output wire[8:0] rgb,
	output wire[1:0] b
);

//-------------------------------------------------------------------------------------------------



reg[2:0] hCount;
always @(posedge clock) if(!reset) hCount <= 3'd0; else if(ce) hCount <= hCount+1'd1;


reg[7:0] redInput;
wire redInputLoad = hCount == 3 && de;
always @(posedge clock) if(ce) if(redInputLoad) redInput <= di;


reg[7:0] blueInput;
wire blueInputLoad = hCount == 1 & de;
always @(posedge clock) if(ce) if(blueInputLoad) blueInput <= di;


reg[7:0] greenInput;
wire greenInputLoad = hCount == 5 & de;

always @(posedge clock) if(ce) if(greenInputLoad) greenInput <= di;

reg[7:0] redOutput;
reg[7:0] blueOutput;
reg[7:0] greenOutput;

wire dataOutputLoad = hCount == 7 && de;

always @(posedge clock) if(ce)
if(dataOutputLoad)
begin
	redOutput <= redInput;
	blueOutput <= blueInput;
	greenOutput <= greenInput;
end
else
begin
	redOutput <= { redOutput[6:0], 1'b0 };
	blueOutput <= { blueOutput[6:0], 1'b0 };
	greenOutput <= { greenOutput[6:0], 1'b0 };
end

//-------------------------------------------------------------------------------------------------

assign rgb = { {3{redOutput[7]}}, {3{greenOutput[7]}}, {3{blueOutput[7]}} };
assign b = { hCount[2], hCount[1]|(hCount[2]&~altg) };

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
