`timescale 1ns/1ps
// ZC702 PL interface. UART is brought in through J62 using an external
// 2.5-V-compatible USB-UART adapter; the onboard USB-UART belongs to the PS.
module zc702_int16_top (
    input  wire       SYSCLK_P,
    input  wire       SYSCLK_N,
    input  wire       resetn,
    input  wire       uart_rxd,
    output wire       uart_txd,
    output wire [5:0] led
);
    wire core_clk, clk_locked;
    wire core_rstn;
    zc702_clock_gen clock_gen (
        .clk_in1_p(SYSCLK_P), .clk_in1_n(SYSCLK_N),
        .reset(~resetn), .clk_out1(core_clk), .locked(clk_locked)
    );
    reset_sync core_reset_sync (
        .clk(core_clk), .async_resetn(resetn & clk_locked), .resetn(core_rstn)
    );

    wire [7:0] rx_data;
    wire rx_valid, rx_frame_error;
    uart_rx #(.CLOCK_HZ(10_000_000), .BAUD(115_200)) receive_uart (
        .clk(core_clk), .rstn(core_rstn), .serial_in(uart_rxd),
        .data_out(rx_data), .data_valid(rx_valid), .framing_error(rx_frame_error)
    );

    localparam [1:0] LOAD_IMAGE=2'd0, WAIT_INFERENCE=2'd1, WAIT_UART=2'd2;
    reg [1:0] state;
    reg [9:0] pixel_count;
    reg [15:0] core_pixel;
    reg core_valid;
    reg [7:0] tx_data;
    reg tx_start;
    wire tx_busy, tx_done;
    wire core_ready, core_valid_out;
    wire [3:0] core_class;
    reg [3:0] shown_class;
    reg result_seen;

    cnn_int16_top inference_core (
        .clk(core_clk), .rstn(core_rstn), .valid_in(core_valid),
        .pixel_in(core_pixel), .ready(core_ready),
        .valid_out(core_valid_out), .class_out(core_class)
    );

    uart_tx #(.CLOCK_HZ(10_000_000), .BAUD(115_200)) transmit_uart (
        .clk(core_clk), .rstn(core_rstn), .start(tx_start), .data_in(tx_data),
        .serial_out(uart_txd), .busy(tx_busy), .done(tx_done)
    );

    always @(posedge core_clk) begin
        if (!core_rstn) begin
            state <= LOAD_IMAGE;
            pixel_count <= 0;
            core_pixel <= 0;
            core_valid <= 0;
            tx_data <= 0;
            tx_start <= 0;
            shown_class <= 0;
            result_seen <= 0;
        end else begin
            core_valid <= 1'b0;
            tx_start <= 1'b0;
            case (state)
                LOAD_IMAGE: begin
                    if (rx_valid && core_ready) begin
                        // Match the INT16 Python reference's rounded input scale.
                        core_pixel <= (({12'd0, rx_data} * 20'd3640) + 20'd127) / 20'd255;
                        core_valid <= 1'b1;
                        if (pixel_count == 10'd783) begin
                            pixel_count <= 0;
                            state <= WAIT_INFERENCE;
                        end else pixel_count <= pixel_count + 1'b1;
                    end
                end
                WAIT_INFERENCE: begin
                    if (core_valid_out) begin
                        shown_class <= core_class;
                        result_seen <= 1'b1;
                        tx_data <= 8'h30 + {4'b0000, core_class};
                        tx_start <= 1'b1;
                        state <= WAIT_UART;
                    end
                end
                WAIT_UART: begin
                    if (tx_done) state <= LOAD_IMAGE;
                end
                default: state <= LOAD_IMAGE;
            endcase
        end
    end

    assign led = {result_seen, (state == WAIT_INFERENCE), shown_class};
endmodule
