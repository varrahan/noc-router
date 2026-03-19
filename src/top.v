`timescale 1ns/1ps

module top #(
    parameter DATA_WIDTH   = 32,
    parameter COORD_W      = 4,
    parameter FLIT_SIZE    = 40,
    parameter BUFFER_DEPTH = 8,
    parameter NUM_VCS      = 2,
    parameter ROUTER_X_ID  = 0,
    parameter ROUTER_Y_ID  = 0
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [5*FLIT_SIZE-1:0] in_flit_flat,
    input  wire [4:0]             in_valid,
    input  wire [5*NUM_VCS-1:0]   in_vc_flat,
    output wire [5*FLIT_SIZE-1:0] out_flit_flat,
    output wire [4:0]             out_valid,
    output wire [5*NUM_VCS-1:0]   credit_flat,
    input  wire [5*NUM_VCS-1:0]   ds_credit_flat
);

localparam NUM_PORTS = 5;
localparam VC_W      = 1;

// Unpack flat inputs
wire [FLIT_SIZE-1:0] in_flit   [0:4];
wire [NUM_VCS-1:0]   in_vc     [0:4];
wire [NUM_VCS-1:0]   ds_credit [0:4];

genvar gu;
generate for (gu=0;gu<5;gu=gu+1) begin : g_unpack
    assign in_flit[gu]   = in_flit_flat  [gu*FLIT_SIZE +: FLIT_SIZE];
    assign in_vc[gu]     = in_vc_flat    [gu*NUM_VCS   +: NUM_VCS];
    assign ds_credit[gu] = ds_credit_flat[gu*NUM_VCS   +: NUM_VCS];
end endgenerate

// Input Buffers
wire [FLIT_SIZE-1:0] buf_out    [0:4][0:1];
wire                 buf_empty  [0:4][0:1];
wire                 buf_full   [0:4][0:1];
wire                 buf_hd_vld [0:4][0:1];
wire                 buf_credit [0:4][0:1];
reg                  buf_rd_en  [0:4][0:1];

genvar gp, gv;
generate
for (gp=0;gp<5;gp=gp+1) begin : g_port
  for (gv=0;gv<2;gv=gv+1) begin : g_vc
    wire wr = in_valid[gp] & in_vc[gp][gv];
    input_buffer #(.FLIT_SIZE(FLIT_SIZE),.BUFFER_DEPTH(BUFFER_DEPTH)) ib (
        .clk(clk),.rst_n(rst_n),
        .wr_en(wr),.flit_in(in_flit[gp]),
        .rd_en(buf_rd_en[gp][gv]),
        .flit_out(buf_out[gp][gv]),
        .full(buf_full[gp][gv]),.empty(buf_empty[gp][gv]),
        .valid_head(buf_hd_vld[gp][gv]),
        .credit_out(buf_credit[gp][gv]));
    assign credit_flat[gp*NUM_VCS+gv] = buf_credit[gp][gv];
  end
end
endgenerate

// Route Compute
wire [4:0] rc_port [0:4][0:1];

generate
for (gp=0;gp<5;gp=gp+1) begin : g_rc_p
  for (gv=0;gv<2;gv=gv+1) begin : g_rc_v
    route_compute #(.FLIT_SIZE(FLIT_SIZE),.COORD_W(COORD_W),
                    .ROUTER_X(ROUTER_X_ID),.ROUTER_Y(ROUTER_Y_ID)) rc (
        .head_flit(buf_out[gp][gv]),
        .head_valid(buf_hd_vld[gp][gv]),
        .out_port(rc_port[gp][gv]));
  end
end
endgenerate

// Worm state
reg        worm_active   [0:4][0:1];
reg [4:0]  worm_out_port [0:4][0:1];

// ============================================================
// VC Allocator (runs in parallel with SA; grant selects
// downstream VC only – does NOT gate SA requests)
// ============================================================
wire [NUM_PORTS*NUM_VCS-1:0]      vc_req_flat_w;
wire [NUM_PORTS*NUM_VCS*3-1:0]    opr_flat;
wire [NUM_PORTS*NUM_VCS-1:0]      ds_cred_flat;
wire [NUM_PORTS*NUM_VCS-1:0]      vc_grant_vld;
wire [NUM_PORTS*NUM_VCS*VC_W-1:0] vc_grant_packed;

generate
for (gp=0;gp<5;gp=gp+1) begin : g_vca_p
  for (gv=0;gv<2;gv=gv+1) begin : g_vca_v
    assign vc_req_flat_w[gp*NUM_VCS+gv]  = buf_hd_vld[gp][gv] & ~worm_active[gp][gv];
    assign ds_cred_flat [gp*NUM_VCS+gv]  = ds_credit[gp][gv];
    wire [2:0] opr = rc_port[gp][gv][0] ? 3'd0 :
                     rc_port[gp][gv][1] ? 3'd1 :
                     rc_port[gp][gv][2] ? 3'd2 :
                     rc_port[gp][gv][3] ? 3'd3 : 3'd4;
    assign opr_flat[(gp*NUM_VCS+gv)*3 +: 3] = opr;
  end
end
endgenerate

vc_allocator #(.NUM_PORTS(NUM_PORTS),.NUM_VCS(NUM_VCS)) u_vca (
    .clk(clk),.rst_n(rst_n),
    .vc_req(vc_req_flat_w),
    .out_port_req_flat(opr_flat),
    .ds_credits(ds_cred_flat),
    .vc_grant_flat(vc_grant_packed),
    .vc_grant_vld(vc_grant_vld));

// ============================================================
// Stage 3/4a – Switch Allocator
//
// SA request rules (no dependency on VC allocator):
//   HEAD flit:  buf_hd_vld=1 AND worm_active=0 → request rc_port direction
//   BODY/TAIL:  worm_active=1 AND !buf_empty   → request worm_out_port direction
//
// SA grant drives worm activation and worm_out_port latch.
// ============================================================
reg  [NUM_PORTS*NUM_PORTS-1:0] sa_req_reg;
wire [NUM_PORTS*NUM_PORTS-1:0] sa_req_w   = sa_req_reg;
wire [NUM_PORTS*NUM_PORTS-1:0] sa_grant_w;
wire [NUM_PORTS*3-1:0]         sa_grant_in_packed;

integer op_i, pp2, vv2;
always @(*) begin
    sa_req_reg = {(NUM_PORTS*NUM_PORTS){1'b0}};
    for (pp2=0;pp2<5;pp2=pp2+1) for (vv2=0;vv2<2;vv2=vv2+1) begin
        if (!worm_active[pp2][vv2] && buf_hd_vld[pp2][vv2]) begin
            // HEAD flit present, no active worm: use live RC output
            for (op_i=0;op_i<5;op_i=op_i+1)
                if (rc_port[pp2][vv2][op_i])
                    sa_req_reg[op_i*NUM_PORTS+pp2] = 1'b1;
        end else if (worm_active[pp2][vv2] && !buf_empty[pp2][vv2]) begin
            // Body/tail flit: use latched direction
            for (op_i=0;op_i<5;op_i=op_i+1)
                if (worm_out_port[pp2][vv2][op_i])
                    sa_req_reg[op_i*NUM_PORTS+pp2] = 1'b1;
        end
    end
end

switch_allocator #(.NUM_PORTS(NUM_PORTS),.NUM_VCS(NUM_VCS)) u_sa (
    .clk(clk),.rst_n(rst_n),
    .sa_req(sa_req_w),
    .sa_grant(sa_grant_w),
    .grant_in_packed(sa_grant_in_packed));

// Active VC per input port
// Priority: whichever VC has an active worm; VC0 default for heads.
reg [VC_W-1:0] sa_active_vc [0:4];
integer pp3, vv3;
always @(*) begin
    for (pp3=0;pp3<5;pp3=pp3+1) begin
        sa_active_vc[pp3] = 1'b0;
        // Prefer active worm VC; fall back to any head flit VC
        for (vv3=0;vv3<2;vv3=vv3+1) begin
            if (worm_active[pp3][vv3] && !buf_empty[pp3][vv3])
                sa_active_vc[pp3] = vv3[VC_W-1:0];
        end
        // If no worm active, pick a VC with a head flit
        if (!worm_active[pp3][0] && !worm_active[pp3][1]) begin
            for (vv3=0;vv3<2;vv3=vv3+1)
                if (buf_hd_vld[pp3][vv3])
                    sa_active_vc[pp3] = vv3[VC_W-1:0];
        end
    end
end

// ============================================================
// Worm state FSM – activated by SA grant on a head flit
integer pp, vv;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (pp=0;pp<5;pp=pp+1) for (vv=0;vv<2;vv=vv+1) begin
            worm_active[pp][vv]   <= 1'b0;
            worm_out_port[pp][vv] <= 5'b0;
        end
    end else begin
        for (pp=0;pp<5;pp=pp+1) for (vv=0;vv<2;vv=vv+1) begin
            if (buf_rd_en[pp][vv]) begin
                if (buf_hd_vld[pp][vv]) begin
                    // Head flit consumed by SA: activate worm, latch direction
                    // rc_port is valid here because head is still at FIFO head
                    // UNTIL the posedge advances rd_ptr.
                    worm_active[pp][vv]   <= 1'b1;
                    worm_out_port[pp][vv] <= rc_port[pp][vv];
                end else if (buf_out[pp][vv][FLIT_SIZE-3]) begin
                    // Tail flit consumed: release worm
                    worm_active[pp][vv] <= 1'b0;
                end
                // Body flit consumed: keep worm active (no change)
            end
        end
    end
end

// Buffer read enables
integer op2, pp4, vv4;
always @(*) begin
    for (pp4=0;pp4<5;pp4=pp4+1) for (vv4=0;vv4<2;vv4=vv4+1)
        buf_rd_en[pp4][vv4] = 1'b0;
    for (op2=0;op2<5;op2=op2+1)
        for (pp4=0;pp4<5;pp4=pp4+1)
            if (sa_grant_w[op2*NUM_PORTS+pp4])
                buf_rd_en[pp4][sa_active_vc[pp4]] = 1'b1;
end

// Crossbar
wire [NUM_PORTS*FLIT_SIZE-1:0] xbar_in_flat;
wire [NUM_PORTS*FLIT_SIZE-1:0] xbar_out_flat;
wire [NUM_PORTS-1:0]           xbar_out_valid;

genvar gxp;
generate
for (gxp=0;gxp<5;gxp=gxp+1) begin : g_xbar_in
    assign xbar_in_flat[gxp*FLIT_SIZE +: FLIT_SIZE] =
        (sa_active_vc[gxp] == 1'b0) ? buf_out[gxp][0] : buf_out[gxp][1];
end
endgenerate

switch #(.FLIT_SIZE(FLIT_SIZE),.NUM_PORTS(NUM_PORTS)) u_xbar (
    .in_flit_flat(xbar_in_flat),
    .grant(sa_grant_w),
    .out_flit_flat(xbar_out_flat),
    .out_valid(xbar_out_valid));

// Output connections
genvar gop;
generate
for (gop=0;gop<5;gop=gop+1) begin : g_out
    assign out_flit_flat[gop*FLIT_SIZE +: FLIT_SIZE] =
        xbar_out_flat[gop*FLIT_SIZE +: FLIT_SIZE];
    assign out_valid[gop] = xbar_out_valid[gop];
end
endgenerate

endmodule