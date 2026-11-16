#!/usr/bin/env python3
"""
cache_model.py -- cycle-approximate Python reference model of the RTL cache.

Mirrors the Verilog exactly:
  * direct-mapped, parameterised size / block size, 32-bit addresses
  * read-allocate, write-through, no-write-allocate
  * timing (cycles per access, MEM_LATENCY = L):
        load  hit  : 2           (IDLE + COMPARE)
        load  miss : L + 4       (IDLE + COMPARE + ALLOCATE(L+1) + COMPARE)
        store      : L + 3       (IDLE + COMPARE + WRITE_MEM(L+1))
        no cache   : L + 2       (IDLE + MEM(L+1))   -- baseline

Used to (1) produce the expected hit/miss sequence that the RTL testbench
checks against and (2) sweep cache/block sizes much faster than RTL sim.
"""
import math
import sys


def load_trace(path):
    ops = []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) == 3:
                ops.append((int(p[0]), int(p[1], 16), int(p[2], 16)))
    return ops


class DirectMappedCache:
    def __init__(self, cache_bytes=1024, block_bytes=16, latency=10):
        self.cache_bytes = cache_bytes
        self.block_bytes = block_bytes
        self.lines = cache_bytes // block_bytes
        self.offset_bits = int(math.log2(block_bytes))
        self.index_bits = int(math.log2(self.lines))
        self.tag_bits = 32 - self.offset_bits - self.index_bits
        self.L = latency
        self.valid = [False] * self.lines
        self.tag = [0] * self.lines

    def split(self, addr):
        index = (addr >> self.offset_bits) & (self.lines - 1)
        tag = addr >> (self.offset_bits + self.index_bits)
        return tag, index

    def access(self, op, addr):
        """returns (hit, cycles)"""
        tag, index = self.split(addr)
        hit = self.valid[index] and self.tag[index] == tag
        if op == 0:                         # load
            if hit:
                return True, 2
            self.valid[index] = True        # read-allocate
            self.tag[index] = tag
            return False, self.L + 4
        # store: write-through, no-write-allocate
        return hit, self.L + 3


def simulate(ops, cache_bytes=1024, block_bytes=16, latency=10):
    c = DirectMappedCache(cache_bytes, block_bytes, latency)
    hits_seq = []
    s = dict(accesses=0, loads=0, stores=0, hits=0, misses=0,
             load_hits=0, load_misses=0, cycles=0, mem_reads=0, mem_writes=0)
    for op, addr, _ in ops:
        hit, cyc = c.access(op, addr)
        hits_seq.append(1 if hit else 0)
        s["accesses"] += 1
        s["cycles"] += cyc
        s["hits" if hit else "misses"] += 1
        if op == 0:
            s["loads"] += 1
            s["load_hits" if hit else "load_misses"] += 1
            if not hit:
                s["mem_reads"] += 1
        else:
            s["stores"] += 1
            s["mem_writes"] += 1
    s["nocache_cycles"] = len(ops) * (latency + 2)
    s["hit_rate"] = s["hits"] / s["accesses"] if s["accesses"] else 0.0
    s["load_hit_rate"] = s["load_hits"] / s["loads"] if s["loads"] else 0.0
    return hits_seq, s


def amat(hit_time, miss_rate, miss_penalty):
    return hit_time + miss_rate * miss_penalty


if __name__ == "__main__":
    # usage: cache_model.py <trace> <expect_out> [cache_bytes block_bytes latency]
    trace, out = sys.argv[1], sys.argv[2]
    cb = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    bb = int(sys.argv[4]) if len(sys.argv) > 4 else 16
    lat = int(sys.argv[5]) if len(sys.argv) > 5 else 10
    seq, stats = simulate(load_trace(trace), cb, bb, lat)
    with open(out, "w") as f:
        f.write("\n".join(str(x) for x in seq) + "\n")
    print(f"{trace}: hit_rate={stats['hit_rate']:.4f} cycles={stats['cycles']}")
