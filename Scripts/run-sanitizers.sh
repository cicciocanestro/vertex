#!/usr/bin/env bash
# Runs the automated suite under a sanitizer.
#
# Usage: Scripts/run-sanitizers.sh thread|address
#
# The pinned engine dependencies are deliberately not instrumented: the point is
# to check our Swift code and the C++ bridge we own, not to rebuild libtorrent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-thread}"
case "$MODE" in
    thread|address) ;;
    *)
        echo "uso: $0 thread|address" >&2
        exit 2
        ;;
esac

"$ROOT/Scripts/build-deps.sh"

echo "→ Compilazione con sanitizer: $MODE"
swift build -c debug --sanitize="$MODE"

BIN="$(swift build -c debug --sanitize="$MODE" --show-bin-path)/VertexTestRunner"
if [[ ! -x "$BIN" ]]; then
    echo "✗ Test runner non trovato: $BIN" >&2
    exit 1
fi

echo "→ Esecuzione suite con sanitizer: $MODE"
export VERTEX_SANITIZER="$MODE"
export VERTEX_KEYCHAIN_DISABLED=1
if [[ "$MODE" == "thread" ]]; then
    TSAN_OPTIONS="${TSAN_OPTIONS:-halt_on_error=1}" "$BIN"
else
    ASAN_OPTIONS="${ASAN_OPTIONS:-halt_on_error=1}" "$BIN"
fi
