#!/usr/bin/env bash
#
# Run benchmarks across multiple scales to test performance scaling.
#
# Usage:
#   ./run_scaling.sh <tarantool_binary> <prefix> <scale1> [scale2] ... [scaleN]
#
# Example:
#   ./run_scaling.sh ~/.local/bin/tarantool-master master 1 10 50
#

set -euo pipefail

TARANTOOL="${1:?Usage: $0 <tarantool_binary> <prefix> <scale1> [scale2] ...}"
PREFIX="${2:?Usage: $0 <tarantool_binary> <prefix> <scale1> [scale2] ...}"
shift 2
SCALES=("$@")

if [ ${#SCALES[@]} -eq 0 ]; then
    echo "Error: At least one scale must be provided."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for SCALE in "${SCALES[@]}"; do
    current_prefix="${PREFIX}_s${SCALE}"
    echo ">>> Running scaling test for scale: $SCALE (prefix: $current_prefix) <<<"
    "${SCRIPT_DIR}/run_all.sh" "$TARANTOOL" "$current_prefix" "$SCALE"
    echo ""
done

echo "Scaling tests complete."
echo "Results summary files:"
for SCALE in "${SCALES[@]}"; do
    echo "  ${SCRIPT_DIR}/results/${PREFIX}_s${SCALE}/summary.csv"
done
