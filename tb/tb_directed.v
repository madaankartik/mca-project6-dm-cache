// ============================================================================
// tb_directed.v -- Self-checking DIRECTED testbench for the direct-mapped cache
//
// Covers: cold miss, temporal hit, spatial hit, conflict miss + eviction,
//         write hit (write-through), write miss (no-write-allocate),
//         full-cache fill, valid-bit clear on reset, hit/miss latency.
//
// Run:  make directed     (dumps sim/directed.vcd for GTKWave)
// ============================================================================
`timescale 1ns/1ps
module tb_directed;
    localparam LAT = 10;

    reg         clk = 0, rst = 1;
    reg         cpu_req = 0, cpu_we = 0;
    reg  [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire [31:0] cpu_rdata;
    wire        cpu_ready, cpu_hit;
    wire [31:0] stat_accesses, stat_hits, stat_misses;

    always #5 clk = ~clk;              // 100 MHz simulation clock

    cache_system #(.USE_CACHE(1), .CACHE_BYTES(1024), .BLOCK_BYTES(16), .MEM_LATENCY(LAT)) dut (
        .clk(clk), .rst(rst),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready), .cpu_hit(cpu_hit),
        .stat_accesses(stat_accesses), .stat_hits(stat_hits), .stat_misses(stat_misses)
    );

    // ---------------- golden (shadow) memory ----------------
    reg [31:0] shadow [0:65535];
    integer k;
    initial for (k = 0; k < 65536; k = k + 1) shadow[k] = {16'hC0DE, k[15:0]};

    // ---------------- bookkeeping ----------------
    integer pass = 0, fail = 0;
    reg  [31:0] r_data;
    reg         r_hit;
    integer     r_cyc;

    task access(input we, input [31:0] addr, input [31:0] wdata);
        begin
            @(negedge clk);
            cpu_req = 1; cpu_we = we; cpu_addr = addr; cpu_wdata = wdata;
            r_cyc = 1;
            @(negedge clk);
            cpu_req = 0;
            while (!cpu_ready) begin @(negedge clk); r_cyc = r_cyc + 1; end
            r_cyc  = r_cyc + 1;          // include the request cycle
            r_data = cpu_rdata;
            r_hit  = cpu_hit;
            if (we) shadow[addr[17:2]] = wdata;
        end
    endtask

    task check(input cond, input [8*64-1:0] name);
        begin
            if (cond) begin pass = pass + 1; $display("  [PASS] %0s", name); end
            else      begin fail = fail + 1; $display("  [FAIL] %0s", name); end
        end
    endtask

    task rd(input [31:0] addr, input exp_hit, input [8*64-1:0] name);
        begin
            access(1'b0, addr, 32'd0);
            $display("  RD  0x%08h -> data=0x%08h  %s  (%0d cycles)",
                     addr, r_data, r_hit ? "HIT " : "MISS", r_cyc);
            check(r_hit == exp_hit && r_data == shadow[addr[17:2]], name);
        end
    endtask

    task wr(input [31:0] addr, input [31:0] data, input exp_hit, input [8*64-1:0] name);
        begin
            access(1'b1, addr, data);
            $display("  WR  0x%08h <- data=0x%08h  %s  (%0d cycles)",
                     addr, data, r_hit ? "HIT " : "MISS", r_cyc);
            check(r_hit == exp_hit && dut.u_mem.mem[addr[17:2]] == data, name);
        end
    endtask

    integer i, hits_before;

    initial begin
        $dumpfile("sim/directed.vcd");
        $dumpvars(0, tb_directed);

        repeat (3) @(negedge clk);
        rst = 0;

        $display("\n=== T1: cold (compulsory) miss ===");
        rd(32'h0000_0040, 1'b0, "T1 cold miss returns memory data");
        check(r_cyc == LAT + 4, "T1 read-miss latency = LAT+4 cycles");

        $display("\n=== T2: temporal locality ===");
        rd(32'h0000_0040, 1'b1, "T2 same address hits");
        check(r_cyc == 2, "T2 read-hit latency = 2 cycles");

        $display("\n=== T3: spatial locality (same 16-byte block) ===");
        rd(32'h0000_0044, 1'b1, "T3a word 1 of block hits");
        rd(32'h0000_004C, 1'b1, "T3b word 3 of block hits");

        $display("\n=== T4: conflict miss (same index, different tag) ===");
        rd(32'h0000_0440, 1'b0, "T4a 0x440 maps to index 4 -> conflict miss");
        rd(32'h0000_0040, 1'b0, "T4b 0x040 was evicted -> miss again");

        $display("\n=== T5: write hit (write-through) ===");
        wr(32'h0000_0048, 32'hDEAD_BEEF, 1'b1, "T5a write hit updates main memory");
        rd(32'h0000_0048, 1'b1, "T5b read-after-write hits with new data");

        $display("\n=== T6: write miss (no-write-allocate) ===");
        wr(32'h0000_2000, 32'hCAFE_F00D, 1'b0, "T6a write miss goes to memory only");
        rd(32'h0000_2000, 1'b0, "T6b block not allocated -> read misses, data correct");
        rd(32'h0000_2004, 1'b1, "T6c neighbour word now hits");

        $display("\n=== T7: fill all 64 lines, then re-read ===");
        for (i = 0; i < 64; i = i + 1) access(1'b0, 32'h0001_0000 + i*16, 0);
        @(negedge clk); hits_before = stat_hits;   // let counter settle
        for (i = 0; i < 64; i = i + 1) access(1'b0, 32'h0001_0000 + i*16 + 4, 0);
        @(negedge clk);
        check(stat_hits - hits_before == 64, "T7 all 64 lines resident (64/64 hits)");

        $display("\n=== T8: reset invalidates every line ===");
        @(negedge clk); rst = 1; @(negedge clk); rst = 0;
        check(stat_accesses == 0, "T8a counters cleared by reset");
        rd(32'h0001_0004, 1'b0, "T8b previously cached line now misses");

        $display("\n==================================================");
        $display("  DIRECTED TESTS: %0d passed, %0d failed", pass, fail);
        if (fail == 0) $display("  RESULT: ALL TESTS PASSED");
        else           $display("  RESULT: FAILURES PRESENT");
        $display("==================================================\n");
        #20 $finish;
    end

    initial begin
        #2_000_000 $display("TIMEOUT"); $finish;
    end
endmodule
