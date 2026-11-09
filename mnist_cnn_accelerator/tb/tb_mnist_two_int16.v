`timescale 1ns/1ps
module tb_mnist_two_int16;
    localparam PIXELS = 784;
    reg clk=0, rstn=0, valid_in=0;
    reg [15:0] pixel_in=0;
    wire ready, valid_out;
    wire [3:0] class_out;
    reg [15:0] pixels [0:PIXELS-1];
    integer i, cycles;
    cnn_int16_top dut(.clk(clk),.rstn(rstn),.valid_in(valid_in),.pixel_in(pixel_in),
                      .ready(ready),.valid_out(valid_out),.class_out(class_out));
    always #5 clk=~clk;
    initial begin
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/tb/data/mnist_two_pixels_int16.mem",pixels);
        repeat(5) @(negedge clk); rstn=1;
        for (i=0;i<PIXELS;i=i+1) begin
            @(negedge clk);
            while(!ready) @(negedge clk);
            pixel_in=pixels[i]; valid_in=1;
            @(negedge clk); valid_in=0;
        end
        cycles=0;
        while(!valid_out && cycles<1000000) begin @(negedge clk); cycles=cycles+1; end
        if(!valid_out) $display("FAIL: timeout waiting for INT16 CNN result");
        else $display("SIM_RESULT image=mnist_two.png precision=INT16 rtl_prediction=%0d",class_out);
        $finish;
    end
endmodule
