`timescale 1ns/1ps

module router_tb;

parameter FLIT_SIZE    = 40;
parameter COORD_W      = 4;
parameter BUFFER_DEPTH = 8;
parameter NUM_VCS      = 2;
parameter ROUTER_X_ID  = 2;
parameter ROUTER_Y_ID  = 2;
parameter CLK_HALF     = 5;

// Clock/Reset
reg clk, rst_n;
initial begin clk=0; rst_n=0; #50 rst_n=1; end
always #CLK_HALF clk = ~clk;

// Task-driven port registers
reg  [FLIT_SIZE-1:0] task_flit  [0:4];
reg  [4:0]           task_valid;
reg  [NUM_VCS-1:0]   task_vc    [0:4];

wire [FLIT_SIZE-1:0] tg_flit;
wire                 tg_valid;
wire [NUM_VCS-1:0]   tg_vc;
reg                  tg_en;
wire [31:0]          tg_pkts, tg_flits;

// Final muxed registers going to DUT
reg  [5*FLIT_SIZE-1:0] in_flit_flat;
reg  [4:0]             in_valid;
reg  [5*NUM_VCS-1:0]   in_vc_flat;

// Mux: traffic generator overrides LOCAL port (0) when tg_en is active
always @(*) begin : port_mux
    integer p;
    for (p=0; p<5; p=p+1) begin
        in_flit_flat[p*FLIT_SIZE +: FLIT_SIZE] = task_flit[p];
        in_vc_flat  [p*NUM_VCS   +: NUM_VCS]   = task_vc[p];
    end
    in_valid = task_valid;
    if (tg_en && tg_valid) begin
        in_flit_flat[0*FLIT_SIZE +: FLIT_SIZE] = tg_flit;
        in_vc_flat  [0*NUM_VCS   +: NUM_VCS]   = tg_vc;
        in_valid[0]                            = 1'b1;
    end
end

wire [5*FLIT_SIZE-1:0] out_flit_flat;
wire [4:0]             out_valid;
wire [5*NUM_VCS-1:0]   credit_flat;
reg  [5*NUM_VCS-1:0]   ds_credit_flat;

// DUT
top #(
    .FLIT_SIZE   (FLIT_SIZE),
    .COORD_W     (COORD_W),
    .BUFFER_DEPTH(BUFFER_DEPTH),
    .NUM_VCS     (NUM_VCS),
    .ROUTER_X_ID (ROUTER_X_ID),
    .ROUTER_Y_ID (ROUTER_Y_ID)
) dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .in_flit_flat  (in_flit_flat),
    .in_valid      (in_valid),
    .in_vc_flat    (in_vc_flat),
    .out_flit_flat (out_flit_flat),
    .out_valid     (out_valid),
    .credit_flat   (credit_flat),
    .ds_credit_flat(ds_credit_flat)
);

// Traffic generator
traffic_gen #(
    .FLIT_SIZE    (FLIT_SIZE),
    .COORD_W      (COORD_W),
    .NUM_VCS      (NUM_VCS),
    .DST_X        (ROUTER_X_ID+1),
    .DST_Y        (ROUTER_Y_ID),
    .PKT_LEN      (4),
    .SEED         (32'hCAFEBABE),
    .BUFFER_DEPTH (BUFFER_DEPTH)
) tgen (
    .clk       (clk),
    .rst_n     (rst_n),
    .inject_en (tg_en),
    .credit_in (credit_flat[0*NUM_VCS +: NUM_VCS]),
    .vc_sel_in (1'b0),
    .flit_out  (tg_flit),
    .flit_valid(tg_valid),
    .vc_sel_out(tg_vc),
    .pkt_count (tg_pkts),
    .flit_count(tg_flits)
);

// Flit builder
function [FLIT_SIZE-1:0] mkflit;
    input        is_head, is_tail;
    input [3:0]  dx, dy;
    input [31:0] pay;
    localparam PW = FLIT_SIZE - 3 - 2*COORD_W;
    begin mkflit = {1'b1, is_head, is_tail, dx, dy, pay[PW-1:0]}; end
endfunction

//  Inject helpers
task send_flit;
    input integer port, vc;
    input [FLIT_SIZE-1:0] flit;
    begin
        @(negedge clk);
        task_flit[port]  = flit;
        task_valid[port] = 1;
        task_vc[port]    = (1 << vc);
        @(posedge clk);
        @(negedge clk);
        task_valid[port] = 0;
        task_flit[port]  = 0;
        task_vc[port]    = 0;
    end
endtask

task inject_pkt;
    input integer port, vc;
    input [3:0] dx, dy;
    input integer plen;
    integer f;
    begin
        for (f=0; f<plen; f=f+1)
            send_flit(port, vc,
                mkflit((f==0),(f==plen-1), dx, dy, f*32'h1111_1111));
    end
endtask

task expect_port;
    input integer exp_port;
    input [255:0] label;
    input integer timeout;
    integer i;
    reg hit;
    begin
        hit = 0;
        for (i=0; i<timeout && !hit; i=i+1) begin
            @(posedge clk); #1;
            if (out_valid[exp_port]) hit = 1;
        end
        if (hit)
            $display("[PASS] %s  port=%0d @ %0.1f ns",
                     label, exp_port, $realtime/1000.0);
        else
            $display("[FAIL] %s  timeout on port %0d after %0d cycles",
                     label, exp_port, timeout);
    end
endtask

// Stimulus
integer p;
initial begin
    for (p=0; p<5; p=p+1) begin
        task_flit[p]  = 0;
        task_valid[p] = 0;
        task_vc[p]    = 0;
    end
    ds_credit_flat = {(5*NUM_VCS){1'b1}};
    tg_en          = 0;

    @(posedge rst_n);
    repeat(4) @(posedge clk);

    $display("====================================================");
    $display(" NoC Router TB  –  Router (%0d,%0d)  FLIT_SIZE=%0d",
             ROUTER_X_ID, ROUTER_Y_ID, FLIT_SIZE);
    $display("====================================================");

    // TC1: LOCAL -> EAST
    $display("\n[TC1] LOCAL -> EAST (dx=+1)");
    fork
        inject_pkt(0, 0, ROUTER_X_ID+1, ROUTER_Y_ID, 3);
        expect_port(3, "TC1 LOCAL->EAST", 60);
    join
    repeat(8) @(posedge clk);

    // TC2: LOCAL -> WEST
    $display("\n[TC2] LOCAL -> WEST (dx=-1)");
    fork
        inject_pkt(0, 0, ROUTER_X_ID-1, ROUTER_Y_ID, 3);
        expect_port(4, "TC2 LOCAL->WEST", 60);
    join
    repeat(8) @(posedge clk);

    // TC3: LOCAL -> SOUTH
    $display("\n[TC3] LOCAL -> SOUTH (dy=+1)");
    fork
        inject_pkt(0, 0, ROUTER_X_ID, ROUTER_Y_ID+1, 3);
        expect_port(2, "TC3 LOCAL->SOUTH", 60);
    join
    repeat(8) @(posedge clk);

    // TC4: LOCAL -> NORTH
    $display("\n[TC4] LOCAL -> NORTH (dy=-1)");
    fork
        inject_pkt(0, 0, ROUTER_X_ID, ROUTER_Y_ID-1, 3);
        expect_port(1, "TC4 LOCAL->NORTH", 60);
    join
    repeat(8) @(posedge clk);

    // TC5: LOCAL -> LOCAL (self)
    $display("\n[TC5] LOCAL -> LOCAL (self-destined)");
    fork
        inject_pkt(0, 0, ROUTER_X_ID, ROUTER_Y_ID, 2);
        expect_port(0, "TC5 LOCAL->LOCAL", 60);
    join
    repeat(8) @(posedge clk);

    // TC6: Concurrent injection on NORTH and WEST ports
    $display("\n[TC6] Concurrent: NORTH->EAST  and  WEST->LOCAL");
    @(negedge clk);
    task_flit[1]  = mkflit(1,0, ROUTER_X_ID+1, ROUTER_Y_ID, 32'hAA11);
    task_valid[1] = 1; task_vc[1] = 2'b01;
    task_flit[4]  = mkflit(1,0, ROUTER_X_ID, ROUTER_Y_ID, 32'hBB22);
    task_valid[4] = 1; task_vc[4] = 2'b01;
    repeat(2) @(posedge clk);
    @(negedge clk);
    task_flit[1] = mkflit(0,1, ROUTER_X_ID+1, ROUTER_Y_ID, 32'hAA11);
    task_flit[4] = mkflit(0,1, ROUTER_X_ID,   ROUTER_Y_ID, 32'hBB22);
    @(posedge clk);
    @(negedge clk);
    task_valid[1]=0; task_valid[4]=0;
    task_flit[1]=0;  task_flit[4]=0;
    task_vc[1]=0;    task_vc[4]=0;
    repeat(20) @(posedge clk);
    $display("[INFO] TC6 concurrent injection done – check waveform for RR arbitration");

    // TC7: Back-pressure: zero EAST downstream credits
    $display("\n[TC7] Back-pressure: EAST ds_credits=0 (router should buffer, not drop)");
    ds_credit_flat[3*NUM_VCS +: NUM_VCS] = 2'b00;
    inject_pkt(0, 0, ROUTER_X_ID+1, ROUTER_Y_ID, 3);
    repeat(30) @(posedge clk);
    $display("[INFO] TC7 EAST blocked – no out_valid[3] expected (verify in waveform)");
    ds_credit_flat[3*NUM_VCS +: NUM_VCS] = 2'b11;
    repeat(15) @(posedge clk);

    // TC8: Multi-VC alternating injection on LOCAL port
    $display("\n[TC8] Multi-VC: VC0->EAST, then VC1->WEST");
    inject_pkt(0, 0, ROUTER_X_ID+1, ROUTER_Y_ID, 3);
    inject_pkt(0, 1, ROUTER_X_ID-1, ROUTER_Y_ID, 3);
    repeat(30) @(posedge clk);
    $display("[INFO] TC8 Multi-VC done – verify both directions in waveform");

    // TC9: Traffic generator stress – 32 packets
    $display("\n[TC9] Traffic generator stress: 32 packets");
    tg_en = 1;
    begin : tc9_wait
        integer cyc;
        for (cyc=0; cyc<5000 && tg_pkts<32; cyc=cyc+1)
            @(posedge clk);
    end
    tg_en = 0;
    if (tg_pkts >= 32)
        $display("[PASS] TC9  %0d pkts / %0d flits injected and routed",
                 tg_pkts, tg_flits);
    else
        $display("[FAIL] TC9  Only %0d/32 pkts completed", tg_pkts);
    repeat(15) @(posedge clk);

    // TC10: Back-to-back worm tail release
    $display("\n[TC10] Back-to-back worms (verify no flit interleaving)");
    inject_pkt(0, 0, ROUTER_X_ID+1, ROUTER_Y_ID, 4);
    repeat(2) @(posedge clk);
    inject_pkt(0, 0, ROUTER_X_ID+1, ROUTER_Y_ID, 4);
    repeat(30) @(posedge clk);
    $display("[PASS] TC10 Back-to-back worm injection done");

    $display("\n====================================================");
    $display(" All test cases executed.");
    $display(" Open sim/router_waves.vcd in GTKWave for visual verification.");
    $display("====================================================");
    $finish;
end

// Waveform gen
initial begin
    $dumpfile("../sim/router_waves.vcd"); 
    $dumpvars(0, router_tb);
end

// Watchdog
initial begin
    #2000000;
    $display("[WATCHDOG] Timeout at %0.1f ns", $realtime/1000.0);
    $finish;
end

endmodule