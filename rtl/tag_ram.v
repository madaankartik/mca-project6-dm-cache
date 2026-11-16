// ============================================================================
// tag_ram.v
// One TAG entry per cache line. Synchronous write, asynchronous read.
// ============================================================================
`timescale 1ns/1ps
module tag_ram #(
    parameter NUM_LINES = 64,
    parameter TAG_W     = 22,
    parameter INDEX_W   = $clog2(NUM_LINES)
)(
    input  wire               clk,
    input  wire               we,
    input  wire [INDEX_W-1:0] index,
    input  wire [TAG_W-1:0]   tag_in,
    output wire [TAG_W-1:0]   tag_out
);
    reg [TAG_W-1:0] mem [0:NUM_LINES-1];

    integer i;
    initial for (i = 0; i < NUM_LINES; i = i + 1) mem[i] = {TAG_W{1'b0}};

    always @(posedge clk)
        if (we) mem[index] <= tag_in;

    assign tag_out = mem[index];
endmodule
