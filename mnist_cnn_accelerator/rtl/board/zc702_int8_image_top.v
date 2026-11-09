`timescale 1ns/1ps
module zc702_int8_image_top(
    input wire SYSCLK_P, input wire SYSCLK_N, input wire reset_btn,
    output wire [5:0] led
);
    wire clk, locked, core_rstn, ready, valid_out;
    wire [3:0] class_out;
    reg valid_in;
    reg [7:0] pixel_in;
    reg [9:0] pixel_index;
    reg [1:0] state;
    reg [3:0] result;
    reg done;
    reg [7:0] image_mem [0:783];
    localparam SEND=2'd0, WAIT_RESULT=2'd1, SHOW=2'd2;
    initial $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/tb/data/mnist_eight_pixels_int8.mem", image_mem);
    // ZC702 SW5 is active-high: pressing it asserts reset; releasing it runs the demo.
    zc702_clock_gen clock_gen(.clk_in1_p(SYSCLK_P),.clk_in1_n(SYSCLK_N),.reset(reset_btn),.clk_out1(clk),.locked(locked));
    reset_sync resetter(.clk(clk),.async_resetn(~reset_btn & locked),.resetn(core_rstn));
    cnn_int8_top cnn(.clk(clk),.rstn(core_rstn),.valid_in(valid_in),.pixel_in(pixel_in),.ready(ready),.valid_out(valid_out),.class_out(class_out));
    always @(posedge clk) begin
        if (!core_rstn) begin state<=SEND; pixel_index<=0; valid_in<=0; pixel_in<=0; result<=0; done<=0; end
        else begin
            valid_in<=0;
            case(state)
                SEND: if (ready) begin
                    pixel_in<=image_mem[pixel_index]; valid_in<=1;
                    if (pixel_index==10'd783) begin pixel_index<=0; state<=WAIT_RESULT; end
                    else pixel_index<=pixel_index+1'b1;
                end
                WAIT_RESULT: if (valid_out) begin result<=class_out; done<=1; state<=SHOW; end
                SHOW: begin end
                default: state<=SEND;
            endcase
        end
    end
    assign led={done,1'b0,result};
endmodule
