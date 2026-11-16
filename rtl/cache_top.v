// ============================================================================
// cache_top.v -- Direct-Mapped Cache Controller (synthesizable top level)
//
//   CPU  <==>  [ addr_decoder | tag_ram | valid_ram | data_ram |
//                tag_comparator | cache_fsm | perf counters ]  <==>  Main memory
//
// Default: 1 KB, 16-byte blocks, 64 lines, 32-bit byte addresses.
// Policy : write-through, no-write-allocate.
// ============================================================================
`timescale 1ns/1ps
module cache_top #(
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    // derived
    parameter NUM_LINES   = CACHE_BYTES / BLOCK_BYTES,
    parameter OFFSET_W    = $clog2(BLOCK_BYTES),
    parameter INDEX_W     = $clog2(NUM_LINES),
    parameter TAG_W       = ADDR_W - INDEX_W - OFFSET_W,
    parameter BLOCK_W     = BLOCK_BYTES * 8,
    parameter WORDS       = BLOCK_BYTES / 4,
    parameter WSEL_W      = (WORDS > 1) ? $clog2(WORDS) : 1
)(
    input  wire               clk,
    input  wire               rst,
    // ---------------- CPU interface ----------------
    input  wire               cpu_req,
    input  wire               cpu_we,
    input  wire [ADDR_W-1:0]  cpu_addr,
    input  wire [31:0]        cpu_wdata,
    output wire [31:0]        cpu_rdata,
    output wire               cpu_ready,
    output wire               cpu_hit,
    // ---------------- Main-memory interface ----------------
    output wire               mem_req,
    output wire               mem_we,
    output wire [ADDR_W-1:0]  mem_addr,
    output wire [31:0]        mem_wdata,
    input  wire [BLOCK_W-1:0] mem_rdata,
    input  wire               mem_ready,
    // ---------------- Performance counters ----------------
    output reg  [31:0]        stat_accesses,
    output reg  [31:0]        stat_hits,
    output reg  [31:0]        stat_misses,
    output wire [1:0]         fsm_state
);
    // ---------------- request latch ----------------
    reg [ADDR_W-1:0] req_addr;
    reg [31:0]       req_wdata;
    reg              req_we;
    wire             latch_req;

    always @(posedge clk) begin
        if (rst) begin
            req_addr  <= {ADDR_W{1'b0}};
            req_wdata <= 32'd0;
            req_we    <= 1'b0;
        end else if (latch_req) begin
            req_addr  <= cpu_addr;
            req_wdata <= cpu_wdata;
            req_we    <= cpu_we;
        end
    end

    // ---------------- address decode ----------------
    wire [TAG_W-1:0]    tag;
    wire [INDEX_W-1:0]  index;
    wire [OFFSET_W-1:0] offset;
    wire [WSEL_W-1:0]   word_sel;

    addr_decoder #(.ADDR_W(ADDR_W), .CACHE_BYTES(CACHE_BYTES), .BLOCK_BYTES(BLOCK_BYTES))
    u_dec (.addr(req_addr), .tag(tag), .index(index), .offset(offset), .word_sel(word_sel));

    // ---------------- storage arrays ----------------
    wire [TAG_W-1:0] tag_stored;
    wire             valid_bit;
    wire             tag_we, valid_we, data_block_we, data_word_we;

    tag_ram #(.NUM_LINES(NUM_LINES), .TAG_W(TAG_W))
    u_tag (.clk(clk), .we(tag_we), .index(index), .tag_in(tag), .tag_out(tag_stored));

    valid_ram #(.NUM_LINES(NUM_LINES))
    u_valid (.clk(clk), .rst(rst), .we(valid_we), .index(index),
             .valid_in(1'b1), .valid_out(valid_bit));

    data_ram #(.NUM_LINES(NUM_LINES), .BLOCK_BYTES(BLOCK_BYTES))
    u_data (.clk(clk), .index(index),
            .block_we(data_block_we), .block_in(mem_rdata),
            .word_we(data_word_we), .word_sel(word_sel), .word_in(req_wdata),
            .word_out(cpu_rdata));

    // ---------------- hit detection ----------------
    wire hit;
    tag_comparator #(.TAG_W(TAG_W))
    u_cmp (.tag_req(tag), .tag_stored(tag_stored), .valid(valid_bit), .hit(hit));

    // ---------------- controller ----------------
    wire first_lookup;
    cache_fsm u_fsm (
        .clk(clk), .rst(rst),
        .cpu_req(cpu_req), .req_we(req_we), .cpu_ready(cpu_ready), .resp_hit(cpu_hit),
        .hit(hit),
        .latch_req(latch_req), .tag_we(tag_we), .valid_we(valid_we),
        .data_block_we(data_block_we), .data_word_we(data_word_we),
        .first_lookup(first_lookup),
        .mem_req(mem_req), .mem_we(mem_we), .mem_ready(mem_ready),
        .state_o(fsm_state)
    );

    // ---------------- main-memory address ----------------
    // Refill uses the block-aligned address, write-through uses the word address.
    wire [ADDR_W-1:0] block_addr = {req_addr[ADDR_W-1:OFFSET_W], {OFFSET_W{1'b0}}};
    assign mem_addr  = mem_we ? {req_addr[ADDR_W-1:2], 2'b00} : block_addr;
    assign mem_wdata = req_wdata;

    // ---------------- performance counters ----------------
    always @(posedge clk) begin
        if (rst) begin
            stat_accesses <= 32'd0;
            stat_hits     <= 32'd0;
            stat_misses   <= 32'd0;
        end else if (first_lookup) begin
            stat_accesses <= stat_accesses + 1'b1;
            if (hit) stat_hits   <= stat_hits   + 1'b1;
            else     stat_misses <= stat_misses + 1'b1;
        end
    end
endmodule
