// Signed Q31 requantization with round-to-nearest, ties-to-even.
module requantizer_int16 (
    input wire signed [31:0] accumulator,
    input wire signed [63:0] multiplier,
    output reg signed [31:0] scaled_value
);
    reg signed [95:0] product;
    reg [95:0] magnitude, quotient;
    reg [30:0] remainder;
    always @* begin
        product = accumulator * multiplier;
        magnitude = product[95] ? -product : product;
        quotient = magnitude >> 31;
        remainder = magnitude[30:0];
        if ((remainder > 31'h40000000) ||
            ((remainder == 31'h40000000) && quotient[0]))
            quotient = quotient + 1'b1;
        if (product[95]) begin
            if (quotient > 96'd2147483648) scaled_value = -32'sd2147483647 - 1'b1;
            else scaled_value = -$signed(quotient[31:0]);
        end else begin
            if (quotient > 96'd2147483647) scaled_value = 32'sd2147483647;
            else scaled_value = $signed(quotient[31:0]);
        end
    end
endmodule
