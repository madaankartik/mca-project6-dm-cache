#!/usr/bin/env python3
"""
plot_waveform.py -- render GTKWave-style timing diagrams from the directed-test
VCD into PNGs for the report (the same signals are pre-loaded in
docs/directed.gtkw for live viewing in GTKWave).

usage: python3 model/plot_waveform.py   (after `make directed`)
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from vcdvcd import VCDVCD  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = "tb_directed.dut.g_cache.u_cache."
STATE = {0: "IDLE", 1: "COMPARE", 2: "ALLOCATE", 3: "WRITE_MEM"}

SIGNALS = [
    ("clk", P + "clk", "bit"),
    ("cpu_req", P + "cpu_req", "bit"),
    ("cpu_we", P + "cpu_we", "bit"),
    ("cpu_addr", P + "req_addr[31:0]", "hex"),
    ("fsm_state", P + "fsm_state[1:0]", "state"),
    ("tag", P + "tag[21:0]", "hex"),
    ("index", P + "index[5:0]", "dec"),
    ("valid", P + "valid_bit", "bit"),
    ("hit", P + "hit", "bit"),
    ("mem_req", P + "mem_req", "bit"),
    ("mem_we", P + "mem_we", "bit"),
    ("mem_ready", P + "mem_ready", "bit"),
    ("cpu_ready", P + "cpu_ready", "bit"),
    ("cpu_hit", P + "cpu_hit", "bit"),
    ("cpu_rdata", P + "cpu_rdata[31:0]", "hex"),
]
BLUE, INK, INK2, GRID = "#2a78d6", "#1f1f1e", "#5f5e5a", "#ecebe6"


def changes(sig, t0, t1):
    tv = [(t / 1000.0, v) for t, v in sig.tv]      # VCD is in ps -> ns
    out, last = [], None
    for t, v in tv:
        if t <= t0:
            last = v
        elif t < t1:
            out.append((t, v))
    return [(t0, last)] + out


def val(v, kind):
    if v is None or "x" in v or "z" in v:
        return None
    n = int(v, 2)
    if kind == "hex":
        return f"{n:08x}" if n > 0xFFFF else f"{n:x}"
    if kind == "state":
        return STATE.get(n, str(n))
    return str(n)


def plot(vcd, t0, t1, title, fname, annotations=()):
    fig, ax = plt.subplots(figsize=(11, 0.42 * len(SIGNALS) + 1.0))
    for row, (name, path, kind) in enumerate(SIGNALS):
        y = len(SIGNALS) - 1 - row
        ch = changes(vcd[path], t0, t1) + [(t1, None)]
        ax.text(t0 - (t1 - t0) * 0.01, y + 0.35, name, ha="right", va="center", fontsize=8.5,
                color=INK, family="monospace")
        for (ta, va), (tb, vb) in zip(ch[:-1], ch[1:]):
            if kind == "bit":
                lvl = 0.7 if va == "1" else 0.0
                ax.plot([ta, tb], [y + lvl] * 2, color=BLUE, lw=1.4)
                if vb is not None and vb != va:
                    ax.plot([tb, tb], [y, y + 0.7], color=BLUE, lw=1.4)
            else:
                ax.fill_between([ta + 0.6, tb - 0.6], y + 0.05, y + 0.65, color="#e3eefb",
                                edgecolor=BLUE, lw=0.9)
                s = val(va, kind)
                if s is not None and (tb - ta) > (t1 - t0) * 0.045:
                    ax.text((ta + tb) / 2, y + 0.35, s, ha="center", va="center",
                            fontsize=7, color=INK, family="monospace")
    for j, (t, label) in enumerate(annotations):
        ax.axvline(t, color="#eb6834", lw=0.9, ls="--")
        ax.text(t, len(SIGNALS) + 0.05 + 0.45 * (j % 2), " " + label, fontsize=8, color="#eb6834", ha="left", va="bottom")
    for t in range(int(t0), int(t1), 10):
        ax.axvline(t, color=GRID, lw=0.5, zorder=0)
    ax.set_xlim(t0 - (t1 - t0) * 0.09, t1)
    ax.set_ylim(-0.3, len(SIGNALS) + 1.0)
    ax.set_yticks([])
    ax.set_xlabel("time (ns)  --  10 ns clock period", color=INK2)
    for s in ("left", "right", "top"):
        ax.spines[s].set_visible(False)
    ax.set_title(title, loc="left", fontsize=10.5, color=INK)
    fig.tight_layout()
    fig.savefig(os.path.join(ROOT, "docs", "img", fname), dpi=170)
    plt.close(fig)


def first_time(sig, value_bits, after=0):
    for t, v in sig.tv:
        if t >= after and v == value_bits:
            return t
    return None


if __name__ == "__main__":
    v = VCDVCD(os.path.join(ROOT, "sim", "directed.vcd"))
    req = v[P + "cpu_req"]
    starts = [t / 1000.0 for t, val_ in req.tv if val_ == "1"]
    # T1 cold miss, T2 hit, T3 spatial hits  -> requests 0..3
    plot(v, starts[0] - 10, starts[4] - 5,
         "Read miss -> refill -> read hits (T1 cold miss, T2 temporal hit, T3 spatial hits)",
         "wave_miss_refill_hit.png",
         [(starts[0], "T1 read 0x40: MISS"), (starts[1], "T2 HIT"), (starts[2], "T3 HIT"), (starts[3], "HIT")])
    # T4 conflict miss (requests 4,5)
    plot(v, starts[4] - 10, starts[6] - 5,
         "Conflict miss: 0x440 and 0x040 share index 4 (different tags) and evict each other",
         "wave_conflict.png",
         [(starts[4], "read 0x440: MISS (evicts 0x040)"), (starts[5], "read 0x040: MISS again")])
    # T5 write hit + read, T6 write miss
    plot(v, starts[6] - 10, starts[9] - 5,
         "Write-through: write hit updates cache and memory; write miss bypasses the cache",
         "wave_write_through.png",
         [(starts[6], "write 0x48: HIT"), (starts[7], "read 0x48: HIT"), (starts[8], "write 0x2000: MISS")])
    print("waveform PNGs written to docs/img/")
