#!/usr/bin/env bash
set -euo pipefail

# Run the serial test suite with LLVM coverage and emit standard artifacts:
#   dist/test-results.xml       JUnit XML
#   dist/coverage/coverage.txt  llvm-cov text report
#   dist/coverage/coverage.lcov LCOV report
#
# This intentionally uses the same custom runner as `swift run` so it also
# works with Command Line Tools, where XCTest is not available.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPORT="${VERTEX_TEST_REPORT:-$ROOT/dist/test-results.xml}"
COVERAGE_DIR="${VERTEX_COVERAGE_DIR:-$ROOT/dist/coverage}"
mkdir -p "$(dirname "$REPORT")" "$COVERAGE_DIR"

BIN="$(swift build -c debug --show-bin-path)/VertexTestRunner"

echo "→ Compilazione della suite con coverage…"
swift build -c debug \
    -Xswiftc -profile-generate \
    -Xswiftc -profile-coverage-mapping

echo "→ Esecuzione test suite…"
PROFILE="$COVERAGE_DIR/default.profraw"
rm -f "$PROFILE" "$COVERAGE_DIR/default.profdata"

set +e
VERTEX_TEST_REPORT="$REPORT" \
LLVM_PROFILE_FILE="$PROFILE" \
"$BIN"
TEST_STATUS=$?
set -e

if [ -f "$PROFILE" ]; then
    echo "→ Generazione report coverage…"
    xcrun llvm-profdata merge -sparse "$PROFILE" \
        -o "$COVERAGE_DIR/default.profdata"
    xcrun llvm-cov report "$BIN" \
        -instr-profile="$COVERAGE_DIR/default.profdata" \
        -ignore-filename-regex='Tests/VertexTests' \
        > "$COVERAGE_DIR/coverage.txt"
    xcrun llvm-cov export "$BIN" \
        -instr-profile="$COVERAGE_DIR/default.profdata" \
        -ignore-filename-regex='Tests/VertexTests' \
        -format=lcov \
        > "$COVERAGE_DIR/coverage.lcov"
    printf 'Report:    %s\n' "$REPORT"
    printf 'Coverage:  %s\n' "$COVERAGE_DIR/coverage.txt"
else
    echo "⚠ LLVM non ha prodotto il profilo di coverage" >&2
fi

exit "$TEST_STATUS"
