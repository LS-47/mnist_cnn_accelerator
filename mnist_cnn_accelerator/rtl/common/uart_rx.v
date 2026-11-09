`timescale 1ns/1ps
// 8-N-1 UART receiver. rx_valid pulses for one clock when a complete byte arrives.
module uart_rx #(
    parameter integer CLOCK_HZ = 10_000_000,
    parameter integer BAUD = 115_200
) (
    input  wire       clk,
    input  wire       rstn,
    input  wire       serial_in,
    output reg  [7:0] data_out,
    output reg        data_valid,
    output reg        framing_error
);
    localparam integer CLKS_PER_BIT = CLOCK_HZ / BAUD;
    localparam integer HALF_BIT = CLKS_PER_BIT / 2;
    localparam integer COUNT_W = $clog2(CLKS_PER_BIT + 1);
    localparam [1:0] RX_IDLE=2'd0, RX_START=2'd1, RX_DATA=2'd2, RX_STOP=2'd3;

    reg serial_meta, serial_sync;
    reg [1:0] state;
    reg [COUNT_W-1:0] count;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk) begin
        if (!rstn) begin
            serial_meta <= 1'b1;
            serial_sync <= 1'b1;
        end else begin
            serial_meta <= serial_in;
            serial_sync <= serial_meta;
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            state <= RX_IDLE;
            count <= 0;
            bit_index <= 0;
            shift_reg <= 0;
            data_out <= 0;
            data_valid <= 0;
            framing_error <= 0;
        end else begin
            data_valid <= 1'b0;
            framing_error <= 1'b0;
            case (state)
                RX_IDLE: begin
                    count <= 0;
                    if (!serial_sync) state <= RX_START;
                end
                RX_START: begin
                    if (count == HALF_BIT-1) begin
                        count <= 0;
                        if (!serial_sync) begin
                            bit_index <= 0;
                            state <= RX_DATA;
                        end else state <= RX_IDLE;
                    end else count <= count + 1'b1;
                end
                RX_DATA: begin
                    if (count == CLKS_PER_BIT-1) begin
                        count <= 0;
                        shift_reg[bit_index] <= serial_sync;
                        if (bit_index == 7) state <= RX_STOP;
                        else bit_index <= bit_index + 1'b1;
                    end else count <= count + 1'b1;
                end
                RX_STOP: begin
                    if (count == CLKS_PER_BIT-1) begin
                        count <= 0;
                        state <= RX_IDLE;
                        if (serial_sync) begin
                            data_out <= shift_reg;
                            data_valid <= 1'b1;
                        end else framing_error <= 1'b1;
                    end else count <= count + 1'b1;
                end
                default: state <= RX_IDLE;
            endcase
        end
    end
endmodule
