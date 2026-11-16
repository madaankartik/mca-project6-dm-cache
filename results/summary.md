# Results -- 1 KB direct-mapped cache, 16 B blocks, memory latency 10 cycles

| Trace | Accesses | Hit rate | Load miss rate | AMAT (formula) | AMAT (RTL) | Cycles (cache) | Cycles (no cache) | Speed-up | Mem. transactions (cache / none) |
|---|---|---|---|---|---|---|---|---|---|
| sequential | 2048 | 75.0% | 25.0% | 5.00 | 5.00 | 10240 | 24576 | 2.40x | 512 / 2048 |
| loop | 1280 | 97.5% | 2.5% | 2.30 | 2.30 | 2944 | 15360 | 5.22x | 32 / 1280 |
| random | 2000 | 1.1% | 98.9% | 13.87 | 13.87 | 27736 | 24000 | 0.87x | 1978 / 2000 |
| conflict | 1000 | 0.0% | 100.0% | 14.00 | 14.00 | 14000 | 12000 | 0.86x | 1000 / 1000 |
| vecadd_aligned | 1536 | 0.0% | 100.0% | 14.00 | 14.00 | 20992 | 18432 | 0.88x | 1536 / 1536 |
| vecadd_padded | 1536 | 50.0% | 25.0% | 5.00 | 5.00 | 11776 | 18432 | 1.57x | 768 / 1536 |
| mixed | 3000 | 57.8% | 41.9% | 7.03 | 7.03 | 25042 | 36000 | 1.44x | 1642 / 3000 |

RTL vs Python reference model: **28/28 runs match** exactly (load data, per-access hit/miss decision and total cycle count), across 4 cache geometries.
