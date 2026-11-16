// ============================================================================
// data_ram.v
// Cache data storage: NUM_LINES blocks of BLOCK_BYTES each.
//   * block_we : write a whole block (refill from main memory)
//   * word_we  : write a single 32-bit word inside a block (CPU write hit)
// Asynchronous read of the selected 32-bit word.
// ============================================================================
`timescale 1ns/1ps
module data_ram #(
    parameter NUM_LINES   = 64,
    parameter BLOCK_BYTES = 16,
    parameter INDEX_W     = $clog2(NUM_LINES),
    parameter BLOCK_W     = BLOCK_BYTES * 8,
    parameter WORDS       = BLOCK_BYTES / 4,
    parameter WSEL_W      = (WORDS > 1) ? $clog2(WORDS) : 1
)(
    input  wire               clk,
    input  wire [INDEX_W-1:0] index,
    // block (refill) write port
    input  wire               block_we,
    input  wire [BLOCK_W-1:0] block_in,
    // word (CPU store) write port
    input  wire               word_we,
    input  wire [WSEL_W-1:0]  word_sel,
    input  wire [31:0]        word_in,
    // read port
    output wire [31:0]        word_out
);
    reg [BLOCK_W-1:0] mem [0:NUM_LINES-1];

    integer i;
    initial for (i = 0; i < NUM_LINES; i = i + 1) mem[i] = {BLOCK_W{1'b0}};

    always @(posedge clk) begin
        if (block_we)
            mem[index] <= block_in;
        else if (word_we)
            mem[index][word_sel*32 +: 32] <= word_in;
    end

    wire [BLOCK_W-1:0] blk = mem[index];
    assign word_out = blk[word_sel*32 +: 32];
endmodule
