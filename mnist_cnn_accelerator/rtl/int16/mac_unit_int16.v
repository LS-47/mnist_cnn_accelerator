// Unsigned INT16 activation x signed INT16 weight, signed INT32 product.
module mac_unit_int16 (
    input wire [15:0] activation,
    input wire signed [15:0] weight,
    output wire signed [31:0] product
);
    wire signed [31:0] activation_ext = {16'd0, activation};
    wire signed [31:0] weight_ext = {{16{weight[15]}}, weight};
    wire signed [63:0] product_full = activation_ext * weight_ext;
    assign product = product_full[31:0];
endmodule
