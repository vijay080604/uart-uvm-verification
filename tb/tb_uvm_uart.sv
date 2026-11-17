`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================================
// 1. Interface with Concurrent SVA Protocol Properties
// ============================================================================
interface uart_if;
    logic        clk, rst;
    logic        tx_start, rx_start;
    logic [7:0]  tx_data;
    logic [16:0] baud;
    logic [3:0]  length;
    logic        parity_type, parity_en;
    logic        stop2;
    logic        tx_done, rx_done, tx_err, rx_err;
    logic [7:0]  rx_out;

    // SVA 1: Valid loopback frames must complete with zero TX/RX errors
    property p_valid_transfer_no_err;
        @(posedge clk) disable iff (rst)
        rx_done |-> (!tx_err && !rx_err);
    endproperty
    assert property (p_valid_transfer_no_err)
        else `uvm_error("SVA", "Protocol error flag asserted on valid frame completion!");

    // SVA 2: rx_done must be a clean single-cycle completion strobe
    property p_rx_done_pulse;
        @(posedge clk) disable iff (rst)
        rx_done |=> !rx_done;
    endproperty
    assert property (p_rx_done_pulse)
        else `uvm_error("SVA", "rx_done stayed high for more than 1 clock cycle!");
endinterface

// ============================================================================
// 2. Configuration & Transaction Item
// ============================================================================
class uart_config extends uvm_object;
    `uvm_object_utils(uart_config)
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    function new(string name = "uart_config");
        super.new(name);
    endfunction
endclass

typedef enum bit [3:0] {
    rand_baud_1_stop   = 0,
    rand_length_1_stop = 1,
    length5wp          = 2,
    length6wp          = 3,
    length7wp          = 4,
    length8wp          = 5,
    length5wop         = 6,
    length6wop         = 7,
    length7wop         = 8,
    length8wop         = 9,
    rand_baud_2_stop   = 11,
    rand_length_2_stop = 12
} oper_mode;

class transaction extends uvm_sequence_item;
    `uvm_object_utils(transaction)

    rand oper_mode    op;
         logic        tx_start, rx_start;
         logic        rst;
    rand logic [7:0]  tx_data;
    rand logic [16:0] baud;
    rand logic [3:0]  length;
    rand logic        parity_type, parity_en;
         logic        stop2;
         logic        tx_done, rx_done, tx_err, rx_err;
         logic [7:0]  rx_out;

    constraint baud_c   { baud inside {4800, 9600, 14400, 19200, 38400, 57600, 115200}; }
    constraint length_c { length inside {5, 6, 7, 8}; }

    function new(string name = "transaction");
        super.new(name);
    endfunction
endclass : transaction

// ============================================================================
// 3. All 10 UVM Sequences (50 Randomized Frames Across Baud, Length & Parity)
// ============================================================================
class rand_baud extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud)
    transaction tr;
    function new(string name = "rand_baud"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = rand_baud_1_stop; tr.length = 8; tr.rst = 1'b0;
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b1; tr.stop2 = 1'b0;
            finish_item(tr);
        end
    endtask
endclass

class rand_baud_with_stop extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud_with_stop)
    transaction tr;
    function new(string name = "rand_baud_with_stop"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = rand_baud_2_stop; tr.rst = 1'b0; tr.length = 8;
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b1; tr.stop2 = 1'b1;
            finish_item(tr);
        end
    endtask
endclass

class rand_baud_len5p extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud_len5p)
    transaction tr;
    function new(string name = "rand_baud_len5p"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = length5wp; tr.rst = 1'b0; tr.length = 5;
            tr.tx_data = {3'b000, tr.tx_data[4:0]};
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b1; tr.stop2 = 1'b0;
            finish_item(tr);
        end
    endtask
endclass

class rand_baud_len6p extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud_len6p)
    transaction tr;
    function new(string name = "rand_baud_len6p"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = length6wp; tr.rst = 1'b0; tr.length = 6;
            tr.tx_data = {2'b00, tr.tx_data[5:0]};
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b1; tr.stop2 = 1'b0;
            finish_item(tr);
        end
    endtask
endclass

class rand_baud_len7p extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud_len7p)
    transaction tr;
    function new(string name = "rand_baud_len7p"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = length7wp; tr.rst = 1'b0; tr.length = 7;
            tr.tx_data = {1'b0, tr.tx_data[6:0]};
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b1; tr.stop2 = 1'b0;
            finish_item(tr);
        end
    endtask
endclass

class rand_baud_len8p extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud_len8p)
    transaction tr;
    function new(string name = "rand_baud_len8p"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = length8wp; tr.rst = 1'b0; tr.length = 8;
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b1; tr.stop2 = 1'b0;
            finish_item(tr);
        end
    endtask
endclass

class rand_baud_len5 extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud_len5)
    transaction tr;
    function new(string name = "rand_baud_len5"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = length5wop; tr.rst = 1'b0; tr.length = 5;
            tr.tx_data = {3'b000, tr.tx_data[4:0]};
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b0; tr.stop2 = 1'b0;
            finish_item(tr);
        end
    endtask
endclass

class rand_baud_len6 extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud_len6)
    transaction tr;
    function new(string name = "rand_baud_len6"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = length6wop; tr.rst = 1'b0; tr.length = 6;
            tr.tx_data = {2'b00, tr.tx_data[5:0]};
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b0; tr.stop2 = 1'b0;
            finish_item(tr);
        end
    endtask
endclass

class rand_baud_len7 extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud_len7)
    transaction tr;
    function new(string name = "rand_baud_len7"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = length7wop; tr.rst = 1'b0; tr.length = 7;
            tr.tx_data = {1'b0, tr.tx_data[6:0]};
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b0; tr.stop2 = 1'b0;
            finish_item(tr);
        end
    endtask
endclass

class rand_baud_len8 extends uvm_sequence#(transaction);
    `uvm_object_utils(rand_baud_len8)
    transaction tr;
    function new(string name = "rand_baud_len8"); super.new(name); endfunction
    virtual task body();
        repeat (5) begin
            tr = transaction::type_id::create("tr");
            start_item(tr);
            assert(tr.randomize());
            tr.op = length8wop; tr.rst = 1'b0; tr.length = 8;
            tr.tx_start = 1'b1; tr.rx_start = 1'b1; tr.parity_en = 1'b0; tr.stop2 = 1'b0;
            finish_item(tr);
        end
    endtask
endclass

// ============================================================================
// 4. UVM Driver (Synchronized TX/RX Completion Handshake)
// ============================================================================
class driver extends uvm_driver #(transaction);
    `uvm_component_utils(driver)
    virtual uart_if vif;
    transaction tr;

    function new(input string path = "drv", uvm_component parent = null);
        super.new(path, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
            `uvm_error("drv", "Unable to access Interface");
    endfunction

    task reset_dut();
        repeat (5) begin
            vif.rst         <= 1'b1;
            vif.tx_start    <= 1'b0;
            vif.rx_start    <= 1'b0;
            vif.tx_data     <= 8'h00;
            vif.baud        <= 17'd9600;
            vif.length      <= 4'd8;
            vif.parity_type <= 1'b0;
            vif.parity_en   <= 1'b0;
            vif.stop2       <= 1'b0;
            @(posedge vif.clk);
        end
        vif.rst <= 1'b0;
        @(posedge vif.clk);
    endtask

    task drive();
        reset_dut();
        forever begin
            seq_item_port.get_next_item(tr);
            vif.rst         <= 1'b0;
            vif.tx_start    <= tr.tx_start;
            vif.rx_start    <= tr.rx_start;
            vif.tx_data     <= tr.tx_data;
            vif.baud        <= tr.baud;
            vif.length      <= tr.length;
            vif.parity_type <= tr.parity_type;
            vif.parity_en   <= tr.parity_en;
            vif.stop2       <= tr.stop2;

            @(posedge vif.clk);
            vif.tx_start <= 1'b0;

            fork
                @(posedge vif.tx_done);
                @(posedge vif.rx_done);
            join
            @(posedge vif.clk);
            seq_item_port.item_done();
        end
    endtask

    virtual task run_phase(uvm_phase phase);
        drive();
    endtask
endclass

// ============================================================================
// 5. UVM Monitor
// ============================================================================
class mon extends uvm_monitor;
    `uvm_component_utils(mon)
    uvm_analysis_port#(transaction) send;
    virtual uart_if vif;

    function new(input string inst = "mon", uvm_component parent = null);
        super.new(inst, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        send = new("send", this);
        if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
            `uvm_error("MON", "Unable to access Interface");
    endfunction

    virtual task run_phase(uvm_phase phase);
        transaction tr;
        forever begin
            @(posedge vif.rx_done);
            if (!vif.rst) begin
                tr = transaction::type_id::create("tr");
                tr.rst         = 1'b0;
                tr.tx_data     = vif.tx_data;
                tr.baud        = vif.baud;
                tr.length      = vif.length;
                tr.parity_type = vif.parity_type;
                tr.parity_en   = vif.parity_en;
                tr.stop2       = vif.stop2;
                tr.rx_out      = vif.rx_out;
                tr.tx_err      = vif.tx_err;
                tr.rx_err      = vif.rx_err;
                `uvm_info("MON", $sformatf("BAUD:%0d LEN:%0d PAR_T:%0d PAR_EN:%0d STOP:%0d TX_DATA:0x%02h RX_DATA:0x%02h",
                          tr.baud, tr.length, tr.parity_type, tr.parity_en, tr.stop2, tr.tx_data, tr.rx_out), UVM_MEDIUM);
                send.write(tr);
            end
        end
    endtask
endclass

// ============================================================================
// 6. Functional Coverage Collector (`uvm_subscriber`)
// ============================================================================
class uart_cov extends uvm_subscriber#(transaction);
    `uvm_component_utils(uart_cov)
    transaction tr;

    covergroup cg_uart;
        cp_baud   : coverpoint tr.baud        { bins b[] = {4800, 9600, 14400, 19200, 38400, 57600, 115200}; }
        cp_len    : coverpoint tr.length      { bins l[] = {5, 6, 7, 8}; }
        cp_par_en : coverpoint tr.parity_en   { bins off = {0}; bins on = {1}; }
        cp_par_t  : coverpoint tr.parity_type { bins even = {0}; bins odd = {1}; }
        cp_stop2  : coverpoint tr.stop2       { bins one = {0}; bins two = {1}; }
        cx_frame  : cross cp_len, cp_par_en, cp_par_t;
    endgroup

    function new(string name = "uart_cov", uvm_component parent = null);
        super.new(name, parent);
        cg_uart = new();
    endfunction

    virtual function void write(transaction t);
        tr = t;
        cg_uart.sample();
    endfunction
endclass

// ============================================================================
// 7. Scoreboard with Final Summary Report
// ============================================================================
class sco extends uvm_scoreboard;
    `uvm_component_utils(sco)
    uvm_analysis_imp#(transaction, sco) recv;
    int pass_cnt = 0;
    int fail_cnt = 0;

    function new(input string inst = "sco", uvm_component parent = null);
        super.new(inst, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        recv = new("recv", this);
    endfunction

    virtual function void write(transaction tr);
        if (tr.tx_data == tr.rx_out && !tr.rx_err && !tr.tx_err) begin
            pass_cnt++;
            `uvm_info("SCO", $sformatf("Test Passed | TX:0x%02h == RX:0x%02h", tr.tx_data, tr.rx_out), UVM_MEDIUM)
        end else begin
            fail_cnt++;
            `uvm_error("SCO", $sformatf("Test Failed | EXP:0x%02h GOT:0x%02h RX_ERR:%0b", tr.tx_data, tr.rx_out, tr.rx_err))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        $display("========================================================================");
        $display(" UART UVM SCOREBOARD SUMMARY : PASS = %0d | FAIL = %0d", pass_cnt, fail_cnt);
        $display(" FUNCTIONAL COVERAGE         : %0.2f%%", $get_coverage());
        $display("========================================================================");
    endfunction
endclass

// ============================================================================
// 8. Agent, Environment & Full-Regression Test
// ============================================================================
class agent extends uvm_agent;
    `uvm_component_utils(agent)
    uart_config cfg;
    driver d;
    uvm_sequencer#(transaction) seqr;
    mon m;

    function new(input string inst = "agent", uvm_component parent = null);
        super.new(inst, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg = uart_config::type_id::create("cfg");
        m   = mon::type_id::create("m", this);
        if (cfg.is_active == UVM_ACTIVE) begin
            d    = driver::type_id::create("d", this);
            seqr = uvm_sequencer#(transaction)::type_id::create("seqr", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (cfg.is_active == UVM_ACTIVE)
            d.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass

class env extends uvm_env;
    `uvm_component_utils(env)
    agent    a;
    sco      s;
    uart_cov cov;

    function new(input string inst = "env", uvm_component c);
        super.new(inst, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        a   = agent::type_id::create("a", this);
        s   = sco::type_id::create("s", this);
        cov = uart_cov::type_id::create("cov", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        a.m.send.connect(s.recv);
        a.m.send.connect(cov.analysis_export);
    endfunction
endclass

class test extends uvm_test;
    `uvm_component_utils(test)
    env e;
    rand_baud           rb;
    rand_baud_with_stop rbs;
    rand_baud_len5p     rb5l;
    rand_baud_len6p     rb6l;
    rand_baud_len7p     rb7l;
    rand_baud_len8p     rb8l;
    rand_baud_len5      rb5lwop;
    rand_baud_len6      rb6lwop;
    rand_baud_len7      rb7lwop;
    rand_baud_len8      rb8lwop;

    function new(string inst = "test", uvm_component c);
        super.new(inst, c);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        e       = env::type_id::create("env", this);
        rb      = rand_baud::type_id::create("rb");
        rbs     = rand_baud_with_stop::type_id::create("rbs");
        rb5l    = rand_baud_len5p::type_id::create("rb5l");
        rb6l    = rand_baud_len6p::type_id::create("rb6l");
        rb7l    = rand_baud_len7p::type_id::create("rb7l");
        rb8l    = rand_baud_len8p::type_id::create("rb8l");
        rb5lwop = rand_baud_len5::type_id::create("rb5lwop");
        rb6lwop = rand_baud_len6::type_id::create("rb6lwop");
        rb7lwop = rand_baud_len7::type_id::create("rb7lwop");
        rb8lwop = rand_baud_len8::type_id::create("rb8lwop");
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        rb.start(e.a.seqr);
        rbs.start(e.a.seqr);
        rb5l.start(e.a.seqr);
        rb6l.start(e.a.seqr);
        rb7l.start(e.a.seqr);
        rb8l.start(e.a.seqr);
        rb5lwop.start(e.a.seqr);
        rb6lwop.start(e.a.seqr);
        rb7lwop.start(e.a.seqr);
        rb8lwop.start(e.a.seqr);
        #100;
        phase.drop_objection(this);
    endtask
endclass

// ============================================================================
// 9. Top-Level UVM Testbench (`tb`)
// ============================================================================
module tb;
    uart_if vif();

    uart_top dut (
        .clk         (vif.clk),
        .rst         (vif.rst),
        .tx_start    (vif.tx_start),
        .rx_start    (vif.rx_start),
        .tx_data     (vif.tx_data),
        .baud        (vif.baud),
        .length      (vif.length),
        .parity_type (vif.parity_type),
        .parity_en   (vif.parity_en),
        .stop2       (vif.stop2),
        .tx_done     (vif.tx_done),
        .rx_done     (vif.rx_done),
        .tx_err      (vif.tx_err),
        .rx_err      (vif.rx_err),
        .rx_out      (vif.rx_out)
    );

    initial vif.clk <= 0;
    always #2.5 vif.clk <= ~vif.clk; // 200 MHz (5.000 ns) system clock

    initial begin
        uvm_config_db#(virtual uart_if)::set(null, "*", "vif", vif);
        run_test("test");
    end
endmodule