// ============================================================================
// addr_decoder.v
// Splits a 32-bit byte address into TAG | INDEX | BLOCK OFFSET fields.
//
// Default configuration (1 KB cache, 16-byte blocks, 32-bit address):
//   offset = addr[3:0]   (4 bits)  -> word select = addr[3:2]
//   index  = addr[9:4]   (6 bits)  -> 64 cache lines
//   tag    = addr[31:10] (22 bits)
// ============================================================================
`timescale 1ns/1ps
module addr_decoder #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    // derived
    parameter NUM_LINES   = CACHE_BYTES / BLOCK_BYTES,
    parameter OFFSET_W    = $clog2(BLOCK_BYTES),
    parameter INDEX_W     = $clog2(NUM_LINES),
    parameter TAG_W       = ADDR_W - INDEX_W - OFFSET_W,
    parameter WSEL_W      = (OFFSET_W > 2) ? (OFFSET_W - 2) : 1
)(
    input  wire [ADDR_W-1:0]   addr,
    output wire [TAG_W-1:0]    tag,
    output wire [INDEX_W-1:0]  index,
    output wire [OFFSET_W-1:0] offset,
    output wire [WSEL_W-1:0]   word_sel   // which 32-bit word inside the block
);
    assign offset   = addr[OFFSET_W-1:0];
    assign index    = addr[OFFSET_W+INDEX_W-1:OFFSET_W];
    assign tag      = addr[ADDR_W-1:OFFSET_W+INDEX_W];
    generate
        if (OFFSET_W > 2) begin : g_wsel
            assign word_sel = addr[OFFSET_W-1:2];
        end else begin : g_wsel1
            assign word_sel = 1'b0;          // 4-byte blocks: one word per block
        end
    endgenerate
endmodule
