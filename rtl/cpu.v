//-------------------------------------------------------------------------------------------------
module cpu
//-------------------------------------------------------------------------------------------------
(
	input  wire       reset,
	input  wire       clock,
	input  wire       cep,
	input  wire       cen,
	input  wire       int_n,
	output wire       halt_n,
	output wire       mreq,
	output wire       iorq,
	output wire       wr,
	input  wire[ 7:0] di,
	output wire[ 7:0] data_out,
	output wire[15:0] a,
	input wire [15:0] dir,
	input wire dirset 
);
/*
module tv80e (
  // Outputs
  m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n, A, dout,
  // Inputs
  reset_n, clk, cen, wait_n, int_n, nmi_n, busrq_n, di
  );

*/
tv80e Cpu
(
	.clk (clock),
	.cen (cep),
	.reset_n(reset),
	.busrq_n(1'b1 ),
	.wait_n(1'b1 ),
	.halt_n(halt_n ),
	.mreq_n(mreq ),
	.iorq_n(iorq ),
	.nmi_n(1'b1 ),
	.int_n(int_n),
	.wr_n(wr   ),
	.A      (a    ),
	.di(di   ),
	.dout(data_out),
	.dir (dir),
	.dirset (dirset)
);

/*
T80pa Cpu
(
	.CLK    (clock),
	.CEN_p  (cep  ),
	.CEN_n  (cen  ),
	.RESET_n(reset),
	.BUSRQ_n(1'b1 ),
	.WAIT_n (1'b1 ),
	.BUSAK_n(     ),
	.HALT_n (     ),
	.RFSH_n (     ),
	.MREQ_n (mreq ),
	.IORQ_n (iorq ),
	.NMI_n  (1'b1 ),
	.INT_n  (int_n),
	.M1_n   (     ),
	.RD_n   (     ),
	.WR_n   (wr   ),
	.A      (a    ),
	.DI     (di   ),
	.DO     (data_out),
	.OUT0   (1'b0 ),
	.REG    (     ),
	.DIRSet (1'b0 ),
	.DIR    (212'd0)
);
*/
//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
