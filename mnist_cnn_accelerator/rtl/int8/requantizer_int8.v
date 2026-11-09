// Signed Q31 requantization with round-to-nearest, ties-to-even.
module requantizer_int8 (
    input wire signed [31:0] accumulator,
    input wire [23:0] multiplier,
    output reg signed [31:0] scaled_value
);
    wire signed [55:0] accumulator_ext = {{24{accumulator[31]}}, accumulator};
    wire signed [55:0] multiplier_ext = {32'd0, multiplier};
    wire signed [55:0] product = accumulator_ext * multiplier_ext;
    reg [55:0] magnitude, quotient;
    reg [30:0] remainder;
    always @* begin
        magnitude = product[55] ? (~product + 1'b1) : product;
        quotient = magnitude >> 31;
        remainder = magnitude[30:0];
        if ((remainder > 31'h40000000) ||
            ((remainder == 31'h40000000) && quotient[0]))
            quotient = quotient + 1'b1;
        if (product[55]) begin
            if (quotient > 56'd2147483648) scaled_value = -32'sd2147483647 - 1'b1;
            else scaled_value = -$signed(quotient[31:0]);
        end else begin
            if (quotient > 56'd2147483647) scaled_value = 32'sd2147483647;
            else scaled_value = $signed(quotient[31:0]);
        end
    end
endmodule
