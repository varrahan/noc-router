`timescale 1ns/1ps

module switch #(
    parameter FLIT_SIZE = 40,
    parameter NUM_PORTS = 5
)(
    input  wire [NUM_PORTS*FLIT_SIZE-1:0]  in_flit_flat,
    input  wire [NUM_PORTS*NUM_PORTS-1:0]  grant,
    output reg  [NUM_PORTS*FLIT_SIZE-1:0]  out_flit_flat,
    output reg  [NUM_PORTS-1:0]            out_valid
);
 
integer out_p, in_p;
always @(*) begin
    out_flit_flat = {(NUM_PORTS*FLIT_SIZE){1'b0}};
    out_valid     = {NUM_PORTS{1'b0}};
    for (out_p=0; out_p<NUM_PORTS; out_p=out_p+1) begin
        for (in_p=0; in_p<NUM_PORTS; in_p=in_p+1) begin
            if (grant[out_p*NUM_PORTS + in_p]) begin
                out_flit_flat[out_p*FLIT_SIZE +: FLIT_SIZE] =
                    in_flit_flat[in_p*FLIT_SIZE +: FLIT_SIZE];
                out_valid[out_p] = 1'b1;
            end
        end
    end
end
endmodule
 