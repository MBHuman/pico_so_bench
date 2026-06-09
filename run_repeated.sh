#!/usr/bin/env bash
#
# Run benchmarks N times to allow for confidence interval calculation.
#
# Usage:
#   ./run_repeated.sh <tarantool_binary> <prefix> <scale> <iterations>
#
# Results are saved to:
#   ./results/<prefix>_s<scale>_i<iteration>/
#
# A consolidated CSV is written to ./results/<prefix>_s<scale>_repeated.csv

set -euo pipefail

TARANTOOL="${1:?Usage: $0 <tarantool_binary> <prefix> <scale> <iterations>}"
PREFIX="${2:?Usage: $0 <tarantool_binary> <prefix> <scale> <iterations>}"
SCALE="${3:?Usage: $0 <tarantool_binary> <prefix> <scale> <iterations>}"
ITERATIONS="${4:?Usage: $0 <tarantool_binary> <prefix> <scale> <iterations>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_RESULTS_DIR="${SCRIPT_DIR}/results"
SUMMARY_FILE="${BASE_RESULTS_DIR}/${PREFIX}_s${SCALE}_repeated.csv"

mkdir -p "$BASE_RESULTS_DIR"

echo "Running $ITERATIONS iterations for prefix=$PREFIX at scale=$SCALE"
echo "Consolidated results: $SUMMARY_FILE"
echo "----------------------------------------------------------------"

# Write header for consolidated CSV
echo "iteration,prefix,benchmark,label,ops,elapsed_s,tps" > "$SUMMARY_FILE"

for i in $(seq 1 "$ITERATIONS"); do
    CURRENT_PREFIX="${PREFIX}_s${SCALE}_i${i}"
    echo ">>> Iteration $i / $ITERATIONS (Prefix: $CURRENT_PREFIX) <<<"
    
    # Run the standard benchmark script
    ./run_all.sh "$TARANTOOL" "$CURRENT_PREFIX" "$SCALE"
    
    # Extract results and prepend iteration number
    # summary.csv has header: prefix,benchmark,label,ops,elapsed_s,tps
    RESULT_CSV="${BASE_RESULTS_DIR}/${CURRENT_PREFIX}/summary.csv"
    if [ -f "$RESULT_CSV" ]; then
        tail -n +2 "$RESULT_CSV" | while IFS= read -r line; do
            echo "${i},${line}" >> "$SUMMARY_FILE"
        done
    else
        echo "Warning: Results for iteration $i not found."
    fi
    echo ""
done

echo "----------------------------------------------------------------"
echo "Done! Consolidated results in $SUMMARY_FILE"
echo "You can now use this CSV to calculate means and confidence intervals."
