// Single-image 28x28 byte input buffer with one stream write and one async read.
module input_buffer_int8 (
    input wire clk, input wire write_enable,
    input wire [9:0] write_address, input wire [7:0] write_data,
    input wire [9:0] read_address, output wire [7:0] read_data
);
    reg [7:0] memory [0:783];
    always @(posedge clk)
        if (write_enable) memory[write_address] <= write_data;
    assign read_data = memory[read_address];
endmodule
