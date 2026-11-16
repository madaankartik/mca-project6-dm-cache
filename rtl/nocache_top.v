// ============================================================================
// nocache_top.v -- BASELINE: CPU talks directly to main memory (no cache)
// Same CPU / memory interface as cache_top, so the same testbench and traces
// can be run on both designs for a fair cycle-count comparison.
// ============================================================================
`timescale 1ns/1ps
module nocache_top #(
    parameter ADDR_W      = 32,
    parameter BLOCK_BYTES = 16,
    parameter OFFSET_W    = $clog2(BLOCK_BYTES),
    parameter BLOCK_W     = BLOCK_BYTES * 8,
    parameter WORDS       = BLOCK_BYTES / 4,
    parameter WSEL_W      = (WORDS > 1) ? $clog2(WORDS) : 1
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               cpu_req,
    input  wire               cpu_we,
    input  wire [ADDR_W-1:0]  cpu_addr,
    input  wire [31:0]        cpu_wdata,
    output wire [31:0]        cpu_rdata,
    output wire               cpu_ready,
    output wire               cpu_hit,
    output wire               mem_req,
    output wire               mem_we,
    output wire [ADDR_W-1:0]  mem_addr,
    output wire [31:0]        mem_wdata,
    input  wire [BLOCK_W-1:0] mem_rdata,
    input  wire               mem_ready
);
    reg              busy;
    reg [ADDR_W-1:0] req_addr;
    reg [31:0]       req_wdata;
    reg              req_we;

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0; req_addr <= 0; req_wdata <= 0; req_we <= 1'b0;
        end else if (!busy && cpu_req) begin
            busy <= 1'b1; req_addr <= cpu_addr; req_wdata <= cpu_wdata; req_we <= cpu_we;
        end else if (busy && mem_ready) begin
            busy <= 1'b0;
        end
    end

    wire [WSEL_W-1:0] word_sel = (WORDS > 1) ? req_addr[OFFSET_W-1:2] : 0;

    assign mem_req   = busy;
    assign mem_we    = req_we;
    assign mem_addr  = req_we ? {req_addr[ADDR_W-1:2], 2'b00}
                              : {req_addr[ADDR_W-1:OFFSET_W], {OFFSET_W{1'b0}}};
    assign mem_wdata = req_wdata;
    assign cpu_ready = busy && mem_ready;
    assign cpu_rdata = mem_rdata[word_sel*32 +: 32];
    assign cpu_hit   = 1'b0;
endmodule
