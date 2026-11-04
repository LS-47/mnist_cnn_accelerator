`timescale 1ns/1ps
module tb_cnn_int16;
`ifndef NUM_IMAGES
`define NUM_IMAGES 100
`endif
    localparam N_IMAGES=`NUM_IMAGES;
    localparam PIXELS_PER_IMAGE=784;
    reg clk=0, rstn=0, valid_in=0;
    reg [15:0] pixel_in=0;
    wire ready, valid_out;
    wire [3:0] class_out;
    reg [15:0] pixels [0:N_IMAGES*PIXELS_PER_IMAGE-1];
    reg [3:0] expected [0:N_IMAGES-1];
    reg [3:0] labels [0:N_IMAGES-1];
    integer image_idx, pix_idx, errors;
    cnn_int16_top dut(.clk(clk),.rstn(rstn),.valid_in(valid_in),.pixel_in(pixel_in),
                      .ready(ready),.valid_out(valid_out),.class_out(class_out));
    always #5 clk=~clk;
    initial begin
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/tb/data/mnist100_pixels_int16.mem",pixels);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/tb/data/mnist100_expected_int16.mem",expected);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/tb/data/mnist100_labels.mem",labels);
        errors=0;
        repeat(5) @(negedge clk); rstn=1;
        for (image_idx=0; image_idx<N_IMAGES; image_idx=image_idx+1) begin
            for (pix_idx=0; pix_idx<PIXELS_PER_IMAGE; pix_idx=pix_idx+1) begin
                @(negedge clk);
                while (!ready) @(negedge clk);
                valid_in=1; pixel_in=pixels[image_idx*PIXELS_PER_IMAGE+pix_idx];
                @(negedge clk); valid_in=0;
            end
            wait(valid_out===1'b1);
            $display("INT16 image %0d: RTL=%0d Python=%0d MNIST_label=%0d",
                     image_idx,class_out,expected[image_idx],labels[image_idx]);
            if (class_out !== expected[image_idx]) begin
                $display("Mismatch image %0d: RTL=%0d Python INT16=%0d",image_idx,class_out,expected[image_idx]);
                errors=errors+1;
            end
            if ((image_idx%10)==9) $display("INT16 completed %0d/%0d images",image_idx+1,N_IMAGES);
        end
        if (errors==0) $display("PASS: all %0d INT16 RTL predictions match Python reference",N_IMAGES);
        else $display("FAIL: %0d/%0d INT16 mismatches",errors,N_IMAGES);
        $finish;
    end
endmodule
