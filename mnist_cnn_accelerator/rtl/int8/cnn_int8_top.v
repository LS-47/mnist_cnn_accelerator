`timescale 1ns/1ps
// Serialized, one-MAC-per-cycle CNN for the requested XC7A100T architecture.
// Input pixels are unsigned bytes (pixel/255); hidden ReLU tensors are u8.
module cnn_int8_top(
    input wire clk, input wire rstn,
    input wire valid_in, input wire [7:0] pixel_in,
    output wire ready, output reg valid_out, output reg [3:0] class_out
);
    localparam IDLE=0, C1=1, P1=2, C2=3, P2=4, C3=5, P3=6, F1=7, F2=8, ARG=9;
    reg [3:0] state;
    assign ready = (state == IDLE);

    reg [7:0] raw1 [0:5407]; // 8 x 26 x 26
    reg [7:0] a1 [0:1351];   // 8 x 13 x 13
    reg [7:0] raw2 [0:1935]; // 16 x 11 x 11
    reg [7:0] a2 [0:399];    // 16 x 5 x 5 (odd edge cropped)
    reg [7:0] raw3 [0:287];  // 32 x 3 x 3
    reg [7:0] a3 [0:31];     // 32 x 1 x 1 (odd edge cropped)
    reg [7:0] h1 [0:15];
    reg signed [31:0] scores [0:9];

    reg signed [7:0] w1 [0:71], w2 [0:1151], w3 [0:4607];
    reg signed [7:0] wf1 [0:511], wf2 [0:159];
    reg signed [31:0] b1 [0:7], b2 [0:15], b3 [0:31], bf1 [0:15], bf2 [0:9];
    reg signed [63:0] m1 [0:0], m2 [0:0], m3 [0:0], mf1 [0:0];

    initial begin
        // Run simulation from the project root; weights are derived from the included checkpoint.
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/conv1_weight.mem",w1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/conv2_weight.mem",w2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/conv3_weight.mem",w3);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/fc1_weight.mem",wf1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/fc2_weight.mem",wf2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/conv1_bias.mem",b1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/conv2_bias.mem",b2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/conv3_bias.mem",b3);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/fc1_bias.mem",bf1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/fc2_bias.mem",bf2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/conv1_multiplier.mem",m1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/conv2_multiplier.mem",m2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/conv3_multiplier.mem",m3);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int8/fc1_multiplier.mem",mf1);
    end

    reg [9:0] image_count;
    reg [15:0] out_index, pool_index;
    reg [11:0] term_index;
    reg signed [31:0] acc;
    reg [3:0] arg_index;
    reg signed [31:0] best_score;

    integer conv_cout, conv_ih, conv_iw, conv_oh, conv_ow, conv_fanin;
    integer conv_oc, conv_oy, conv_ox, conv_ic, conv_ky, conv_kx, conv_addr;
    integer pool_cout, pool_ih, pool_iw, pool_oh, pool_ow;
    integer pool_oc, pool_oy, pool_ox, pool_addr;
    reg [9:0] image_read_addr;
    wire [7:0] image_read_data;
    reg [7:0] mac_activation;
    reg signed [7:0] mac_weight;
    reg signed [31:0] mac_bias;
    reg signed [63:0] layer_multiplier;
    wire signed [31:0] mac_product;
    wire signed [31:0] mac_acc_next = (term_index == 0) ? (mac_bias + mac_product) : (acc + mac_product);
    wire signed [31:0] scaled_activation;
    wire [7:0] relu_activation;
    reg [7:0] pool_v0, pool_v1, pool_v2, pool_v3;
    wire [7:0] pool_maximum;
    wire argmax_update;

    input_buffer_int8 input_buffer (
        .clk(clk), .write_enable((state == IDLE) && valid_in),
        .write_address(image_count), .write_data(pixel_in),
        .read_address(image_read_addr), .read_data(image_read_data)
    );
    mac_unit_int8 mac_unit (.activation(mac_activation), .weight(mac_weight), .product(mac_product));
    requantizer_int8 requantizer (.accumulator(mac_acc_next), .multiplier(layer_multiplier),
                                  .scaled_value(scaled_activation));
    relu_int8 relu_unit (.value_in(scaled_activation), .value_out(relu_activation));
    maxpool2x2_int8 maxpool_unit (.value0(pool_v0), .value1(pool_v1),
                                  .value2(pool_v2), .value3(pool_v3), .maximum(pool_maximum));
    argmax_step_int8 argmax_unit (.score(scores[arg_index]), .best_score(best_score),
                                  .update_best(argmax_update));

    // Shared MAC operand selection for all convolution and fully connected stages.
    always @* begin
        image_read_addr = 10'd0;
        mac_activation = 8'd0; mac_weight = 8'sd0; mac_bias = 32'sd0; layer_multiplier = 64'sd0;
        conv_cout=1; conv_ih=1; conv_iw=1; conv_oh=1; conv_ow=1; conv_fanin=1;
        conv_oc=0; conv_oy=0; conv_ox=0; conv_ic=0; conv_ky=0; conv_kx=0; conv_addr=0;
        if (state == C1) begin
            conv_cout=8; conv_ih=28; conv_iw=28; conv_oh=26; conv_ow=26; conv_fanin=9;
            conv_oc=out_index/(conv_oh*conv_ow); conv_oy=(out_index/conv_ow)%conv_oh; conv_ox=out_index%conv_ow;
            conv_ky=term_index/3; conv_kx=term_index%3; conv_addr=(conv_oy+conv_ky)*conv_iw+(conv_ox+conv_kx);
            image_read_addr=conv_addr; mac_activation=image_read_data; mac_weight=w1[conv_oc*9+term_index];
            mac_bias=b1[conv_oc]; layer_multiplier=m1[0];
        end else if (state == C2) begin
            conv_cout=16; conv_ih=13; conv_iw=13; conv_oh=11; conv_ow=11; conv_fanin=72;
            conv_oc=out_index/(conv_oh*conv_ow); conv_oy=(out_index/conv_ow)%conv_oh; conv_ox=out_index%conv_ow;
            conv_ic=term_index/9; conv_ky=(term_index%9)/3; conv_kx=term_index%3;
            conv_addr=conv_ic*conv_ih*conv_iw+(conv_oy+conv_ky)*conv_iw+(conv_ox+conv_kx);
            mac_activation=a1[conv_addr]; mac_weight=w2[conv_oc*conv_fanin+term_index];
            mac_bias=b2[conv_oc]; layer_multiplier=m2[0];
        end else if (state == C3) begin
            conv_cout=32; conv_ih=5; conv_iw=5; conv_oh=3; conv_ow=3; conv_fanin=144;
            conv_oc=out_index/(conv_oh*conv_ow); conv_oy=(out_index/conv_ow)%conv_oh; conv_ox=out_index%conv_ow;
            conv_ic=term_index/9; conv_ky=(term_index%9)/3; conv_kx=term_index%3;
            conv_addr=conv_ic*conv_ih*conv_iw+(conv_oy+conv_ky)*conv_iw+(conv_ox+conv_kx);
            mac_activation=a2[conv_addr]; mac_weight=w3[conv_oc*conv_fanin+term_index];
            mac_bias=b3[conv_oc]; layer_multiplier=m3[0];
        end else if (state == F1) begin
            conv_cout=16; conv_fanin=32; conv_oc=out_index; conv_ic=term_index;
            mac_activation=a3[conv_ic]; mac_weight=wf1[conv_oc*32+conv_ic];
            mac_bias=bf1[conv_oc]; layer_multiplier=mf1[0];
        end else if (state == F2) begin
            conv_cout=10; conv_fanin=16; conv_oc=out_index; conv_ic=term_index;
            mac_activation=h1[conv_ic]; mac_weight=wf2[conv_oc*16+conv_ic]; mac_bias=bf2[conv_oc];
        end

        pool_cout=1; pool_ih=1; pool_iw=1; pool_oh=1; pool_ow=1;
        pool_oc=0; pool_oy=0; pool_ox=0; pool_addr=0;
        pool_v0=0; pool_v1=0; pool_v2=0; pool_v3=0;
        if (state == P1) begin
            pool_cout=8; pool_ih=26; pool_iw=26; pool_oh=13; pool_ow=13;
            pool_oc=pool_index/(pool_oh*pool_ow); pool_oy=(pool_index/pool_ow)%pool_oh; pool_ox=pool_index%pool_ow;
            pool_addr=pool_oc*pool_ih*pool_iw+(2*pool_oy)*pool_iw+2*pool_ox;
            pool_v0=raw1[pool_addr]; pool_v1=raw1[pool_addr+1];
            pool_v2=raw1[pool_addr+pool_iw]; pool_v3=raw1[pool_addr+pool_iw+1];
        end else if (state == P2) begin
            pool_cout=16; pool_ih=11; pool_iw=11; pool_oh=5; pool_ow=5;
            pool_oc=pool_index/(pool_oh*pool_ow); pool_oy=(pool_index/pool_ow)%pool_oh; pool_ox=pool_index%pool_ow;
            pool_addr=pool_oc*pool_ih*pool_iw+(2*pool_oy)*pool_iw+2*pool_ox;
            pool_v0=raw2[pool_addr]; pool_v1=raw2[pool_addr+1];
            pool_v2=raw2[pool_addr+pool_iw]; pool_v3=raw2[pool_addr+pool_iw+1];
        end else if (state == P3) begin
            pool_cout=32; pool_ih=3; pool_iw=3; pool_oh=1; pool_ow=1;
            pool_oc=pool_index; pool_addr=pool_oc*pool_ih*pool_iw;
            pool_v0=raw3[pool_addr]; pool_v1=raw3[pool_addr+1];
            pool_v2=raw3[pool_addr+pool_iw]; pool_v3=raw3[pool_addr+pool_iw+1];
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            state <= IDLE; image_count <= 0; out_index <= 0; term_index <= 0;
            pool_index <= 0; acc <= 0; valid_out <= 0; class_out <= 0;
            arg_index <= 0; best_score <= -32'sd2147483647;
        end else begin
            valid_out <= 1'b0;
            case (state)
                IDLE: if (valid_in) begin
                    if (image_count == 783) begin
                        image_count <= 0; out_index <= 0; term_index <= 0; state <= C1;
                    end else image_count <= image_count + 1'b1;
                end
                C1, C2, C3: begin
                    if (term_index == conv_fanin-1) begin
                        if (state == C1) raw1[out_index] <= relu_activation;
                        else if (state == C2) raw2[out_index] <= relu_activation;
                        else raw3[out_index] <= relu_activation;
                        term_index <= 0; acc <= 0;
                        if (out_index == conv_cout*conv_oh*conv_ow-1) begin
                            out_index <= 0; pool_index <= 0;
                            if (state == C1) state <= P1;
                            else if (state == C2) state <= P2;
                            else state <= P3;
                        end else out_index <= out_index+1'b1;
                    end else begin term_index <= term_index+1'b1; acc <= mac_acc_next; end
                end
                P1, P2, P3: begin
                    if (state == P1) a1[pool_index] <= pool_maximum;
                    else if (state == P2) a2[pool_index] <= pool_maximum;
                    else a3[pool_index] <= pool_maximum;
                    if (pool_index == pool_cout*pool_oh*pool_ow-1) begin
                        pool_index <= 0; out_index <= 0; term_index <= 0;
                        if (state == P1) state <= C2;
                        else if (state == P2) state <= C3;
                        else state <= F1;
                    end else pool_index <= pool_index+1'b1;
                end
                F1: begin
                    if (term_index==31) begin
                        h1[out_index] <= relu_activation;
                        term_index<=0; acc<=0;
                        if (out_index==15) begin out_index<=0; state<=F2; end
                        else out_index<=out_index+1'b1;
                    end else begin term_index<=term_index+1'b1; acc<=mac_acc_next; end
                end
                F2: begin
                    if (term_index==15) begin
                        scores[out_index]<=mac_acc_next; term_index<=0; acc<=0;
                        if (out_index==9) begin arg_index<=0; best_score<=-32'sd2147483647; state<=ARG; end
                        else out_index<=out_index+1'b1;
                    end else begin term_index<=term_index+1'b1; acc<=mac_acc_next; end
                end
                ARG: begin
                    if (argmax_update) begin best_score<=scores[arg_index]; class_out<=arg_index; end
                    if (arg_index==9) begin valid_out<=1'b1; state<=IDLE; out_index<=0; end
                    else arg_index<=arg_index+1'b1;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
