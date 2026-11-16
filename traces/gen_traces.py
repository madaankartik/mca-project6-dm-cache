#!/usr/bin/env python3
"""
gen_traces.py -- generate representative memory-access traces.

Each line: "<op> <addr_hex> <data_hex>"   op 0 = load, 1 = store
All addresses are word-aligned and below 256 KB (size of the memory model).

Traces
  sequential     : streaming read of an 8 KB array        (spatial locality)
  loop           : 10 passes over a 512 B array           (temporal locality)
  random         : uniform random reads over 64 KB        (little locality)
  conflict       : ping-pong between A and A+1 KB         (pathological, same index)
  vecadd_aligned : C[i]=A[i]+B[i], arrays 16 KB apart     (conflict misses)
  vecadd_padded  : same kernel, arrays offset by 256 B    (conflicts removed)
  mixed          : 70% hot working set, 30% random, 20% stores
"""
import os
import random

OUT = os.path.dirname(os.path.abspath(__file__))
random.seed(42)


def w(name, ops):
    with open(os.path.join(OUT, f"{name}.trace"), "w") as f:
        for op, addr, data in ops:
            f.write(f"{op} {addr:08x} {data:08x}\n")
    print(f"  {name:15s} {len(ops):5d} accesses")


def sequential():
    base = 0x0000_4000
    return [(0, base + 4 * i, 0) for i in range(2048)]


def loop():
    base = 0x0000_1000
    return [(0, base + 4 * i, 0) for _ in range(10) for i in range(128)]


def rand():
    return [(0, random.randrange(0, 0x1_0000) & ~3, 0) for _ in range(2000)]


def conflict():
    a, b = 0x0000_2000, 0x0000_2000 + 1024
    ops = []
    for _ in range(500):
        ops += [(0, a, 0), (0, b, 0)]
    return ops


def vecadd(a, b, c, n=512):
    ops = []
    for i in range(n):
        ops.append((0, a + 4 * i, 0))
        ops.append((0, b + 4 * i, 0))
        ops.append((1, c + 4 * i, (0x1000_0000 + i) & 0xFFFF_FFFF))
    return ops


def mixed():
    hot = 0x0000_8000
    ops = []
    for i in range(3000):
        if random.random() < 0.7:
            addr = hot + (random.randrange(0, 512) & ~3)          # 512 B hot set
        else:
            addr = random.randrange(0, 0x2_0000) & ~3            # 128 KB cold region
        if random.random() < 0.2:
            ops.append((1, addr, random.getrandbits(32)))
        else:
            ops.append((0, addr, 0))
    return ops


TRACES = {
    "sequential": sequential,
    "loop": loop,
    "random": rand,
    "conflict": conflict,
    "vecadd_aligned": lambda: vecadd(0x0001_0000, 0x0001_4000, 0x0001_8000),
    "vecadd_padded": lambda: vecadd(0x0001_0000, 0x0001_4100, 0x0001_8200),
    "mixed": mixed,
}

if __name__ == "__main__":
    print("Generating traces:")
    for name, fn in TRACES.items():
        w(name, fn())
