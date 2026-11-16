// ============================================================================
// main_memory.v -- Behavioural main-memory model (simulation only)
//
// * Block-wide read port  (BLOCK_BYTES per access, used for cache refill)
// * Word-wide  write port (32-bit, used for write-through stores)
// * Fixed access latency of LATENCY cycles; mem_ready pulses for 1 cycle.
// * Initial contents follow a known pattern so the testbench can check data:
//       word at byte address A  =  {16'hC0DE, A[17:2]}  (see init_pattern)
// ============================================================================
`timescale 1ns/1ps
module main_memory #(
    parameter ADDR_W      = 32,
    parameter BLOCK_BYTES = 16,
    parameter MEM_BYTES   = 262144,          // 256 KB backing store
    parameter LATENCY     = 10,              // cycles per access
    parameter BLOCK_W     = BLOCK_BYTES * 8,
    parameter WORDS       = BLOCK_BYTES / 4,
    parameter MEM_WORDS   = MEM_BYTES / 4,
    parameter MWA_W       = $clog2(MEM_WORDS)
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               mem_req,
    input  wire               mem_we,
    input  wire [ADDR_W-1:0]  mem_addr,      // byte address
    input  wire [31:0]        mem_wdata,
    output reg  [BLOCK_W-1:0] mem_rdata,
    output reg                mem_ready
);
    reg [31:0] mem [0:MEM_WORDS-1];
    reg [15:0] cnt;

    // statistics: how many transactions reached main memory
    integer reads  = 0;
    integer writes = 0;

    integer i;
    initial for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = {16'hC0DE, i[15:0]};

    wire [MWA_W-1:0] word_addr  = mem_addr[MWA_W+1:2];
    wire [MWA_W-1:0] block_base = word_addr & ~(WORDS - 1);

    integer w;
    always @(posedge clk) begin
        if (rst) begin
            cnt       <= 0;
            mem_ready <= 1'b0;
        end else begin
            mem_ready <= 1'b0;
            if (mem_req && !mem_ready) begin
                if (cnt == LATENCY - 1) begin
                    cnt       <= 0;
                    mem_ready <= 1'b1;
                    if (mem_we) begin
                        mem[word_addr] <= mem_wdata;
                        writes = writes + 1;
                    end else begin
                        for (w = 0; w < WORDS; w = w + 1)
                            mem_rdata[w*32 +: 32] <= mem[block_base + w];
                        reads = reads + 1;
                    end
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end else begin
                cnt <= 0;
            end
        end
    end
endmodule
