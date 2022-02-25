//-------------------------------------------------------------------------------------------------
module clock
//-------------------------------------------------------------------------------------------------
(
	input  wire i, // 50.000 MHz
	output wire o  // 32.000 MHz
);
//-------------------------------------------------------------------------------------------------

IBUFG IBufg(.I(i), .O(ci));

PLL_BASE #
(
	.BANDWIDTH         ("OPTIMIZED"),
	.CLK_FEEDBACK      ("CLKFBOUT" ),
	.COMPENSATION      ("SYSTEM_SYNCHRONOUS"),
	.CLKOUT0_DUTY_CYCLE( 0.500),
	.CLKFBOUT_PHASE    ( 0.000),
	.CLKOUT0_PHASE     ( 0.000),
	.CLKIN_PERIOD      (20.000),
	.REF_JITTER        ( 0.010),
	.DIVCLK_DIVIDE     ( 1    ),
	.CLKFBOUT_MULT     (14    ),
	.CLKOUT0_DIVIDE    (25    )
)
Pll
(
	.RST               (1'b0),
	.CLKFBIN           (fb),
	.CLKFBOUT          (fb),
	.CLKIN             (ci),
	.CLKOUT0           (co),
	.CLKOUT1           (),
	.CLKOUT2           (),
	.CLKOUT3           (),
	.CLKOUT4           (),
	.CLKOUT5           (),
	.LOCKED            ()
);

BUFG  Bufg (.I(co), .O(o));

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
