# Prototype video script (target 4:30, hard limit 5:00)

Speaker order is a suggestion; swap parts so each person presents what they worked on.

**Setup before recording:**

- Have a terminal open in the repo.
- Run `make directed` once beforehand.
- Open GTKWave with `make gtkwave`.
- Open `docs/img/block_diagram.png`, `docs/img/fsm.png` and `results/summary.md` in tabs.
- Record with OBS or a Zoom screen share. Each member records their own part, either live or as a voice-over.

| Time | Speaker | On screen | What to say |
|---|---|---|---|
| 0:00–0:35 | All five | Title slide or webcam | Each member gives their name: "Hi, I'm ___." Then one person: "We are Team Short Circuit, Section B. Our project is Project 6, a direct-mapped cache controller in Verilog. A cache keeps recently used memory blocks close to the CPU so most loads take 2 cycles instead of 14." |
| 0:35–1:20 | Chirag Lalwani | `block_diagram.png` | Explain the 1 KB / 16-byte-block / 64-line organisation. Explain the address split: tag 22 bits, index 6, offset 4. Walk through the modules: request latch, decoder, tag RAM, valid bits, data RAM, comparator, FSM, counters. |
| 1:20–2:00 | Kartik Madaan | `fsm.png` | Walk through the four states, IDLE → COMPARE → ALLOCATE or WRITE_MEM. Explain the write-through, no-write-allocate policy and why a refill goes back to COMPARE. |
| 2:00–3:10 | Arhan Alam | Terminal, then GTKWave | Run `make directed` live and show "16 passed, ALL TESTS PASSED". In GTKWave, show the cold miss (`fsm_state` in ALLOCATE until `mem_ready`), then the 2-cycle hits on 0x44 and 0x4C. Then show the conflict: 0x440 evicts 0x040. |
| 3:10–4:05 | Siddhanth Raikar | Terminal, then `speedup_bars.png` and the sweep plots | Run `make rtl` and show "28/28 RTL runs match the reference model". Explain the results: loop 97.5 % hit rate and 5.2× speed-up; sequential 75 % because of 16-byte blocks; aligned vecadd 0 % because of conflict misses, fixed by padding. |
| 4:05–4:35 | Arjun Singh | `synth/SYNTHESIS.md`, then the GitHub repo | Give the synthesis numbers: 61.4 MHz Fmax, 256 FFs, ~5 % of an ECP5. Show the repo structure and report. Next steps: 2-way set-associative with LRU, write-back, FPGA deployment. |

**Upload:** YouTube (unlisted) or Google Drive with "anyone with the link" access. Paste the link into `README.md` and into the report's Artefacts section.
