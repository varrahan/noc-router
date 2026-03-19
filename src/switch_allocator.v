`timescale 1ns/1ps
 
module switch_allocator #(
    parameter NUM_PORTS = 5,
    parameter NUM_VCS   = 2
)(
    input wire clk,
    input wire rst_n,
    input wire [NUM_PORTS*NUM_PORTS-1:0] sa_req,
    output reg [NUM_PORTS*NUM_PORTS-1:0] sa_grant,
    // grant_in_packed: 3 bits per output port (enough for 5 ports: ceil(log2(5))=3)
    output reg [NUM_PORTS*3-1:0] grant_in_packed
);
 
reg [2:0] rr_ptr [0:NUM_PORTS-1];
 
integer op, k, w;
reg found;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sa_grant         <= 0;
        grant_in_packed  <= 0;
        for (op=0;op<NUM_PORTS;op=op+1) begin
            rr_ptr[op] <= 0;
        end
    end else begin
        sa_grant        <= 0;
        grant_in_packed <= 0;
        for (op=0;op<NUM_PORTS;op=op+1) begin
            found = 0;
            for (k=0;k<NUM_PORTS;k=k+1) begin
                if (!found) begin
                    w = (rr_ptr[op]+k) % NUM_PORTS;
                    if (sa_req[op*NUM_PORTS+w]) begin
                        sa_grant[op*NUM_PORTS+w]  <= 1;
                        grant_in_packed[op*3 +: 3]<= w[2:0];
                        rr_ptr[op]                <= (w+1) % NUM_PORTS;
                        found = 1;
                    end
                end
            end
        end
    end
end
endmodule