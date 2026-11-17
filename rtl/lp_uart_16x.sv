`timescale 1ns / 1ps

// ============================================================================
// 1. Low-Power Baud-Tick Generator (Single-Clock Enable + Idle Counter Gating)
// ============================================================================
module lp_clk_gen (
    input  logic        clk,
    input  logic        rst,
    input  logic [16:0] baud,
    input  logic        tx_active,
    input  logic        rx_active,
    output logic        tx_tick,
    output logic        rx_tick
);
    logic [11:0] rx_max;
    logic [14:0] tx_max;
    logic [11:0] rx_count;
    logic [14:0] tx_count;

    // Full-period divisors (single-cycle tick enables replace 50%-duty ripple clocks)
    always_comb begin
        case (baud)
            17'd4800   : begin rx_max = 12'd1301; tx_max = 15'd20832; end
            17'd9600   : begin rx_max = 12'd650;  tx_max = 15'd10416; end
            17'd14400  : begin rx_max = 12'd433;  tx_max = 15'd6944;  end
            17'd19200  : begin rx_max = 12'd325;  tx_max = 15'd5208;  end
            17'd38400  : begin rx_max = 12'd162;  tx_max = 15'd2604;  end
            17'd57600  : begin rx_max = 12'd108;  tx_max = 15'd1736;  end
            17'd115200 : begin rx_max = 12'd53;   tx_max = 15'd868;   end
            17'd128000 : begin rx_max = 12'd48;   tx_max = 15'd781;   end
            default    : begin rx_max = 12'd650;  tx_max = 15'd10416; end
        endcase
    end

    // Clock-enable gated RX 16x oversampling tick
    always_ff @(posedge clk) begin
        if (rst || !rx_active) begin
            rx_count <= '0;
            rx_tick  <= 1'b0;
        end else if (rx_count >= rx_max) begin
            rx_count <= '0;
            rx_tick  <= 1'b1;
        end else begin
            rx_count <= rx_count + 1'b1;
            rx_tick  <= 1'b0;
        end
    end

    // Clock-enable gated TX baud tick
    always_ff @(posedge clk) begin
        if (rst || !tx_active) begin
            tx_count <= '0;
            tx_tick  <= 1'b0;
        end else if (tx_count >= tx_max) begin
            tx_count <= '0;
            tx_tick  <= 1'b1;
        end else begin
            tx_count <= tx_count + 1'b1;
            tx_tick  <= 1'b0;
        end
    end
endmodule

// ============================================================================
// 2. Synchronous Low-Power UART TX
// ============================================================================
module lp_uart_tx (
    input  logic       clk,
    input  logic       tx_tick,
    input  logic       tx_start,
    input  logic       rst,
    input  logic [7:0] tx_data,
    input  logic [3:0] length,
    input  logic       parity_type,
    input  logic       parity_en,
    input  logic       stop2,
    output logic       tx_active,
    output logic       tx,
    output logic       tx_done,
    output logic       tx_err
);
    typedef enum logic [2:0] {
        idle = 0, start_bit = 1, send_data = 2, send_parity = 3,
        send_first_stop = 4, send_sec_stop = 5, done = 6
    } state_type;

    state_type  state;
    logic [7:0] tx_reg;
    logic       parity_bit;
    logic [3:0] count;

    assign tx_active = (state != idle) || tx_start;

    always_comb begin
        logic raw_p;
        case (length)
            4'd5    : raw_p = ^(tx_reg[4:0]);
            4'd6    : raw_p = ^(tx_reg[5:0]);
            4'd7    : raw_p = ^(tx_reg[6:0]);
            4'd8    : raw_p = ^(tx_reg[7:0]);
            default : raw_p = 1'b0;
        endcase
        parity_bit = parity_type ? raw_p : ~raw_p;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= idle;
            tx      <= 1'b1;
            tx_done <= 1'b0;
            tx_err  <= 1'b0;
            tx_reg  <= 8'h00;
            count   <= 4'd0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                idle: begin
                    tx    <= 1'b1;
                    count <= 4'd0;
                    if (tx_start) begin
                        tx_reg <= tx_data;
                        tx_err <= (length < 4'd5 || length > 4'd8);
                        state  <= start_bit;
                    end
                end
                start_bit: if (tx_tick) begin
                    tx    <= 1'b0;
                    count <= 4'd0;
                    state <= send_data;
                end
                send_data: if (tx_tick) begin
                    tx <= tx_reg[count];
                    if (count < (length - 4'd1)) begin
                        count <= count + 4'd1;
                    end else begin
                        count <= 4'd0;
                        state <= parity_en ? send_parity : send_first_stop;
                    end
                end
                send_parity: if (tx_tick) begin
                    tx    <= parity_bit;
                    state <= send_first_stop;
                end
                send_first_stop: if (tx_tick) begin
                    tx    <= 1'b1;
                    state <= stop2 ? send_sec_stop : done;
                end
                send_sec_stop: if (tx_tick) begin
                    tx    <= 1'b1;
                    state <= done;
                end
                done: if (tx_tick) begin
                    tx_done <= 1'b1;
                    state   <= idle;
                end
                default: state <= idle;
            endcase
        end
    end
endmodule

// ============================================================================
// 3. Fault-Tolerant 16x UART RX (2-FF Synchronizer + 3-Point Majority Voting)
// ============================================================================
module lp_uart_rx (
    input  logic       clk,
    input  logic       rx_tick,
    input  logic       rx_start,
    input  logic       rst,
    input  logic       rx,
    input  logic [3:0] length,
    input  logic       parity_type,
    input  logic       parity_en,
    input  logic       stop2,
    output logic       rx_active,
    output logic [7:0] rx_out,
    output logic       rx_done,
    output logic       rx_error
);
    typedef enum logic [2:0] {
        idle = 0, start_bit = 1, recv_data = 2, check_parity = 3,
        check_first_stop = 4, check_sec_stop = 5, done = 6
    } state_type;

    state_type  state;
    logic       rx_s1, rx_sync;
    logic [7:0] datard;
    logic [3:0] count;
    logic [3:0] bit_count;
    logic       s7, s8, s9;
    logic       voted_rx;
    logic       exp_parity;

    // 2-out-of-3 majority voter rejects single-cycle line noise glitches
    assign voted_rx  = (s7 & s8) | (s8 & s9) | (s7 & s9);
    assign rx_active = (state != idle) || (rx_start && !rx_sync);

    // 2-FF synchronizer prevents metastability on asynchronous RX input
    always_ff @(posedge clk) begin
        if (rst) begin
            rx_s1   <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_s1   <= rx;
            rx_sync <= rx_s1;
        end
    end

    always_comb begin
        logic raw_p;
        case (length)
            4'd5    : raw_p = ^(datard[7:3]);
            4'd6    : raw_p = ^(datard[7:2]);
            4'd7    : raw_p = ^(datard[7:1]);
            default : raw_p = ^(datard[7:0]);
        endcase
        exp_parity = parity_type ? raw_p : ~raw_p;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= idle;
            rx_out      <= 8'h00;
            rx_done     <= 1'b0;
            rx_error    <= 1'b0;
            datard      <= 8'h00;
            count       <= 4'd0;
            bit_count   <= 4'd0;
            {s7, s8, s9}<= 3'b111;
        end else begin
            rx_done <= 1'b0;
            case (state)
                idle: begin
                    count     <= 4'd0;
                    bit_count <= 4'd0;
                    if (rx_start && !rx_sync) begin
                        rx_error <= 1'b0;
                        datard   <= 8'h00;
                        state    <= start_bit;
                    end
                end

                start_bit: if (rx_tick) begin
                    if (count == 4'd7) s7 <= rx_sync;
                    if (count == 4'd8) s8 <= rx_sync;
                    if (count == 4'd9) s9 <= rx_sync;
                    if (count == 4'd10 && voted_rx) begin
                        state <= idle;
                        count <= 4'd0;
                    end else if (count == 4'd15) begin
                        count <= 4'd0;
                        state <= recv_data;
                    end else begin
                        count <= count + 4'd1;
                    end
                end

                recv_data: if (rx_tick) begin
                    if (count == 4'd7) s7 <= rx_sync;
                    if (count == 4'd8) s8 <= rx_sync;
                    if (count == 4'd9) s9 <= rx_sync;
                    if (count == 4'd10)
                        datard <= {voted_rx, datard[7:1]};
                    if (count == 4'd15) begin
                        count <= 4'd0;
                        if (bit_count == (length - 4'd1)) begin
                            bit_count <= 4'd0;
                            state     <= parity_en ? check_parity : check_first_stop;
                        end else begin
                            bit_count <= bit_count + 4'd1;
                        end
                    end else begin
                        count <= count + 4'd1;
                    end
                end

                check_parity: if (rx_tick) begin
                    if (count == 4'd7) s7 <= rx_sync;
                    if (count == 4'd8) s8 <= rx_sync;
                    if (count == 4'd9) s9 <= rx_sync;
                    if (count == 4'd10 && (voted_rx != exp_parity))
                        rx_error <= 1'b1;
                    if (count == 4'd15) begin
                        count <= 4'd0;
                        state <= check_first_stop;
                    end else begin
                        count <= count + 4'd1;
                    end
                end

                check_first_stop: if (rx_tick) begin
                    if (count == 4'd7) s7 <= rx_sync;
                    if (count == 4'd8) s8 <= rx_sync;
                    if (count == 4'd9) s9 <= rx_sync;
                    if (count == 4'd10 && (voted_rx != 1'b1))
                        rx_error <= 1'b1;
                    if (count == 4'd15) begin
                        count <= 4'd0;
                        state <= stop2 ? check_sec_stop : done;
                    end else begin
                        count <= count + 4'd1;
                    end
                end

                check_sec_stop: if (rx_tick) begin
                    if (count == 4'd7) s7 <= rx_sync;
                    if (count == 4'd8) s8 <= rx_sync;
                    if (count == 4'd9) s9 <= rx_sync;
                    if (count == 4'd10 && (voted_rx != 1'b1))
                        rx_error <= 1'b1;
                    if (count == 4'd15) begin
                        count <= 4'd0;
                        state <= done;
                    end else begin
                        count <= count + 4'd1;
                    end
                end

                done: begin
                    case (length)
                        4'd5    : rx_out <= {3'b000, datard[7:3]};
                        4'd6    : rx_out <= {2'b00,  datard[7:2]};
                        4'd7    : rx_out <= {1'b0,   datard[7:1]};
                        default : rx_out <= datard;
                    endcase
                    rx_done <= 1'b1;
                    state   <= idle;
                end

                default: state <= idle;
            endcase
        end
    end
endmodule

// ============================================================================
// 4. Optimized Top-Level Wrapper (`uart_top` - Identical Port Signature)
// ============================================================================
module uart_top (
    input  logic        clk,
    input  logic        rst,
    input  logic        tx_start,
    input  logic        rx_start,
    input  logic [7:0]  tx_data,
    input  logic [16:0] baud,
    input  logic [3:0]  length,
    input  logic        parity_type,
    input  logic        parity_en,
    input  logic        stop2,
    output logic        tx_done,
    output logic        rx_done,
    output logic        tx_err,
    output logic        rx_err,
    output logic [7:0]  rx_out
);
    logic tx_tick, rx_tick;
    logic tx_active, rx_active;
    logic tx_rx;

    lp_clk_gen clk_dut (
        .clk(clk), .rst(rst), .baud(baud),
        .tx_active(tx_active), .rx_active(rx_active),
        .tx_tick(tx_tick), .rx_tick(rx_tick)
    );

    lp_uart_tx tx_dut (
        .clk(clk), .tx_tick(tx_tick), .tx_start(tx_start), .rst(rst),
        .tx_data(tx_data), .length(length), .parity_type(parity_type),
        .parity_en(parity_en), .stop2(stop2), .tx_active(tx_active),
        .tx(tx_rx), .tx_done(tx_done), .tx_err(tx_err)
    );

    lp_uart_rx rx_dut (
        .clk(clk), .rx_tick(rx_tick), .rx_start(rx_start), .rst(rst),
        .rx(tx_rx), .length(length), .parity_type(parity_type),
        .parity_en(parity_en), .stop2(stop2), .rx_active(rx_active),
        .rx_out(rx_out), .rx_done(rx_done), .rx_error(rx_err)
    );
endmodule