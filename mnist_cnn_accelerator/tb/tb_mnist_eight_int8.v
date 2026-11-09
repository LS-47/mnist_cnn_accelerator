`timescale 1ns/1ps
module tb_mnist_eight_int8;
    localparam PIXELS = 784;
    reg clk = 0;
    reg rstn = 0;
    reg valid_in = 0;
    reg [7:0] pixel_in = 0;
    wire ready, valid_out;
    wire [3:0] class_out;
    reg [7:0] pixels [0:PIXELS-1];
    integer i;
    integer cycles;

    cnn_int8_top dut (
        .clk(clk), .rstn(rstn), .valid_in(valid_in), .pixel_in(pixel_in),
        .ready(ready), .valid_out(valid_out), .class_out(class_out)
    );

    always #5 clk = ~clk;

    initial begin
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/tb/data/mnist_eight_pixels_int8.mem", pixels);
        repeat (5) @(negedge clk);
        rstn = 1;

        for (i = 0; i < PIXELS; i = i + 1) begin
            @(negedge clk);
            while (!ready) @(negedge clk);
            pixel_in = pixels[i];
            valid_in = 1;
            @(negedge clk);
            valid_in = 0;
        end

        cycles = 0;
        while (!valid_out && cycles < 1000000) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (!valid_out) begin
            $display("FAIL: timeout waiting for CNN result");
            $finish;
        end
        $display("SIM_RESULT image=mnist_eight.png expected_label=8 rtl_prediction=%0d", class_out);
        $finish;
    end
endmodule
