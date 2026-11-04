// Single-image buffer for calibrated unsigned INT16 pixel codes.
module input_buffer_int16 (
    input wire clk, input wire write_enable,
    input wire [9:0] write_address, input wire [15:0] write_data,
    input wire [9:0] read_address, output wire [15:0] read_data
);
    reg [15:0] memory [0:783];
    always @(posedge clk)
        if (write_enable) memory[write_address] <= write_data;
    assign read_data = memory[read_address];
endmodule
