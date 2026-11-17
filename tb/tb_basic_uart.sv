`timescale 1ns / 1ps

module tb_basic_uart;
    logic        clk = 0;
    logic        rst;
    logic        tx_start, rx_start;
    logic [7:0]  tx_data;
    logic [16:0] baud;
    logic [3:0]  length;
    logic        parity_type, parity_en;
    logic        stop2;
    logic        tx_done, rx_done, tx_err, rx_err;
    logic [7:0]  rx_out;

    int pass_cnt = 0;
    int fail_cnt = 0;

    // 50 MHz system clock (20 ns period)
    always #10 clk = ~clk;

    basic_uart dut (
        .clk         (clk),
        .rst         (rst),
        .tx_start    (tx_start),
        .rx_start    (rx_start),
        .tx_data     (tx_data),
        .baud        (baud),
        .length      (length),
        .parity_type (parity_type),
        .parity_en   (parity_en),
        .stop2       (stop2),
        .tx_done     (tx_done),
        .rx_done     (rx_done),
        .tx_err      (tx_err),
        .rx_err      (rx_err),
        .rx_out      (rx_out)
    );

    task automatic send_and_check(
        input logic [16:0] t_baud,
        input logic [3:0]  t_len,
        input logic        t_par_en,
        input logic        t_par_type,
        input logic        t_stop2,
        input logic [7:0]  t_data
    );
        begin
            baud        = t_baud;
            length      = t_len;
            parity_en   = t_par_en;
            parity_type = t_par_type;
            stop2       = t_stop2;
            tx_data     = t_data;
            rx_start    = 1'b1;
            tx_start    = 1'b1;

            // Wait until both TX and RX finish the frame
            fork
                @(posedge tx_done);
                @(posedge rx_done);
            join
            tx_start = 1'b0;
            #500;

            if (rx_out === t_data && !rx_err && !tx_err) begin
                pass_cnt++;
                $display("[PASS] BAUD=%0d LEN=%0d PAR_EN=%0b PAR_T=%0b STOP2=%0b | TX=0x%02h == RX=0x%02h",
                         t_baud, t_len, t_par_en, t_par_type, t_stop2, t_data, rx_out);
            end else begin
                fail_cnt++;
                $display("[FAIL] BAUD=%0d LEN=%0d | EXP=0x%02h GOT=0x%02h RX_ERR=%0b",
                         t_baud, t_len, t_data, rx_out, rx_err);
            end
        end
    endtask

    initial begin
        rst      = 1'b1;
        tx_start = 1'b0;
        rx_start = 1'b0;
        tx_data  = 8'h00;
        baud     = 17'd115200;
        length   = 4'd8;
        parity_en   = 1'b0;
        parity_type = 1'b0;
        stop2       = 1'b0;

        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);

        // Test 1-6: Varying lengths, baud rates, parity & stop bits
        send_and_check(17'd115200, 4'd8, 1'b1, 1'b0, 1'b0, 8'hA5); // 8-bit, even parity, 1 stop
        send_and_check(17'd115200, 4'd8, 1'b1, 1'b1, 1'b1, 8'h3C); // 8-bit, odd parity, 2 stop
        send_and_check(17'd57600,  4'd8, 1'b0, 1'b0, 1'b0, 8'hF0); // 8-bit, no parity
        send_and_check(17'd115200, 4'd7, 1'b1, 1'b0, 1'b0, 8'h5A); // 7-bit, even parity
        send_and_check(17'd115200, 4'd6, 1'b1, 1'b1, 1'b0, 8'h2D); // 6-bit, odd parity
        send_and_check(17'd115200, 4'd5, 1'b0, 1'b0, 1'b0, 8'h17); // 5-bit, no parity

        $display("========================================================================");
        $display(" BASIC UART SUMMARY : PASS = %0d | FAIL = %0d", pass_cnt, fail_cnt);
        $display("========================================================================");
        $finish;
    end
endmodule