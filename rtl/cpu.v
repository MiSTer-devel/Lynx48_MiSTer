//-------------------------------------------------------------------------------------------------
// Z80: t80sv (rtl/t80sv, SystemVerilog T80 0250 by Rodimus, with the fixes from the SVI-328 core
// that pass every SingleStepTests/z80 case). Same ports as Kyp's cpu.v (T80pa).
//-------------------------------------------------------------------------------------------------
module cpu
//-------------------------------------------------------------------------------------------------
(
	input  wire       reset,
	input  wire       clock,
	input  wire       pe,
	input  wire       ne,
	output wire       rfsh,
	output wire       mreq,
	output wire       iorq,
	input  wire       irq,
	output wire       m1,
	output wire       rd,
	output wire       wr,
	input  wire[ 7:0] d,
	output wire[ 7:0] q,
	output wire[15:0] a
);

t80sv_T80pa #(.Mode(0)) Cpu
(
	.CLK      (clock  ),
	.CEN_p    (pe     ),
	.CEN_n    (ne     ),
	.RESET_n  (reset  ),
	.BUSRQ_n  (1'b1   ),
	.WAIT_n   (1'b1   ),
	.BUSAK_n  (       ),
	.HALT_n   (       ),
	.RFSH_n   (rfsh   ),
	.MREQ_n   (mreq   ),
	.IORQ_n   (iorq   ),
	.NMI_n    (1'b1   ),
	.INT_n    (irq    ),
	.M1_n     (m1     ),
	.RD_n     (rd     ),
	.WR_n     (wr     ),
	.A        (a      ),
	.DI       (d      ),
	.DO       (q      ),
	.REG      (       ),
	.DIRSet   (1'b0   ),
	.DIR      (212'd0 ),
	.OUT0     (1'b0   ),
	.R800_mode(1'b0   )
);

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
