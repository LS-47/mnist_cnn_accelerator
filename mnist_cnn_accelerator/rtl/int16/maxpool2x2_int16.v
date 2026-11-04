// Combinational max of a 2x2 window of unsigned INT16 activations.
module maxpool2x2_int16 (
    input wire [15:0] value0, input wire [15:0] value1,
    input wire [15:0] value2, input wire [15:0] value3,
    output reg [15:0] maximum
);
    always @* begin
        maximum = value0;
        if (value1 > maximum) maximum = value1;
        if (value2 > maximum) maximum = value2;
        if (value3 > maximum) maximum = value3;
    end
endmodule
