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

echo "→ Compilazione della suite con coverage…"
WARNING_FLAGS=()
if [[ "${VERTEX_WARNINGS_AS_ERRORS:-0}" == "1" ]]; then
    WARNING_FLAGS=(-Xswiftc -warnings-as-errors)
fi
swift build -c debug \
    "${WARNING_FLAGS[@]}" \
    -Xswiftc -profile-generate \
    -Xswiftc -profile-coverage-mapping
# `--show-bin-path` only prints the build directory; it does not compile.
BIN="$(swift build -c debug --show-bin-path)/VertexTestRunner"

echo "→ Esecuzione test suite…"
PROFILE="$COVERAGE_DIR/default.profraw"
rm -f "$PROFILE" "$COVERAGE_DIR/default.profdata" \
    "$COVERAGE_DIR/coverage.txt" "$COVERAGE_DIR/coverage.lcov"

set +e
VERTEX_TEST_REPORT="$REPORT" \
VERTEX_KEYCHAIN_DISABLED=1 \
LLVM_PROFILE_FILE="$PROFILE" \
"$BIN"
TEST_STATUS=$?
set -e

if [ -f "$PROFILE" ]; then
    # With only the Command Line Tools the LLVM coverage tools may be missing.
    # A green suite must not turn into a red build because of a report.
    if xcrun -f llvm-profdata >/dev/null 2>&1 && xcrun -f llvm-cov >/dev/null 2>&1; then
        echo "→ Generazione report coverage…"
        if xcrun llvm-profdata merge -sparse "$PROFILE" \
            -o "$COVERAGE_DIR/default.profdata" \
            && xcrun llvm-cov report "$BIN" \
                -instr-profile="$COVERAGE_DIR/default.profdata" \
                -ignore-filename-regex='Tests/VertexTests' \
                > "$COVERAGE_DIR/coverage.txt" \
            && xcrun llvm-cov export "$BIN" \
                -instr-profile="$COVERAGE_DIR/default.profdata" \
                -ignore-filename-regex='Tests/VertexTests' \
                -format=lcov \
                > "$COVERAGE_DIR/coverage.lcov"; then
            printf 'Report:    %s\n' "$REPORT"
            printf 'Coverage:  %s\n' "$COVERAGE_DIR/coverage.txt"

            # Regression gate: the total line coverage may not fall below the
            # recorded floor. Raise VERTEX_MIN_COVERAGE as coverage improves.
            total="$(awk '/^TOTAL/ {gsub("%", "", $4); print $4}' "$COVERAGE_DIR/coverage.txt")"
            minimum="${VERTEX_MIN_COVERAGE:-62}"
            if [ -n "$total" ] && ! awk -v t="$total" -v m="$minimum" \
                'BEGIN { exit (t + 0 >= m + 0) ? 0 : 1 }'; then
                echo "✗ Coverage ${total}% sotto il minimo ${minimum}%" >&2
                exit 1
            fi
            printf 'Coverage minima: %s%%\n' "$minimum"
        else
            echo "⚠ Generazione del report coverage fallita (i test restano validi)" >&2
        fi
    else
        echo "⚠ Strumenti LLVM non disponibili: coverage saltata" >&2
    fi
else
    echo "⚠ LLVM non ha prodotto il profilo di coverage" >&2
fi

exit "$TEST_STATUS"
