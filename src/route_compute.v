`timescale 1ns/1ps

module route_compute #(
    parameter FLIT_SIZE  = 40,
    parameter COORD_W    = 4, 
    parameter ROUTER_X   = 0,
    parameter ROUTER_Y   = 0
)(
    // Head flit to evaluate
    input wire [FLIT_SIZE-1:0] head_flit,
    input wire head_valid,
    // Computed output port
    output reg [4:0]  out_port
);

    // Flit field extraction
    wire [COORD_W-1:0] dest_x = head_flit[FLIT_SIZE-4 -: COORD_W];
    wire [COORD_W-1:0] dest_y = head_flit[FLIT_SIZE-4-COORD_W -: COORD_W];

    // X-Y routing decision
    localparam LOCAL = 5'b00001;
    localparam NORTH = 5'b00010;
    localparam SOUTH = 5'b00100;
    localparam EAST  = 5'b01000;
    localparam WEST  = 5'b10000;

    wire signed [COORD_W:0] dx = $signed({1'b0, dest_x}) - $signed({1'b0, ROUTER_X[COORD_W-1:0]});
    wire signed [COORD_W:0] dy = $signed({1'b0, dest_y}) - $signed({1'b0, ROUTER_Y[COORD_W-1:0]});

    always @(*) begin
        if (!head_valid) begin
            out_port = 5'b0;
        end else if (dx > 0) begin
            out_port = EAST;
        end else if (dx < 0) begin
            out_port = WEST;
        end else if (dy > 0) begin
            out_port = SOUTH;
        end else if (dy < 0) begin
            out_port = NORTH;
        end else begin
            out_port = LOCAL;
        end
    end

endmodule