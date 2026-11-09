`timescale 1ns/1ps
// Serialized INT16 CNN. Activations use unsigned 16-bit storage; calibrated
// layer limits preserve signed INT32 accumulator headroom.
module cnn_int16_top(
    input wire clk, input wire rstn,
    input wire valid_in, input wire [15:0] pixel_in,
    output wire ready, output reg valid_out, output reg [3:0] class_out
);
    localparam IDLE=0, C1=1, P1=2, C2=3, P2=4, C3=5, P3=6, F1=7, F2=8, ARG=9;
    reg [3:0] state;
    assign ready = (state == IDLE);

    reg [15:0] raw1 [0:5407]; // 8 x 26 x 26
    reg [15:0] a1 [0:1351];   // 8 x 13 x 13
    reg [15:0] raw2 [0:1935]; // 16 x 11 x 11
    reg [15:0] a2 [0:399];    // 16 x 5 x 5 (odd edge cropped)
    reg [15:0] raw3 [0:287];  // 32 x 3 x 3
    reg [15:0] a3 [0:31];     // 32 x 1 x 1 (odd edge cropped)
    reg [15:0] h1 [0:15];
    reg signed [31:0] scores [0:9];

    reg signed [15:0] w1 [0:71], w2 [0:1151], w3 [0:4607];
    reg signed [15:0] wf1 [0:511], wf2 [0:159];
    reg signed [31:0] b1 [0:7], b2 [0:15], b3 [0:31], bf1 [0:15], bf2 [0:9];
    reg [23:0] m1 [0:0], m2 [0:0], m3 [0:0], mf1 [0:0];

    initial begin
        // Run simulation from the project root; weights are derived from the included checkpoint.
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/conv1_weight.mem",w1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/conv2_weight.mem",w2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/conv3_weight.mem",w3);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/fc1_weight.mem",wf1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/fc2_weight.mem",wf2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/conv1_bias.mem",b1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/conv2_bias.mem",b2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/conv3_bias.mem",b3);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/fc1_bias.mem",bf1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/fc2_bias.mem",bf2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/conv1_multiplier.mem",m1);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/conv2_multiplier.mem",m2);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/conv3_multiplier.mem",m3);
        $readmemh("C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/weights/int16/fc1_multiplier.mem",mf1);
    end

    reg [9:0] image_count;
    reg [15:0] out_index, pool_index;
    reg [11:0] term_index;
    reg [1:0] term_x, term_y;
    reg [3:0] term_channel;
    reg [4:0] out_x, out_y;
    reg [5:0] out_channel;
    reg [3:0] pool_x, pool_y;
    reg [4:0] pool_channel;
    reg signed [31:0] acc;
    reg [3:0] arg_index;
    reg signed [31:0] best_score;

    reg [4:0] conv_oc;
    reg [4:0] conv_ic;
    reg [10:0] conv_addr;
    reg [12:0] pool_addr;
    reg [12:0] weight_addr;
    reg [9:0] image_read_addr;
    wire [15:0] image_read_data;
    reg [15:0] mac_activation;
    reg signed [15:0] mac_weight;
    reg signed [31:0] mac_bias;
    reg [23:0] layer_multiplier;
    reg [15:0] activation_max_code;
    wire signed [31:0] mac_product;
    wire signed [31:0] mac_acc_next = (term_index == 0) ? (mac_bias + mac_product) : (acc + mac_product);
    wire signed [31:0] scaled_activation;
    wire [15:0] relu_activation;
    reg [15:0] pool_v0, pool_v1, pool_v2, pool_v3;
    wire [15:0] pool_maximum;
    wire argmax_update;

    input_buffer_int16 input_buffer (
        .clk(clk), .write_enable((state == IDLE) && valid_in),
        .write_address(image_count), .write_data(pixel_in),
        .read_address(image_read_addr), .read_data(image_read_data)
    );
    mac_unit_int16 mac_unit (.activation(mac_activation), .weight(mac_weight), .product(mac_product));
    requantizer_int16 requantizer (.accumulator(mac_acc_next), .multiplier(layer_multiplier),
                                   .scaled_value(scaled_activation));
    relu_int16 relu_unit (.value_in(scaled_activation), .max_code(activation_max_code),
                          .value_out(relu_activation));
    maxpool2x2_int16 maxpool_unit (.value0(pool_v0), .value1(pool_v1),
                                   .value2(pool_v2), .value3(pool_v3), .maximum(pool_maximum));
    argmax_step_int16 argmax_unit (.score(scores[arg_index]), .best_score(best_score),
                                   .update_best(argmax_update));

    // One physical MAC selects the active convolution or FC operands each cycle.
    always @* begin
        image_read_addr=10'd0;
        mac_activation=16'd0; mac_weight=16'sd0; mac_bias=32'sd0;
        layer_multiplier=24'd0; activation_max_code=16'd0;
        conv_oc=0; conv_ic=0; conv_addr=0; weight_addr=0;
        if (state == C1) begin
            conv_oc=out_channel;
            conv_addr=(out_y+term_y)*28+(out_x+term_x);
            weight_addr=conv_oc*9+term_index;
            image_read_addr=conv_addr; mac_activation=image_read_data; mac_weight=w1[weight_addr];
            mac_bias=b1[conv_oc]; layer_multiplier=m1[0]; activation_max_code=16'd455;
        end else if (state == C2) begin
            conv_oc=out_channel;
            conv_ic=term_channel;
            conv_addr=term_channel*169+(out_y+term_y)*13+(out_x+term_x);
            weight_addr=conv_oc*72+term_index;
            mac_activation=a1[conv_addr]; mac_weight=w2[weight_addr];
            mac_bias=b2[conv_oc]; layer_multiplier=m2[0]; activation_max_code=16'd227;
        end else if (state == C3) begin
            conv_oc=out_channel;
            conv_ic=term_channel;
            conv_addr=term_channel*25+(out_y+term_y)*5+(out_x+term_x);
            weight_addr=conv_oc*144+term_index;
            mac_activation=a2[conv_addr]; mac_weight=w3[weight_addr];
            mac_bias=b3[conv_oc]; layer_multiplier=m3[0]; activation_max_code=16'd1023;
        end else if (state == F1) begin
            conv_oc=out_index; conv_ic=term_index;
            weight_addr=out_index*32+term_index;
            mac_activation=a3[conv_ic]; mac_weight=wf1[weight_addr];
            mac_bias=bf1[conv_oc]; layer_multiplier=mf1[0]; activation_max_code=16'd2047;
        end else if (state == F2) begin
            conv_oc=out_index; conv_ic=term_index;
            weight_addr=out_index*16+term_index;
            mac_activation=h1[conv_ic]; mac_weight=wf2[weight_addr]; mac_bias=bf2[conv_oc];
        end

        pool_addr=0;
        pool_v0=0; pool_v1=0; pool_v2=0; pool_v3=0;
        if (state == P1) begin
            pool_addr=pool_channel*676+(2*pool_y)*26+2*pool_x;
            pool_v0=raw1[pool_addr]; pool_v1=raw1[pool_addr+1];
            pool_v2=raw1[pool_addr+26]; pool_v3=raw1[pool_addr+27];
        end else if (state == P2) begin
            pool_addr=pool_channel*121+(2*pool_y)*11+2*pool_x;
            pool_v0=raw2[pool_addr]; pool_v1=raw2[pool_addr+1];
            pool_v2=raw2[pool_addr+11]; pool_v3=raw2[pool_addr+12];
        end else if (state == P3) begin
            pool_addr=pool_channel*9;
            pool_v0=raw3[pool_addr]; pool_v1=raw3[pool_addr+1];
            pool_v2=raw3[pool_addr+3]; pool_v3=raw3[pool_addr+4];
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            state <= IDLE; image_count <= 0; out_index <= 0; term_index <= 0;
            pool_index <= 0; acc <= 0; valid_out <= 0; class_out <= 0;
            term_x <= 0; term_y <= 0; term_channel <= 0;
            out_x <= 0; out_y <= 0; out_channel <= 0;
            pool_x <= 0; pool_y <= 0; pool_channel <= 0;
            arg_index <= 0; best_score <= -32'sd2147483647;
        end else begin
            valid_out <= 1'b0;
            case (state)
                IDLE: if (valid_in) begin
                    if (image_count == 783) begin
                        image_count <= 0; out_index <= 0; term_index <= 0;
                        term_x <= 0; term_y <= 0; term_channel <= 0;
                        out_x <= 0; out_y <= 0; out_channel <= 0; state <= C1;
                    end else image_count <= image_count + 1'b1;
                end
                C1, C2, C3: begin
                    if ((state == C1 && term_index == 8) ||
                        (state == C2 && term_index == 71) ||
                        (state == C3 && term_index == 143)) begin
                        if (state == C1) raw1[out_index] <= relu_activation;
                        else if (state == C2) raw2[out_index] <= relu_activation;
                        else raw3[out_index] <= relu_activation;
                        term_index <= 0; acc <= 0;
                        term_x <= 0; term_y <= 0; term_channel <= 0;
                        if ((state == C1 && out_index == 16'd5407) ||
                            (state == C2 && out_index == 16'd1935) ||
                            (state == C3 && out_index == 16'd287)) begin
                            out_index <= 0; pool_index <= 0;
                            out_x <= 0; out_y <= 0; out_channel <= 0;
                            pool_x <= 0; pool_y <= 0; pool_channel <= 0;
                            if (state == C1) state <= P1;
                            else if (state == C2) state <= P2;
                            else state <= P3;
                        end else begin
                            out_index <= out_index+1'b1;
                            if (state == C1) begin
                                if (out_x == 25) begin
                                    out_x <= 0;
                                    if (out_y == 25) begin out_y <= 0; out_channel <= out_channel+1'b1; end
                                    else out_y <= out_y+1'b1;
                                end else out_x <= out_x+1'b1;
                            end else if (state == C2) begin
                                if (out_x == 10) begin
                                    out_x <= 0;
                                    if (out_y == 10) begin out_y <= 0; out_channel <= out_channel+1'b1; end
                                    else out_y <= out_y+1'b1;
                                end else out_x <= out_x+1'b1;
                            end else begin
                                if (out_x == 2) begin
                                    out_x <= 0;
                                    if (out_y == 2) begin out_y <= 0; out_channel <= out_channel+1'b1; end
                                    else out_y <= out_y+1'b1;
                                end else out_x <= out_x+1'b1;
                            end
                        end
                    end else begin
                        term_index <= term_index+1'b1; acc <= mac_acc_next;
                        if (term_x == 2) begin
                            term_x <= 0;
                            if (term_y == 2) begin
                                term_y <= 0;
                                if (state != C1) term_channel <= term_channel+1'b1;
                            end else term_y <= term_y+1'b1;
                        end else term_x <= term_x+1'b1;
                    end
                end
                P1, P2, P3: begin
                    if (state == P1) a1[pool_index] <= pool_maximum;
                    else if (state == P2) a2[pool_index] <= pool_maximum;
                    else a3[pool_index] <= pool_maximum;
                    if ((state == P1 && pool_index == 16'd1351) ||
                        (state == P2 && pool_index == 16'd399) ||
                        (state == P3 && pool_index == 16'd31)) begin
                        pool_index <= 0; out_index <= 0; term_index <= 0;
                        pool_x <= 0; pool_y <= 0; pool_channel <= 0;
                        out_x <= 0; out_y <= 0; out_channel <= 0;
                        if (state == P1) state <= C2;
                        else if (state == P2) state <= C3;
                        else state <= F1;
                    end else begin
                        pool_index <= pool_index+1'b1;
                        if (state == P1) begin
                            if (pool_x == 12) begin
                                pool_x <= 0;
                                if (pool_y == 12) begin pool_y <= 0; pool_channel <= pool_channel+1'b1; end
                                else pool_y <= pool_y+1'b1;
                            end else pool_x <= pool_x+1'b1;
                        end else if (state == P2) begin
                            if (pool_x == 4) begin
                                pool_x <= 0;
                                if (pool_y == 4) begin pool_y <= 0; pool_channel <= pool_channel+1'b1; end
                                else pool_y <= pool_y+1'b1;
                            end else pool_x <= pool_x+1'b1;
                        end else begin
                            pool_x <= 0; pool_y <= 0; pool_channel <= pool_channel+1'b1;
                        end
                    end
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
