#!/usr/bin/env bash
#
# Run all Tarantool benchmarks and save results for CSV/Python analysis.
#
# Results are written to ./results/<prefix>/ inside the workspace.
# Each benchmark gets its own sub-folder with:
#   output.log   — full stdout/stderr from the Tarantool process
#   tarantool.log — box.cfg log file copied out after the run
#   results.csv  — parsed [BENCH] lines, ready for pandas/matplotlib
#
# A combined summary.csv is written to ./results/<prefix>/summary.csv.
#
# Usage:
#   ./run_all.sh <tarantool_binary> <prefix> [scale]
#
# Typical comparison workflow:
#   ./run_all.sh /opt/tarantool-master/bin/tarantool  master  1
#   ./run_all.sh /opt/tarantool-patched/bin/tarantool patched 1
#
# bench_sort_order.lua requires the patched build; it is skipped silently
# on master (the CSV row is simply absent from that prefix's results).
#

set -euo pipefail

TARANTOOL="${1:?Usage: $0 <tarantool_binary> <prefix> [scale]}"
PREFIX="${2:?Usage: $0 <tarantool_binary> <prefix> [scale]}"
SCALE="${3:-1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results/${PREFIX}"

if [ ! -x "$TARANTOOL" ]; then
    echo "Error: '$TARANTOOL' is not executable"
    exit 1
fi

TT_VERSION="$("$TARANTOOL" --version 2>&1 | head -1)"

echo "Binary:   $TARANTOOL"
echo "Version:  $TT_VERSION"
echo "Prefix:   $PREFIX"
echo "Scale:    $SCALE"
echo "Results:  $RESULTS_DIR"
echo ""

mkdir -p "$RESULTS_DIR"

# Write a metadata file so analysis scripts know what produced these results.
cat > "${RESULTS_DIR}/meta.txt" <<EOF
prefix=$PREFIX
scale=$SCALE
binary=$TARANTOOL
version=$TT_VERSION
date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

# ── CSV header ────────────────────────────────────────────────────────────────
SUMMARY_CSV="${RESULTS_DIR}/summary.csv"
echo "prefix,benchmark,label,ops,elapsed_s,tps" > "$SUMMARY_CSV"

# ── parse_bench_line <prefix> <benchmark> <line> -> CSV row ───────────────────
#
# Input line format (from the Lua files):
#   [BENCH] <label...>  ops=<n>  elapsed=<t>s  TPS=<tps>
#
parse_bench_line() {
    local pfx="$1" bname="$2" line="$3"
    # Strip the [BENCH] prefix.
    line="${line#\[BENCH\] }"

    local label ops elapsed tps
    label="$(echo "$line" | sed -E 's/  +ops=.*//' | sed 's/[[:space:]]*$//')"
    ops="$(echo "$line" | sed -n 's/.*ops=[[:space:]]*\([0-9]\+\).*/\1/p')"
    elapsed="$(echo "$line" | sed -n 's/.*elapsed=[[:space:]]*\([0-9.]\+\)s.*/\1/p')"
    tps="$(echo "$line" | sed -n 's/.*TPS=[[:space:]]*\([0-9]\+\).*/\1/p')"

    echo "${pfx},${bname},${label},${ops},${elapsed},${tps}"
}

# ── run one benchmark ─────────────────────────────────────────────────────────
run_bench() {
    local name="$1"
    local optional="${2:-no}"
    local script="${SCRIPT_DIR}/${name}.lua"
    local bench_dir="${RESULTS_DIR}/${name}"
    local output_log="${bench_dir}/output.log"
    local bench_csv="${bench_dir}/results.csv"

    rm -rf  "$bench_dir"
    mkdir -p "$bench_dir"

    echo "=== ${name} ==="

    local exit_code=0
    # Run from bench_dir so box.cfg log/snapshot files land there.
    (cd "$bench_dir" && "$TARANTOOL" "$script" "$SCALE") \
        2>&1 | tee "$output_log" || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        if [ "$optional" = "yes" ]; then
            echo "Skipping ${name} (not supported/failed)"
            echo ""
            return
        fi
        echo "FAILED: ${name} (exit $exit_code)"
        FAILED_BENCHES="${FAILED_BENCHES} ${name}"
        echo ""
        return
    fi

    # Parse [BENCH] lines into a per-benchmark CSV.
    echo "prefix,benchmark,label,ops,elapsed_s,tps" > "$bench_csv"
    # Use || true to avoid pipefail if grep finds no matches.
    while IFS= read -r line; do
        parse_bench_line "$PREFIX" "$name" "$line" >> "$bench_csv"
    done < <(grep '^\[BENCH\]' "$output_log" | grep -v ' DONE' || true)

    # Append to summary (skip header line from bench_csv).
    tail -n +2 "$bench_csv" >> "$SUMMARY_CSV"

    echo ""
    echo "--- ${name} results ---"
    column -t -s, "$bench_csv" 2>/dev/null || cat "$bench_csv"
    echo ""
}

# ── run all benchmarks ────────────────────────────────────────────────────────

FAILED_BENCHES=""

run_bench "bench_memtx"
run_bench "bench_vinyl"
run_bench "bench_sort_order" "yes"

# ── final summary ─────────────────────────────────────────────────────────────

echo "================================================================"
echo "Summary CSV: ${SUMMARY_CSV}"
echo "================================================================"
column -t -s, "$SUMMARY_CSV" 2>/dev/null || cat "$SUMMARY_CSV"
echo ""
echo "Results directory layout:"
find "$RESULTS_DIR" -type f | sort | sed "s|${RESULTS_DIR}/||" | sed 's/^/  /'
echo ""
if [ -n "$FAILED_BENCHES" ]; then
    echo "FAILED:${FAILED_BENCHES}"
    echo "All other benchmarks complete."
else
    echo "All benchmarks complete."
fi
