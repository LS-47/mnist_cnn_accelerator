// Unsigned INT8 activation x signed INT8 weight, widened to signed INT32.
module mac_unit_int8 (
    input wire [7:0] activation,
    input wire signed [7:0] weight,
    output wire signed [31:0] product
);
    wire signed [16:0] activation_ext = {9'd0, activation};
    wire signed [16:0] weight_ext = {{9{weight[7]}}, weight};
    wire signed [33:0] product_full = activation_ext * weight_ext;
    assign product = {{15{product_full[16]}}, product_full[16:0]};
endmodule
