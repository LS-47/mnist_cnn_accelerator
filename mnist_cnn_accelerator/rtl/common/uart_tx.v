`timescale 1ns/1ps
// 8-N-1 UART transmitter. Accept data when busy=0; done pulses after stop bit.
module uart_tx #(
    parameter integer CLOCK_HZ = 10_000_000,
    parameter integer BAUD = 115_200
) (
    input  wire       clk,
    input  wire       rstn,
    input  wire       start,
    input  wire [7:0] data_in,
    output reg        serial_out,
    output reg        busy,
    output reg        done
);
    localparam integer CLKS_PER_BIT = CLOCK_HZ / BAUD;
    localparam integer COUNT_W = $clog2(CLKS_PER_BIT + 1);
    localparam [1:0] TX_IDLE=2'd0, TX_START=2'd1, TX_DATA=2'd2, TX_STOP=2'd3;

    reg [1:0] state;
    reg [COUNT_W-1:0] count;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;

    always @(posedge clk) begin
        if (!rstn) begin
            state <= TX_IDLE;
            count <= 0;
            bit_index <= 0;
            shift_reg <= 0;
            serial_out <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                TX_IDLE: begin
                    serial_out <= 1'b1;
                    busy <= 1'b0;
                    count <= 0;
                    if (start) begin
                        shift_reg <= data_in;
                        bit_index <= 0;
                        serial_out <= 1'b0;
                        busy <= 1'b1;
                        state <= TX_START;
                    end
                end
                TX_START: begin
                    if (count == CLKS_PER_BIT-1) begin
                        count <= 0;
                        serial_out <= shift_reg[0];
                        state <= TX_DATA;
                    end else count <= count + 1'b1;
                end
                TX_DATA: begin
                    if (count == CLKS_PER_BIT-1) begin
                        count <= 0;
                        if (bit_index == 7) begin
                            serial_out <= 1'b1;
                            state <= TX_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            serial_out <= shift_reg[bit_index+1'b1];
                        end
                    end else count <= count + 1'b1;
                end
                TX_STOP: begin
                    if (count == CLKS_PER_BIT-1) begin
                        count <= 0;
                        state <= TX_IDLE;
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else count <= count + 1'b1;
                end
                default: state <= TX_IDLE;
            endcase
        end
    end
endmodule
