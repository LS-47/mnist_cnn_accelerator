`timescale 1ns/1ps
// Asynchronous assertion with two-clock-cycle synchronous reset release.
module reset_sync (
    input  wire clk,
    input  wire async_resetn,
    output wire resetn
);
    reg [1:0] pipe;
    always @(posedge clk or negedge async_resetn) begin
        if (!async_resetn) pipe <= 2'b00;
        else pipe <= {pipe[0], 1'b1};
    end
    assign resetn = pipe[1];
endmodule
