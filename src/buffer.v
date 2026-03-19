`timescale 1ns/1ps

module input_buffer #(
    parameter FLIT_SIZE    = 40,
    parameter BUFFER_DEPTH = 8
)(
    input wire clk,
    input wire rst_n,
    // Write port
    input wire wr_en,
    input wire [FLIT_SIZE-1:0] flit_in,
    // Read port
    input wire rd_en,
    output wire [FLIT_SIZE-1:0] flit_out,
    // Status signals
    output wire full,
    output wire empty,
    output wire valid_head,
    // Credit return to upstream
    output wire credit_out
);

    localparam ADDR_W = $clog2(BUFFER_DEPTH);
    reg [FLIT_SIZE-1:0] mem [0:BUFFER_DEPTH-1];
    reg [ADDR_W:0] wr_ptr;
    reg [ADDR_W:0] rd_ptr;
    wire [ADDR_W-1:0] wr_addr = wr_ptr[ADDR_W-1:0];
    wire [ADDR_W-1:0] rd_addr = rd_ptr[ADDR_W-1:0];
    assign full  = (wr_ptr[ADDR_W] != rd_ptr[ADDR_W]) && (wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]);
    assign empty = (wr_ptr == rd_ptr);

    // Write logic
    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wr_addr] <= flit_in;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wr_ptr <= {(ADDR_W+1){1'b0}};
        else if (wr_en && !full)
            wr_ptr <= wr_ptr + 1'b1;
    end

    // Read logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_ptr <= {(ADDR_W+1){1'b0}};
        else if (rd_en && !empty)
            rd_ptr <= rd_ptr + 1'b1;
    end

    assign flit_out = mem[rd_addr];
    assign valid_head = !empty && flit_out[FLIT_SIZE-2];
    assign credit_out = rd_en && !empty;

endmodule