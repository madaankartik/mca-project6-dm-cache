# Synthesis results: `cache_top` (1 KB, 16 B blocks, 64 lines)

`main_memory.v` and `nocache_top.v` are simulation models and are **not** synthesized.

## Flow

| Step | Tool | Script |
|---|---|---|
| Logic synthesis, Xilinx 7-series (Artix-7) | Yosys 0.33 `synth_xilinx` | `synth/synth_xilinx.ys` |
| Logic synthesis, Lattice ECP5 | Yosys 0.33 `synth_ecp5` | `synth/synth_ecp5.ys` |
| Place & route + static timing (Fmax) | nextpnr-ecp5 (LFE5U-85F, out-of-context) | `make pnr` |

Run everything with `make synth`.

## Resource utilisation: Xilinx 7-series (Yosys `synth_xilinx`)

| Resource | Count | Used for |
|---|---|---|
| LUTs (LUT2–LUT6 + INV) | 321 | decode, compare, FSM, word mux, counters |
| LUTRAM (RAM64M) | 136 (= 544 LUTs as memory) | data array 64×128 b, tag array 64×22 b |
| Flip-flops (FDRE) | 233 | valid bits (64), request latch (65), 3×32-bit counters, FSM |
| CARRY4 | 32 | 32-bit performance counters |
| MUXF7 / MUXF8 | 145 / 69 | wide read multiplexers |
| Block RAM | 0 | asynchronous-read arrays map to distributed RAM |

## Resource utilisation and timing: Lattice ECP5-85F (Yosys + nextpnr)

| Resource | Used | Available | % |
|---|---|---|---|
| TRELLIS_COMB (LUT4) | 4387 | 83 640 | 5 % |
| TRELLIS_FF | 256 | 83 640 | <1 % |
| TRELLIS_RAMW (distributed RAM) | 512 | 10 455 | 4 % |
| DP16KD (block RAM) | 1 | 208 | <1 % |

**Maximum frequency (post place-and-route): 61.4 MHz** (critical-path period ≈ 16.3 ns)

**Critical path:** tag-array read → 22-bit tag compare → FSM next-state / write enables → array write. This is the single-cycle COMPARE lookup.

## Notes and possible improvements

* At 61 MHz, the 2-cycle hit time is 32.6 ns.
* The arrays use asynchronous read, so they map to distributed (LUT) RAM. Registering the read address (synchronous read) would let the data array map to block RAM. That reduces LUT usage, at the cost of one extra cycle of hit latency.
* For Vivado / Artix-7 timing numbers, add `rtl/*.v` (except `main_memory.v` and `nocache_top.v`) to a Vivado project, set `cache_top` as top, add a 100 MHz clock constraint, and run Synthesis followed by Implementation. Read the WNS from the timing summary: Fmax = 1 / (T − WNS).
