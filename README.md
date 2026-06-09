# pico_so_bench

Benchmark suite for [Tarantool](https://www.tarantool.io/) evaluating `sort_order` performance.

This suite compares performance between master and patched builds of Tarantool, focusing on ascending, descending, and mixed order indexes in Memtx and Vinyl engines.

## Benchmarks

| Benchmark | Pattern | Purpose |
|-----------|---------|---------|
| **Memtx** | Point / Range / Insert / Delete | Baseline memory engine performance and regressions |
| **Vinyl** | Point / Range / Insert / Delete | Disk-based engine performance and write-amp evaluation |
| **Sort Order** | ASC / DESC / MIXED parts | Evaluate overhead of custom sort orders in index parts |

## Quick start

```bash
make all
```

Results are stored in `./results/` and visualized in `./plots/`.

## Performance Report

Comprehensive analysis of the benchmark results, including statistical significance and engine comparisons, can be found in:

👉 **[REPORT.md](REPORT.md)**

## Usage

```bash
./run_repeated_scaling.sh <tarantool_binary> <prefix> <iterations> <scale1> [scale2]...
```

- **tarantool_binary** -- path to the Tarantool executable
- **prefix** -- name for the result directory
- **iterations** -- number of times to repeat each test (for confidence intervals)
- **scale** -- data size multiplier (default: 1)

| Scale | Memtx Rows | Vinyl Rows | Sort Order Rows |
|-------|------------|------------|-----------------|
| 1     | 100K       | 50K        | 60K             |
| 10    | 1M         | 500K       | 600K            |
| 50    | 5M         | 2.5M       | 3M              |

## Reproducing Results

Use the provided `Makefile` to run the full comparative suite:

```bash
# Set up Python environment
uv sync

# Run all benchmarks and generate plots
make all
```

## Metrics

The benchmarks report:

- **Throughput** (TPS - Transactions Per Second)
- **Execution Time** (seconds)
- **Scaling Ratios** (Ratio of TPS between versions)

## Requirements

- Tarantool (2.11+ recommended)
- Python 3.10+ (with pandas, matplotlib, seaborn)
- `uv` for dependency management

## License

BSD-2-Clause
