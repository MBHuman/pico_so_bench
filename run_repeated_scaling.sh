#!/usr/bin/env bash
#
# Run benchmarks repeatedly for multiple scales.
#
# Usage:
#   ./run_repeated_scaling.sh <tarantool_binary> <prefix> <iterations> <scale1> [scale2] [scale3] ...
#
# Example:
#   ./run_repeated_scaling.sh ./tarantool master 5 1 10 50

set -euo pipefail

TARANTOOL="${1:?Usage: $0 <tarantool_binary> <prefix> <iterations> <scale1> [scale2] ...}"
PREFIX="${2:?Usage: $0 <tarantool_binary> <prefix> <iterations> <scale1> [scale2] ...}"
ITERATIONS="${3:?Usage: $0 <tarantool_binary> <prefix> <iterations> <scale1> [scale2] ...}"
shift 3
SCALES=("$@")

if [ ${#SCALES[@]} -eq 0 ]; then
    echo "Error: No scales specified."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Starting repeated scaling run: $PREFIX"
echo "Binary: $TARANTOOL"
echo "Iterations per scale: $ITERATIONS"
echo "Scales: ${SCALES[*]}"
echo "----------------------------------------------------------------"

for scale in "${SCALES[@]}"; do
    echo "==== SCALE: $scale ===="
    ./run_repeated.sh "$TARANTOOL" "$PREFIX" "$scale" "$ITERATIONS"
    echo ""
done

echo "----------------------------------------------------------------"
echo "All repeated scaling runs complete for $PREFIX."
