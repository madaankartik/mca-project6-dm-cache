#!/usr/bin/env python3
"""
run_rtl.py -- run every trace through the Verilog RTL (Icarus Verilog) and
collect hit/miss/cycle statistics.

For each trace:
  1. Python reference model produces the expected hit/miss sequence
  2. tb_trace.v runs the RTL with the cache   (checks data + hit/miss)
  3. tb_trace.v runs the RTL without a cache  (baseline cycle count)

Also cross-validates the RTL against the model on extra cache geometries.
Output: results/rtl_results.csv
"""
import csv
import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "model"))
from cache_model import load_trace, simulate  # noqa: E402

RTL = sorted(glob.glob(os.path.join(ROOT, "rtl", "*.v")))
TB = os.path.join(ROOT, "tb", "tb_trace.v")
SIM = os.path.join(ROOT, "sim")
RES = os.path.join(ROOT, "results")
os.makedirs(SIM, exist_ok=True)
os.makedirs(RES, exist_ok=True)

LAT = 10
TRACES = ["sequential", "loop", "random", "conflict",
          "vecadd_aligned", "vecadd_padded", "mixed"]


def build(use_cache, cb, bb, lat=LAT):
    exe = os.path.join(SIM, f"tb_trace_c{use_cache}_{cb}_{bb}_{lat}.vvp")
    cmd = ["iverilog", "-g2005", "-o", exe,
           f"-Ptb_trace.USE_CACHE={use_cache}", f"-Ptb_trace.CACHE_BYTES={cb}",
           f"-Ptb_trace.BLOCK_BYTES={bb}", f"-Ptb_trace.MEM_LATENCY={lat}", TB] + RTL
    subprocess.run(cmd, check=True, cwd=ROOT)
    return exe


def run(exe, trace, expect=None, vcd=None):
    out = os.path.join(SIM, "tmp_result.txt")
    args = ["vvp", "-n", exe, f"+TRACE={trace}", f"+OUT={out}"]
    if expect:
        args.append(f"+EXPECT={expect}")
    if vcd:
        args.append(f"+VCD={vcd}")
    subprocess.run(args, check=True, cwd=ROOT, stdout=subprocess.DEVNULL)
    with open(out) as f:
        return {k: int(v) for k, v in (kv.split("=") for kv in f.read().split())}


def main():
    rows = []
    configs = [(1024, 16)]                         # main design point
    xval = [(512, 16), (2048, 32), (1024, 4)]      # cross-validation geometries

    for cb, bb in configs + xval:
        exe_c = build(1, cb, bb)
        exe_n = build(0, cb, bb) if (cb, bb) in configs else None
        for t in TRACES:
            tpath = os.path.join(ROOT, "traces", f"{t}.trace")
            seq, ms = simulate(load_trace(tpath), cb, bb, LAT)
            epath = os.path.join(SIM, f"{t}_{cb}_{bb}.expect")
            with open(epath, "w") as f:
                f.write("\n".join(map(str, seq)) + "\n")
            vcd = os.path.join(SIM, f"trace_{t}.vcd") if (cb, bb) == (1024, 16) and t == "loop" else None
            rc = run(exe_c, tpath, epath, vcd)
            row = dict(trace=t, cache_bytes=cb, block_bytes=bb, **{f"rtl_{k}": v for k, v in rc.items()
                                                                   if k not in ("use_cache", "cache_bytes", "block_bytes")})
            row["model_hits"] = ms["hits"]
            row["model_cycles"] = ms["cycles"]
            if exe_n:
                rn = run(exe_n, tpath)
                row["nocache_cycles"] = rn["total_cycles"]
                row["nocache_data_errors"] = rn["data_errors"]
                row["nocache_mem_reads"] = rn["mem_reads"]
            ok = (rc["data_errors"] == 0 and rc["hitmiss_errors"] == 0
                  and rc["hits"] == ms["hits"] and rc["total_cycles"] == ms["cycles"])
            row["model_match"] = "PASS" if ok else "FAIL"
            rows.append(row)
            print(f"[{cb:5d}B/{bb:2d}B] {t:15s} hits={rc['hits']:5d}/{rc['accesses']:5d} "
                  f"cycles={rc['total_cycles']:6d} model={ms['cycles']:6d} "
                  f"data_err={rc['data_errors']} mismatch={rc['hitmiss_errors']}  {row['model_match']}")

    keys = sorted({k for r in rows for k in r}, key=lambda k: (k != "trace", k))
    with open(os.path.join(RES, "rtl_results.csv"), "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=keys)
        wr.writeheader()
        wr.writerows(rows)
    fails = [r for r in rows if r["model_match"] != "PASS"]
    print(f"\n{len(rows) - len(fails)}/{len(rows)} RTL runs match the reference model "
          f"(data + hit/miss + cycle count).")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
