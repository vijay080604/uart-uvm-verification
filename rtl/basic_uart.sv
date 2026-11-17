`timescale 1ns / 1ps

// ============================================================================
// 1. Basic Clock Generator (Divided tx_clk & rx_clk for 50 MHz System Clock)
// ============================================================================
module clk_gen (
    input  logic        clk,
    input  logic        rst,
    input  logic [16:0] baud,
    output logic        tx_clk,
    output logic        rx_clk
);
    logic [10:0] rx_max;
    logic [13:0] tx_max;
    logic [10:0] rx_count;
    logic [13:0] tx_count;

    // Baud divisor lookup (for 50 MHz / 20 ns clock period)
    always_comb begin
        case (baud)
            17'd4800   : begin rx_max = 11'd325; tx_max = 14'd5207; end
            17'd9600   : begin rx_max = 11'd162; tx_max = 14'd2603; end
            17'd14400  : begin rx_max = 11'd108; tx_max = 14'd1735; end
            17'd19200  : begin rx_max = 11'd80;  tx_max = 14'd1301; end
            17'd38400  : begin rx_max = 11'd40;  tx_max = 14'd650;  end
            17'd57600  : begin rx_max = 11'd26;  tx_max = 14'd433;  end
            17'd115200 : begin rx_max = 11'd13;  tx_max = 14'd216;  end
            default    : begin rx_max = 11'd162; tx_max = 14'd2603; end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_count <= '0;
            rx_clk   <= 1'b0;
        end else if (rx_count >= rx_max) begin
            rx_clk   <= ~rx_clk;
            rx_count <= '0;
        end else begin
            rx_count <= rx_count + 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            tx_count <= '0;
            tx_clk   <= 1'b0;
        end else if (tx_count >= tx_max) begin
            tx_clk   <= ~tx_clk;
            tx_count <= '0;
        end else begin
            tx_count <= tx_count + 1'b1;
        end
    end
endmodule

// ============================================================================
// 2. Basic UART Transmitter
// ============================================================================
module basic_uart_tx (
    input  logic       tx_clk,
    input  logic       tx_start,
    input  logic       rst,
    input  logic [7:0] tx_data,
    input  logic [3:0] length,
    input  logic       parity_type, // 1 = Odd, 0 = Even
    input  logic       parity_en,
    input  logic       stop2,
    output logic       tx,
    output logic       tx_done,
    output logic       tx_err
);
    typedef enum logic [2:0] {
        idle            = 3'd0,
        start_bit       = 3'd1,
        send_data       = 3'd2,
        send_parity     = 3'd3,
        send_first_stop = 3'd4,
        send_sec_stop   = 3'd5,
        done            = 3'd6
    } state_type;

    state_type  state;
    logic [7:0] tx_reg;
    logic       parity_bit;
    logic [3:0] count;

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

    always_ff @(posedge tx_clk or posedge rst) begin
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
                        state  <= start_bit;
                    end
                end
                start_bit: begin
                    tx    <= 1'b0;
                    count <= 4'd0;
                    state <= send_data;
                end
                send_data: begin
                    tx <= tx_reg[count];
                    if (count < (length - 4'd1)) begin
                        count <= count + 4'd1;
                    end else begin
                        count <= 4'd0;
                        state <= parity_en ? send_parity : send_first_stop;
                    end
                end
                send_parity: begin
                    tx    <= parity_bit;
                    state <= send_first_stop;
                end
                send_first_stop: begin
                    tx    <= 1'b1;
                    state <= stop2 ? send_sec_stop : done;
                end
                send_sec_stop: begin
                    tx    <= 1'b1;
                    state <= done;
                end
                done: begin
                    tx_done <= 1'b1;
                    state   <= idle;
                end
                default: state <= idle;
            endcase
        end
    end
endmodule

// ============================================================================
// 3. Basic UART Receiver (Single Mid-Bit Sample at count == 7)
// ============================================================================
module basic_uart_rx (
    input  logic       rx_clk,
    input  logic       rx_start,
    input  logic       rst,
    input  logic       rx,
    input  logic [3:0] length,
    input  logic       parity_type,
    input  logic       parity_en,
    input  logic       stop2,
    output logic [7:0] rx_out,
    output logic       rx_done,
    output logic       rx_error
);
    typedef enum logic [2:0] {
        idle             = 3'd0,
        start_bit        = 3'd1,
        recv_data        = 3'd2,
        check_parity     = 3'd3,
        check_first_stop = 3'd4,
        check_sec_stop   = 3'd5,
        done             = 3'd6
    } state_type;

    state_type  state;
    logic [7:0] datard;
    logic [3:0] count;
    logic [3:0] bit_count;
    logic       exp_parity;

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

    always_ff @(posedge rx_clk or posedge rst) begin
        if (rst) begin
            state     <= idle;
            rx_out    <= 8'h00;
            rx_done   <= 1'b0;
            rx_error  <= 1'b0;
            datard    <= 8'h00;
            count     <= 4'd0;
            bit_count <= 4'd0;
        end else begin
            rx_done <= 1'b0;
            case (state)
                idle: begin
                    count     <= 4'd0;
                    bit_count <= 4'd0;
                    if (rx_start && !rx) begin
                        rx_error <= 1'b0;
                        datard   <= 8'h00;
                        state    <= start_bit;
                    end
                end
                start_bit: begin
                    if (count == 4'd7 && rx) begin
                        state <= idle;
                        count <= 4'd0;
                    end else if (count == 4'd15) begin
                        count <= 4'd0;
                        state <= recv_data;
                    end else begin
                        count <= count + 4'd1;
                    end
                end
                recv_data: begin
                    if (count == 4'd7)
                        datard <= {rx, datard[7:1]};
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
                check_parity: begin
                    if (count == 4'd7 && (rx != exp_parity))
                        rx_error <= 1'b1;
                    if (count == 4'd15) begin
                        count <= 4'd0;
                        state <= check_first_stop;
                    end else begin
                        count <= count + 4'd1;
                    end
                end
                check_first_stop: begin
                    if (count == 4'd7 && (rx != 1'b1))
                        rx_error <= 1'b1;
                    if (count == 4'd15) begin
                        count <= 4'd0;
                        state <= stop2 ? check_sec_stop : done;
                    end else begin
                        count <= count + 4'd1;
                    end
                end
                check_sec_stop: begin
                    if (count == 4'd7 && (rx != 1'b1))
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
// 4. Basic UART Top-Level (`basic_uart`)
// ============================================================================
module basic_uart (
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
    logic tx_clk, rx_clk, tx_rx;

    clk_gen clk_dut (
        .clk(clk), .rst(rst), .baud(baud), .tx_clk(tx_clk), .rx_clk(rx_clk)
    );

    basic_uart_tx tx_dut (
        .tx_clk(tx_clk), .tx_start(tx_start), .rst(rst), .tx_data(tx_data),
        .length(length), .parity_type(parity_type), .parity_en(parity_en),
        .stop2(stop2), .tx(tx_rx), .tx_done(tx_done), .tx_err(tx_err)
    );

    basic_uart_rx rx_dut (
        .rx_clk(rx_clk), .rx_start(rx_start), .rst(rst), .rx(tx_rx),
        .length(length), .parity_type(parity_type), .parity_en(parity_en),
        .stop2(stop2), .rx_out(rx_out), .rx_done(rx_done), .rx_error(rx_err)
    );
endmodule