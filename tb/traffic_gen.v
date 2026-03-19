`timescale 1ns/1ps

module traffic_gen #(
    parameter FLIT_SIZE  = 40,
    parameter COORD_W    = 4,
    parameter NUM_VCS    = 2,
    parameter SRC_X      = 0,
    parameter SRC_Y      = 0,
    parameter DST_X      = 1,
    parameter DST_Y      = 1,
    parameter PKT_LEN    = 4,
    parameter SEED       = 32'hDEAD_BEEF,
    parameter BUFFER_DEPTH = 8
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      inject_en,
    // credit_in: one bit per VC (from router credit_flat slice)
    input  wire [NUM_VCS-1:0]        credit_in,
    // Which VC to inject on (binary encoded, not one-hot)
    input  wire                      vc_sel_in,   // 1-bit for NUM_VCS=2
    output reg  [FLIT_SIZE-1:0]      flit_out,
    output reg                       flit_valid,
    output reg  [NUM_VCS-1:0]        vc_sel_out,  // one-hot to router
    output reg  [31:0]               pkt_count,
    output reg  [31:0]               flit_count
);

// Credit counter
localparam CNTW = 4; // log2(BUFFER_DEPTH+1)
reg [CNTW-1:0] credits;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) credits <= BUFFER_DEPTH[CNTW-1:0];
    else begin
        case ({flit_valid, credit_in[vc_sel_in]})
            2'b01: if (credits < BUFFER_DEPTH) credits <= credits + 1;
            2'b10: if (credits > 0)            credits <= credits - 1;
            default: ;
        endcase
    end
end

// LFSR payload generator
reg [31:0] lfsr;
wire fb = lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0];
always @(posedge clk or negedge rst_n)
    if (!rst_n) lfsr <= SEED;
    else if (flit_valid) lfsr <= {lfsr[30:0], fb};

// Flit counter within packet
reg [7:0] flit_idx;
wire is_head = (flit_idx == 0);
wire is_tail = (flit_idx == PKT_LEN-1);

// Assemble flit
wire [FLIT_SIZE-1:0] flit_next;
localparam PAY_W = FLIT_SIZE - 3 - 2*COORD_W;

assign flit_next = {
    1'b1,                         // valid
    is_head,                      // head
    is_tail,                      // tail
    DST_X[COORD_W-1:0],          // dest_x
    DST_Y[COORD_W-1:0],          // dest_y
    lfsr[PAY_W-1:0]              // payload
};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        flit_out   <= 0;
        flit_valid <= 0;
        vc_sel_out <= 1;          // default VC0 one-hot
        flit_idx   <= 0;
        pkt_count  <= 0;
        flit_count <= 0;
    end else begin
        flit_valid <= 0;
        vc_sel_out <= (1 << vc_sel_in);
        if (inject_en && credits > 0) begin
            flit_out   <= flit_next;
            flit_valid <= 1;
            flit_count <= flit_count + 1;
            if (is_tail) begin
                flit_idx  <= 0;
                pkt_count <= pkt_count + 1;
            end else
                flit_idx <= flit_idx + 1;
        end
    end
end
endmodule