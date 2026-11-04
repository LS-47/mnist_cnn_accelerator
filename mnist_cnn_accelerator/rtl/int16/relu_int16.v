// ReLU and calibrated layer-specific unsigned INT16 activation clamp.
module relu_int16 (
    input wire signed [31:0] value_in,
    input wire [15:0] max_code,
    output reg [15:0] value_out
);
    always @* begin
        if (value_in < 0) value_out = 16'd0;
        else if (value_in > $signed({1'b0, max_code})) value_out = max_code;
        else value_out = value_in[15:0];
    end
endmodule
