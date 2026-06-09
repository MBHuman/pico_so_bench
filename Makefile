# Tarantool Benchmark Makefile

TT_MASTER = $(HOME)/.local/bin/tarantool-master
TT_SO     = $(HOME)/.local/bin/tarantool-so

ITERATIONS = 10
SCALES     = 1 5 10 20 30

.PHONY: all bench-master bench-so plot clean

all: bench-master bench-so plot

bench-master:
	./run_repeated_scaling.sh $(TT_MASTER) master $(ITERATIONS) $(SCALES)

bench-so:
	./run_repeated_scaling.sh $(TT_SO) so $(ITERATIONS) $(SCALES)

plot:
	uv run ./scripts/plot_line_charts.py
	uv run ./scripts/generate_matrices.py

clean:
	rm -rf results/
	rm -rf plots/
	rm -rf matrices/
