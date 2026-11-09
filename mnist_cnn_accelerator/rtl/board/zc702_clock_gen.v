`timescale 1ns/1ps
// ZC702 200 MHz differential oscillator -> 10 MHz PL clock.
// MMCM VCO = 200 MHz * 4 / 1 = 800 MHz; output = 800 MHz / 80 = 10 MHz.
module zc702_clock_gen (
    input  wire clk_in1_p,
    input  wire clk_in1_n,
    input  wire reset,
    output wire clk_out1,
    output wire locked
);
    wire clk_in;
    wire clkfb_mmcm;
    wire clkfb_global;
    wire clkout0_mmcm;

    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IBUF_LOW_PWR("FALSE")
    ) sysclk_ibuf (
        .I(clk_in1_p),
        .IB(clk_in1_n),
        .O(clk_in)
    );

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(4.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKIN1_PERIOD(5.000),
        .CLKOUT0_DIVIDE_F(80.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_PHASE(0.000),
        .DIVCLK_DIVIDE(1),
        .STARTUP_WAIT("FALSE")
    ) sysclk_mmcm (
        .CLKIN1(clk_in),
        .CLKFBIN(clkfb_global),
        .RST(reset),
        .PWRDWN(1'b0),
        .CLKFBOUT(clkfb_mmcm),
        .CLKOUT0(clkout0_mmcm),
        .LOCKED(locked)
    );

    BUFG feedback_buf (
        .I(clkfb_mmcm),
        .O(clkfb_global)
    );

    BUFG core_clock_buf (
        .I(clkout0_mmcm),
        .O(clk_out1)
    );
endmodule
