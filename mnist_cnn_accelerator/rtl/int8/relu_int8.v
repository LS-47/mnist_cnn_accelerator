// Clamp signed requantized value to an unsigned INT8 ReLU activation.
module relu_int8 (
    input wire signed [31:0] value_in,
    output reg [7:0] value_out
);
    always @* begin
        if (value_in < 0) value_out = 8'd0;
        else if (value_in > 255) value_out = 8'd255;
        else value_out = value_in[7:0];
    end
endmodule
