#!/usr/bin/env bash
# Runs the complete suite repeatedly to catch flakiness that a single green run
# hides. Logs stay outside the repository (.build/stress).
#
# Usage: Scripts/stress-tests.sh [runs]   (default: 20)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUNS="${1:-20}"
LOG_DIR="${VERTEX_STRESS_DIR:-$ROOT/.build/stress}"
mkdir -p "$LOG_DIR"

for run in $(seq 1 "$RUNS"); do
    echo "→ Run $run/$RUNS"
    if ! ./build.sh test >"$LOG_DIR/run-$run.log" 2>&1; then
        echo "✗ Run $run fallita: $LOG_DIR/run-$run.log" >&2
        tail -20 "$LOG_DIR/run-$run.log" >&2
        exit 1
    fi
    grep -E "Superati:|Falliti:" "$LOG_DIR/run-$run.log" | tail -2 || true
done

echo "✓ $RUNS run consecutive verdi (log in $LOG_DIR)"
