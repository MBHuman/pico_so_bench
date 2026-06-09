# Tarantool Benchmark Makefile

TT_MASTER = $(HOME)/.local/bin/tarantool-master
TT_SO     = $(HOME)/.local/bin/tarantool-so

# Branch names used as prefixes in result CSVs and passed to plot scripts
BRANCH_BASE   = master
BRANCH_TARGET = so

ITERATIONS = 2
SCALES     = 20

# Set to 1 if the target branch does NOT have sort_order support
# (bench_sort_order will be excluded from comparison plots)
NO_SORT_ORDER = 0

FLAMEGRAPH_SCALE  = 20
FLAMEGRAPH_PROFILE = ${TT_MASTER}
FLAMEGRAPH_PROFILE_NAME = tarantool-master
FLAMEGRAPH_DIR    = $(HOME)/Documents/other/FlameGraph
PERF_FOLDER       = perf
PERF              = sudo perf

.PHONY: all bench-master bench-so plot clean \
        flamegraph flamegraph-sort-order flamegraph-memtx flamegraph-vinyl

all: bench-master bench-so plot

_SORT_ORDER_FLAG = $(if $(filter 1,$(NO_SORT_ORDER)),--no-sort-order,)

bench-master:
	./run_repeated_scaling.sh $(TT_MASTER) $(BRANCH_BASE) $(ITERATIONS) $(SCALES)

bench-so:
	./run_repeated_scaling.sh $(TT_SO) $(BRANCH_TARGET) $(ITERATIONS) $(SCALES)

plot:
	uv run ./scripts/plot_statistical.py --base $(BRANCH_BASE) --target $(BRANCH_TARGET) $(_SORT_ORDER_FLAG)
	uv run ./scripts/compare_builds.py   --base $(BRANCH_BASE) --target $(BRANCH_TARGET) $(_SORT_ORDER_FLAG)

flamegraph: flamegraph-sort-order flamegraph-memtx flamegraph-vinyl

flamegraph-sort-order:
	mkdir -p $(PERF_FOLDER)
	sudo sysctl -q kernel.perf_event_paranoid=1
	$(PERF) record -F 99 -g --call-graph dwarf -o $(PERF_FOLDER)/perf-sort-order-${FLAMEGRAPH_PROFILE_NAME}.data \
	    -- $(FLAMEGRAPH_PROFILE) bench_sort_order.lua $(FLAMEGRAPH_SCALE)
	sudo chown $$USER $(PERF_FOLDER)/perf-sort-order-${FLAMEGRAPH_PROFILE_NAME}.data
	perf script -i $(PERF_FOLDER)/perf-sort-order-${FLAMEGRAPH_PROFILE_NAME}.data \
	    | $(FLAMEGRAPH_DIR)/stackcollapse-perf.pl \
	    | $(FLAMEGRAPH_DIR)/flamegraph.pl --width 1800 \
	      --title "tarantool-so bench_sort_order scale=$(FLAMEGRAPH_SCALE)" \
	    > $(PERF_FOLDER)/flamegraph-sort-order-${FLAMEGRAPH_PROFILE_NAME}.svg
	@echo "Generated $(PERF_FOLDER)/flamegraph-sort-order-${FLAMEGRAPH_PROFILE_NAME}.svg"

flamegraph-memtx:
	mkdir -p $(PERF_FOLDER)
	sudo sysctl -q kernel.perf_event_paranoid=1
	$(PERF) record -F 99 -g --call-graph dwarf -o $(PERF_FOLDER)/perf-memtx-${FLAMEGRAPH_PROFILE_NAME}.data \
	    -- $(FLAMEGRAPH_PROFILE) bench_memtx.lua $(FLAMEGRAPH_SCALE)
	sudo chown $$USER $(PERF_FOLDER)/perf-memtx-${FLAMEGRAPH_PROFILE_NAME}.data
	perf script -i $(PERF_FOLDER)/perf-memtx-${FLAMEGRAPH_PROFILE_NAME}.data \
	    | $(FLAMEGRAPH_DIR)/stackcollapse-perf.pl \
	    | $(FLAMEGRAPH_DIR)/flamegraph.pl --width 1800 \
	      --title "tarantool-so bench_memtx scale=$(FLAMEGRAPH_SCALE)" \
	    > $(PERF_FOLDER)/flamegraph-memtx-${FLAMEGRAPH_PROFILE_NAME}.svg
	@echo "Generated $(PERF_FOLDER)/flamegraph-memtx-${FLAMEGRAPH_PROFILE_NAME}.svg"

flamegraph-vinyl:
	mkdir -p $(PERF_FOLDER)
	sudo sysctl -q kernel.perf_event_paranoid=1
	$(PERF) record -F 99 -g --call-graph dwarf -o $(PERF_FOLDER)/perf-vinyl-${FLAMEGRAPH_PROFILE_NAME}.data \
	    -- $(FLAMEGRAPH_PROFILE) bench_vinyl.lua $(FLAMEGRAPH_SCALE)
	sudo chown $$USER $(PERF_FOLDER)/perf-vinyl-${FLAMEGRAPH_PROFILE_NAME}.data
	perf script -i $(PERF_FOLDER)/perf-vinyl-${FLAMEGRAPH_PROFILE_NAME}.data \
	    | $(FLAMEGRAPH_DIR)/stackcollapse-perf.pl \
	    | $(FLAMEGRAPH_DIR)/flamegraph.pl --width 1800 \
	      --title "tarantool-so bench_vinyl scale=$(FLAMEGRAPH_SCALE)" \
	    > $(PERF_FOLDER)/flamegraph-vinyl-${FLAMEGRAPH_PROFILE_NAME}.svg
	@echo "Generated $(PERF_FOLDER)/flamegraph-vinyl-${FLAMEGRAPH_PROFILE_NAME}.svg"

clean:
	rm -rf results/
	rm -rf plots/
	rm -rf matrices/
	rm -rf $(PERF_FOLDER)/
