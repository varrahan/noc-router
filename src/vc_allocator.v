`timescale 1ns/1ps
 
module vc_allocator #(
    parameter NUM_PORTS = 5,
    parameter NUM_VCS   = 2
)(
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire [NUM_PORTS*NUM_VCS-1:0]    vc_req,
    // out_port_req_flat: 3 bits per (port,vc) pair
    input  wire [NUM_PORTS*NUM_VCS*3-1:0]  out_port_req_flat,
    input  wire [NUM_PORTS*NUM_VCS-1:0]    ds_credits,
    // vc_grant_flat: 1 bit per (port,vc) – which downstream VC won (bit 0)
    output reg  [NUM_PORTS*NUM_VCS-1:0]    vc_grant_flat,
    output reg  [NUM_PORTS*NUM_VCS-1:0]    vc_grant_vld
);
 
localparam VC_W = 1;
 
reg [VC_W-1:0] rr_ptr [0:NUM_PORTS-1];
 
integer pp, vv, k, p_out, cand;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vc_grant_flat <= 0;
        vc_grant_vld  <= 0;
        for (pp=0;pp<NUM_PORTS;pp=pp+1) rr_ptr[pp] <= 0;
    end else begin
        vc_grant_vld  <= 0;
        vc_grant_flat <= 0;
        for (pp=0;pp<NUM_PORTS;pp=pp+1) begin
            for (vv=0;vv<NUM_VCS;vv=vv+1) begin
                if (vc_req[pp*NUM_VCS+vv]) begin
                    p_out = out_port_req_flat[(pp*NUM_VCS+vv)*3 +: 3];
                    for (k=0;k<NUM_VCS;k=k+1) begin
                        cand = (rr_ptr[p_out] + k) % NUM_VCS;
                        if (ds_credits[p_out*NUM_VCS+cand] &&
                            !vc_grant_vld[pp*NUM_VCS+vv]) begin
                            vc_grant_flat[pp*NUM_VCS+vv] <= cand[VC_W-1:0];
                            vc_grant_vld[pp*NUM_VCS+vv]  <= 1;
                            rr_ptr[p_out]                <= (cand+1) % NUM_VCS;
                        end
                    end
                end
            end
        end
    end
end
endmodule