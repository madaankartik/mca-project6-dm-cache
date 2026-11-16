# ============================================================================
# Project 6 -- Direct-Mapped Cache Controller : build / verify / analyse
#   make directed   : directed self-checking testbench (+ sim/directed.vcd)
#   make traces     : generate memory-access traces
#   make rtl        : run all traces through the RTL, check against the model
#   make analysis   : tables + figures (results/, docs/img/)
#   make waves      : waveform PNGs from the directed VCD
#   make synth      : Yosys synthesis (Xilinx 7-series + ECP5)
#   make pnr        : nextpnr-ecp5 place & route -> Fmax
#   make report     : compile the IEEE report PDF
#   make all        : everything except pnr/report
#   make gtkwave    : open the directed-test waveform in GTKWave
# ============================================================================
RTL      := $(wildcard rtl/*.v)
SYN_RTL  := rtl/addr_decoder.v rtl/tag_ram.v rtl/valid_ram.v rtl/data_ram.v \
            rtl/tag_comparator.v rtl/cache_fsm.v rtl/cache_top.v
PY       := python3

.PHONY: all directed traces rtl analysis waves synth pnr report gtkwave clean

all: directed traces rtl analysis waves synth

sim:
	mkdir -p sim results

directed: sim
	iverilog -g2005 -Wall -o sim/directed.vvp tb/tb_directed.v $(RTL)
	vvp -n sim/directed.vvp | tee sim/directed.log
	@grep -q "ALL TESTS PASSED" sim/directed.log

traces:
	$(PY) traces/gen_traces.py

rtl: sim traces
	$(PY) model/run_rtl.py

analysis:
	$(PY) model/analysis.py

waves: directed
	$(PY) model/plot_waveform.py

synth:
	yosys -q -s synth/synth_xilinx.ys > synth/yosys_xilinx.log 2>&1
	yosys -q -s synth/synth_ecp5.ys   > synth/yosys_ecp5.log 2>&1
	@echo "utilisation -> synth/utilization_*.txt"

pnr: synth
	nextpnr-ecp5 --85k --json synth/cache_top_ecp5.json --out-of-context \
	    --freq 100 --timing-allow-fail --seed 1 > synth/nextpnr_ecp5.log 2>&1
	@grep "Max frequency" synth/nextpnr_ecp5.log | tail -1

report:
	cd report && pdflatex -interaction=nonstopmode main.tex >/dev/null && \
	    pdflatex -interaction=nonstopmode main.tex >/dev/null
	@echo "report/main.pdf"

gtkwave: directed
	gtkwave sim/directed.vcd docs/directed.gtkw &

clean:
	rm -rf sim/*.vvp sim/*.vcd sim/*.expect sim/*.txt synth/*.json report/*.aux report/*.log
