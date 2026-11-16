#!/usr/bin/env python3
"""
analysis.py -- performance analysis of the direct-mapped cache.

Inputs : results/rtl_results.csv (from run_rtl.py), traces/*.trace
Outputs: results/summary.md, results/sweep_*.csv, report/results_table.tex,
         docs/img/*.png  (figures used in the IEEE report)

Metrics
  hit rate / miss rate          (all accesses and loads only)
  AMAT_load = t_hit + m_load * miss_penalty,  t_hit = 2, penalty = L + 2
  speed-up  = cycles(no cache) / cycles(cache)
  memory traffic = # main-memory transactions
"""
import csv
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "model"))
from cache_model import load_trace, simulate, amat  # noqa: E402

RES = os.path.join(ROOT, "results")
IMG = os.path.join(ROOT, "docs", "img")
os.makedirs(IMG, exist_ok=True)
LAT = 10
T_HIT = 2
PENALTY = LAT + 2          # load-miss cycles (L+4) minus hit time (2)

TRACES = ["sequential", "loop", "random", "conflict",
          "vecadd_aligned", "vecadd_padded", "mixed"]
# categorical palette (fixed order) + text/grid tokens
C = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300"]
INK, INK2, GRID = "#1f1f1e", "#5f5e5a", "#e6e5e0"

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 9, "axes.edgecolor": INK2,
    "axes.labelcolor": INK, "xtick.color": INK2, "ytick.color": INK2,
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.axisbelow": True, "legend.frameon": False, "savefig.dpi": 200,
})


def read_rtl():
    with open(os.path.join(RES, "rtl_results.csv")) as f:
        return [r for r in csv.DictReader(f)]


def main_table(rows):
    main = [r for r in rows if r["cache_bytes"] == "1024" and r["block_bytes"] == "16"]
    out = []
    for r in main:
        n = int(r["rtl_accesses"]); loads = int(r["rtl_loads"])
        hits = int(r["rtl_hits"]); lm = int(r["rtl_load_misses"])
        cyc = int(r["rtl_total_cycles"]); nc = int(r["nocache_cycles"])
        m_load = lm / loads if loads else 0.0
        out.append(dict(
            trace=r["trace"], accesses=n, stores=int(r["rtl_stores"]),
            hit_rate=hits / n, miss_rate=1 - hits / n,
            load_miss_rate=m_load,
            amat_formula=amat(T_HIT, m_load, PENALTY),
            amat_measured=int(r["rtl_load_cycles"]) / loads if loads else 0.0,
            avg_cycles=cyc / n, cycles=cyc, nocache_cycles=nc, speedup=nc / cyc,
            mem_tx=int(r["rtl_mem_reads"]) + int(r["rtl_mem_writes"]),
            nocache_mem_tx=n, model=r["model_match"],
        ))
    return out


def write_summary(tab, rows):
    lines = ["# Results -- 1 KB direct-mapped cache, 16 B blocks, memory latency 10 cycles", "",
             "| Trace | Accesses | Hit rate | Load miss rate | AMAT (formula) | AMAT (RTL) | Cycles (cache) | Cycles (no cache) | Speed-up | Mem. transactions (cache / none) |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for t in tab:
        lines.append(f"| {t['trace']} | {t['accesses']} | {t['hit_rate']*100:.1f}% | {t['load_miss_rate']*100:.1f}% | "
                     f"{t['amat_formula']:.2f} | {t['amat_measured']:.2f} | {t['cycles']} | {t['nocache_cycles']} | "
                     f"{t['speedup']:.2f}x | {t['mem_tx']} / {t['nocache_mem_tx']} |")
    ok = sum(r["model_match"] == "PASS" for r in rows)
    lines += ["", f"RTL vs Python reference model: **{ok}/{len(rows)} runs match** exactly "
              "(load data, per-access hit/miss decision and total cycle count), across 4 cache geometries.", ""]
    with open(os.path.join(RES, "summary.md"), "w") as f:
        f.write("\n".join(lines))
    print("\n".join(lines))

    # LaTeX table for the IEEE report
    nice = {"vecadd_aligned": "vecadd (aligned)", "vecadd_padded": "vecadd (padded)"}
    tex = [r"\begin{table}[!t]", r"\centering",
           r"\caption{RTL results: 1\,KB direct-mapped cache, 16\,B blocks, $L=10$ cycles}",
           r"\label{tab:results}", r"\setlength{\tabcolsep}{3pt}",
           r"\begin{tabular}{lrrrrrr}", r"\hline",
           r"Trace & Acc. & Hit & AMAT & Cycles & Cycles & Speed- \\",
           r" & & rate & (load) & cache & no cache & up \\", r"\hline"]
    for t in tab:
        tex.append(f"{nice.get(t['trace'], t['trace'])} & {t['accesses']} & {t['hit_rate']*100:.1f}\\% & "
                   f"{t['amat_measured']:.2f} & {t['cycles']} & {t['nocache_cycles']} & {t['speedup']:.2f}$\\times$ \\\\")
    tex += [r"\hline", r"\end{tabular}", r"\end{table}"]
    with open(os.path.join(ROOT, "report", "results_table.tex"), "w") as f:
        f.write("\n".join(tex) + "\n")


def sweeps():
    traces = {t: load_trace(os.path.join(ROOT, "traces", f"{t}.trace")) for t in TRACES}
    sizes = [256, 512, 1024, 2048, 4096, 8192]
    blocks = [4, 8, 16, 32, 64]
    lats = [5, 10, 20, 50, 100]
    s_rows, b_rows, l_rows = [], [], []
    for t, ops in traces.items():
        for cb in sizes:
            s_rows.append(dict(trace=t, cache_bytes=cb, hit_rate=simulate(ops, cb, 16, LAT)[1]["hit_rate"]))
        for bb in blocks:
            st = simulate(ops, 1024, bb, LAT)[1]
            b_rows.append(dict(trace=t, block_bytes=bb, hit_rate=st["hit_rate"]))
        for L in lats:
            st = simulate(ops, 1024, 16, L)[1]
            l_rows.append(dict(trace=t, latency=L, speedup=st["nocache_cycles"] / st["cycles"],
                               amat=amat(2, 1 - st["load_hit_rate"], L + 2) if st["loads"] else 0))
    for name, rows in (("size", s_rows), ("block", b_rows), ("latency", l_rows)):
        with open(os.path.join(RES, f"sweep_{name}.csv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader(); w.writerows(rows)
    return s_rows, b_rows, l_rows


SHOW = ["sequential", "loop", "mixed", "random"]   # 4 representative series


def line_plot(rows, xkey, ykey, xlabel, ylabel, title, fname, logx=True, pct=True, mark_x=None, direct=True):
    fig, ax = plt.subplots(figsize=(3.5, 2.8))
    for i, t in enumerate(SHOW):
        pts = [r for r in rows if r["trace"] == t]
        xs = [r[xkey] for r in pts]; ys = [r[ykey] * (100 if pct else 1) for r in pts]
        ax.plot(xs, ys, color=C[i], lw=2, marker="o", ms=4, label=t,
                markeredgecolor="white", markeredgewidth=1)
        if direct: ax.annotate(t, (xs[-1], ys[-1]), xytext=(4, 0), textcoords="offset points",
                    va="center", fontsize=7.5, color=INK2)
    if logx:
        ax.set_xscale("log", base=2)
        ax.set_xticks(xs); ax.set_xticklabels([str(x) for x in xs])
        ax.minorticks_off()
    if mark_x:
        ax.axvline(mark_x, color=INK2, lw=0.8, ls="--")
        y0, y1 = ax.get_ylim(); ax.text(mark_x, y0 + 0.42 * (y1 - y0), " design\n point", fontsize=7, color=INK2, va="bottom")
    ax.set_xlabel(xlabel); ax.set_ylabel(ylabel)
    ax.set_title(title, fontsize=9.5, color=INK, loc="left")
    if direct: ax.set_xlim(right=ax.get_xlim()[1] * 1.9 if logx else None)
    ax.legend(fontsize=7, loc="upper center", bbox_to_anchor=(0.5, -0.28), ncol=4,
              handlelength=1.5, columnspacing=1.0)
    fig.tight_layout()
    fig.savefig(os.path.join(IMG, fname)); plt.close(fig)


def speedup_bars(tab):
    fig, ax = plt.subplots(figsize=(3.5, 2.6))
    names = [t["trace"].replace("vecadd_", "vecadd\n") for t in tab]
    x = range(len(tab)); w = 0.38
    ax.bar([i - w / 2 - 0.01 for i in x], [t["nocache_cycles"] / 1000 for t in tab], w,
           color=C[1], label="no cache (baseline)")
    ax.bar([i + w / 2 + 0.01 for i in x], [t["cycles"] / 1000 for t in tab], w,
           color=C[0], label="1 KB direct-mapped")
    for i, t in enumerate(tab):
        ax.text(i + w / 2, t["cycles"] / 1000 + 0.6, f"{t['speedup']:.1f}x", ha="center",
                fontsize=6.5, color=INK)
    ax.set_xticks(list(x)); ax.set_xticklabels(names, fontsize=6.5)
    ax.set_ylabel("total cycles (thousands)")
    ax.set_title("Execution cycles: cache vs. no cache", fontsize=9.5, color=INK, loc="left")
    ax.legend(fontsize=7, loc="upper left"); ax.grid(axis="x", visible=False)
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "speedup_bars.png")); plt.close(fig)


def hitrate_bars(tab):
    fig, ax = plt.subplots(figsize=(3.5, 2.4))
    names = [t["trace"].replace("vecadd_", "vecadd\n") for t in tab]
    vals = [t["hit_rate"] * 100 for t in tab]
    ax.bar(range(len(tab)), vals, 0.6, color=C[0])
    for i, v in enumerate(vals):
        ax.text(i, v + 1.5, f"{v:.1f}%", ha="center", fontsize=6.5, color=INK)
    ax.set_xticks(range(len(tab))); ax.set_xticklabels(names, fontsize=6.5)
    ax.set_ylim(0, 110); ax.set_ylabel("hit rate (%)")
    ax.set_title("Hit rate per trace (1 KB, 16 B blocks)", fontsize=9.5, color=INK, loc="left")
    ax.grid(axis="x", visible=False)
    fig.tight_layout(); fig.savefig(os.path.join(IMG, "hitrate_bars.png")); plt.close(fig)


if __name__ == "__main__":
    rows = read_rtl()
    tab = main_table(rows)
    write_summary(tab, rows)
    s, b, l = sweeps()
    line_plot(s, "cache_bytes", "hit_rate", "cache size (bytes)", "hit rate (%)",
              "Hit rate vs. cache size (16 B blocks)", "sweep_cache_size.png", mark_x=1024)
    line_plot(b, "block_bytes", "hit_rate", "block size (bytes)", "hit rate (%)",
              "Hit rate vs. block size (1 KB cache)", "sweep_block_size.png", mark_x=16)
    line_plot(l, "latency", "speedup", "main-memory latency (cycles)", "speed-up vs. no cache",
              "Speed-up vs. memory latency", "sweep_latency.png", pct=False, mark_x=10, direct=False)
    speedup_bars(tab)
    hitrate_bars(tab)
    print("figures written to docs/img/")
