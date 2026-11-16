// ============================================================================
// valid_ram.v
// One VALID bit per cache line. Implemented as a flip-flop vector so that a
// single synchronous reset invalidates the whole cache in one cycle.
// ============================================================================
`timescale 1ns/1ps
module valid_ram #(
    parameter NUM_LINES = 64,
    parameter INDEX_W   = $clog2(NUM_LINES)
)(
    input  wire               clk,
    input  wire               rst,       // synchronous, active-high: invalidate all
    input  wire               we,        // set valid bit of 'index'
    input  wire [INDEX_W-1:0] index,
    input  wire               valid_in,
    output wire               valid_out
);
    reg [NUM_LINES-1:0] valid;

    always @(posedge clk) begin
        if (rst)
            valid <= {NUM_LINES{1'b0}};
        else if (we)
            valid[index] <= valid_in;
    end

    assign valid_out = valid[index];
endmodule
