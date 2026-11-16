// ============================================================================
// tb_trace.v -- TRACE-DRIVEN, self-checking testbench
//
// Reads a memory-access trace, drives it through cache_system and checks:
//   * every load returns the correct data (against a shadow memory)
//   * every hit/miss decision matches the Python reference model
// Writes a one-line summary (key=value) used by the analysis scripts.
//
// Plusargs : +TRACE=<file> +EXPECT=<file> +OUT=<file> [+VCD=<file>]
// Params   : -Ptb_trace.USE_CACHE=0/1 -Ptb_trace.CACHE_BYTES=.. etc.
// Trace fmt: "<op> <addr_hex> <data_hex>" per line, op 0 = load, 1 = store
// Expect   : one 0/1 per line (1 = hit) -- produced by model/cache_model.py
// ============================================================================
`timescale 1ns/1ps
module tb_trace;
    parameter USE_CACHE   = 1;
    parameter CACHE_BYTES = 1024;
    parameter BLOCK_BYTES = 16;
    parameter MEM_LATENCY = 10;

    reg         clk = 0, rst = 1;
    reg         cpu_req = 0, cpu_we = 0;
    reg  [31:0] cpu_addr = 0, cpu_wdata = 0;
    wire [31:0] cpu_rdata;
    wire        cpu_ready, cpu_hit;
    wire [31:0] stat_accesses, stat_hits, stat_misses;

    always #5 clk = ~clk;

    cache_system #(.USE_CACHE(USE_CACHE), .CACHE_BYTES(CACHE_BYTES),
                   .BLOCK_BYTES(BLOCK_BYTES), .MEM_LATENCY(MEM_LATENCY)) dut (
        .clk(clk), .rst(rst),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready), .cpu_hit(cpu_hit),
        .stat_accesses(stat_accesses), .stat_hits(stat_hits), .stat_misses(stat_misses)
    );

    reg [31:0] shadow [0:65535];
    integer k;
    initial for (k = 0; k < 65536; k = k + 1) shadow[k] = {16'hC0DE, k[15:0]};

    reg [1023:0] trace_f, expect_f, out_f, vcd_f;
    integer fd_t, fd_e, fd_o, rc, rc_e;
    integer op, exp_hit;
    reg [31:0] addr, data;

    integer n = 0, loads = 0, stores = 0;
    integer data_err = 0, hit_err = 0;
    integer cyc, total_cycles = 0, load_cycles = 0, store_cycles = 0;
    integer hit_lat_sum = 0, hit_cnt_l = 0, miss_lat_sum = 0, miss_cnt_l = 0;

    initial begin
        if (!$value$plusargs("TRACE=%s",  trace_f))  begin $display("need +TRACE");  $finish; end
        if (!$value$plusargs("OUT=%s",    out_f))    out_f = "sim/trace_result.txt";
        fd_e = 0;
        if ($value$plusargs("EXPECT=%s", expect_f)) fd_e = $fopen(expect_f, "r");
        if ($value$plusargs("VCD=%s", vcd_f)) begin
            $dumpfile(vcd_f);
            $dumpvars(0, tb_trace);
        end
        fd_t = $fopen(trace_f, "r");
        if (fd_t == 0) begin $display("cannot open trace"); $finish; end

        repeat (3) @(negedge clk);
        rst = 0;

        while (!$feof(fd_t)) begin
            rc = $fscanf(fd_t, "%d %h %h\n", op, addr, data);
            if (rc == 3) begin
                // ---- issue request ----
                @(negedge clk);
                cpu_req = 1; cpu_we = op[0]; cpu_addr = addr; cpu_wdata = data;
                cyc = 1;
                @(negedge clk);
                cpu_req = 0;
                while (!cpu_ready) begin @(negedge clk); cyc = cyc + 1; end
                cyc = cyc + 1;
                total_cycles = total_cycles + cyc;
                n = n + 1;

                if (op == 0) begin
                    loads = loads + 1;
                    load_cycles = load_cycles + cyc;
                    if (cpu_rdata !== shadow[addr[17:2]]) begin
                        data_err = data_err + 1;
                        if (data_err < 5)
                            $display("DATA ERROR @%0d addr=%h got=%h exp=%h",
                                     n, addr, cpu_rdata, shadow[addr[17:2]]);
                    end
                    if (cpu_hit) begin hit_lat_sum = hit_lat_sum + cyc; hit_cnt_l = hit_cnt_l + 1; end
                    else         begin miss_lat_sum = miss_lat_sum + cyc; miss_cnt_l = miss_cnt_l + 1; end
                end else begin
                    stores = stores + 1;
                    store_cycles = store_cycles + cyc;
                    shadow[addr[17:2]] = data;
                end

                if (fd_e != 0 && USE_CACHE) begin
                    rc_e = $fscanf(fd_e, "%d\n", exp_hit);
                    if (rc_e == 1 && exp_hit != cpu_hit) begin
                        hit_err = hit_err + 1;
                        if (hit_err < 5)
                            $display("HIT/MISS MISMATCH @%0d addr=%h rtl=%0d model=%0d",
                                     n, addr, cpu_hit, exp_hit);
                    end
                end
            end
        end

        repeat (2) @(negedge clk);          // let perf counters settle
        fd_o = $fopen(out_f, "w");
        $fwrite(fd_o, "use_cache=%0d cache_bytes=%0d block_bytes=%0d mem_latency=%0d ",
                USE_CACHE, CACHE_BYTES, BLOCK_BYTES, MEM_LATENCY);
        $fwrite(fd_o, "accesses=%0d loads=%0d stores=%0d hits=%0d misses=%0d ",
                n, loads, stores, stat_hits, stat_misses);
        $fwrite(fd_o, "total_cycles=%0d load_cycles=%0d store_cycles=%0d ",
                total_cycles, load_cycles, store_cycles);
        $fwrite(fd_o, "load_hits=%0d load_hit_cycles=%0d load_misses=%0d load_miss_cycles=%0d ",
                hit_cnt_l, hit_lat_sum, miss_cnt_l, miss_lat_sum);
        $fwrite(fd_o, "mem_reads=%0d mem_writes=%0d data_errors=%0d hitmiss_errors=%0d\n",
                dut.u_mem.reads, dut.u_mem.writes, data_err, hit_err);
        $fclose(fd_o);

        $display("%0s : %0d accesses, %0d cycles, hits=%0d misses=%0d, data_err=%0d, model_mismatch=%0d",
                 trace_f, n, total_cycles, stat_hits, stat_misses, data_err, hit_err);
        $finish;
    end
endmodule
