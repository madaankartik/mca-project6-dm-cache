// ============================================================================
// cache_system.v -- Simulation wrapper: CPU port + (cache | no-cache) + memory
//   USE_CACHE = 1 : cache_top in front of main_memory
//   USE_CACHE = 0 : nocache_top (baseline) in front of main_memory
// ============================================================================
`timescale 1ns/1ps
module cache_system #(
    parameter USE_CACHE   = 1,
    parameter ADDR_W      = 32,
    parameter CACHE_BYTES = 1024,
    parameter BLOCK_BYTES = 16,
    parameter MEM_LATENCY = 10,
    parameter BLOCK_W     = BLOCK_BYTES * 8
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              cpu_req,
    input  wire              cpu_we,
    input  wire [ADDR_W-1:0] cpu_addr,
    input  wire [31:0]       cpu_wdata,
    output wire [31:0]       cpu_rdata,
    output wire              cpu_ready,
    output wire              cpu_hit,
    output wire [31:0]       stat_accesses,
    output wire [31:0]       stat_hits,
    output wire [31:0]       stat_misses
);
    wire               mem_req, mem_we, mem_ready;
    wire [ADDR_W-1:0]  mem_addr;
    wire [31:0]        mem_wdata;
    wire [BLOCK_W-1:0] mem_rdata;

    generate
        if (USE_CACHE) begin : g_cache
            wire [1:0] fsm_state;
            cache_top #(.ADDR_W(ADDR_W), .CACHE_BYTES(CACHE_BYTES), .BLOCK_BYTES(BLOCK_BYTES))
            u_cache (
                .clk(clk), .rst(rst),
                .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
                .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready), .cpu_hit(cpu_hit),
                .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
                .mem_rdata(mem_rdata), .mem_ready(mem_ready),
                .stat_accesses(stat_accesses), .stat_hits(stat_hits), .stat_misses(stat_misses),
                .fsm_state(fsm_state)
            );
        end else begin : g_nocache
            nocache_top #(.ADDR_W(ADDR_W), .BLOCK_BYTES(BLOCK_BYTES))
            u_nocache (
                .clk(clk), .rst(rst),
                .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
                .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready), .cpu_hit(cpu_hit),
                .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
                .mem_rdata(mem_rdata), .mem_ready(mem_ready)
            );
            assign stat_accesses = 32'd0;
            assign stat_hits     = 32'd0;
            assign stat_misses   = 32'd0;
        end
    endgenerate

    main_memory #(.ADDR_W(ADDR_W), .BLOCK_BYTES(BLOCK_BYTES), .LATENCY(MEM_LATENCY))
    u_mem (
        .clk(clk), .rst(rst),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );
endmodule
