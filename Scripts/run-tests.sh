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

"$ROOT/Scripts/build-deps.sh"

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

TEST_ISO_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vertex-tests.XXXXXX")"
TEST_DEFAULTS_SUITE="${VERTEX_DEFAULTS_SUITE:-app.vertex.torrent.tests.$$}"
OWN_DEFAULTS_SUITE=0
if [ -z "${VERTEX_DEFAULTS_SUITE:-}" ]; then
    OWN_DEFAULTS_SUITE=1
fi
CLEANED_UP=0
cleanup() {
    if [ "$CLEANED_UP" -eq 1 ]; then
        return 0
    fi
    CLEANED_UP=1
    if [ "$OWN_DEFAULTS_SUITE" -eq 1 ]; then
        defaults delete "$TEST_DEFAULTS_SUITE" >/dev/null 2>&1 || true
    fi
    rm -rf "$TEST_ISO_DIR"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

set +e
VERTEX_TEST_REPORT="$REPORT" \
VERTEX_DATA_DIR="${VERTEX_DATA_DIR:-$TEST_ISO_DIR/data}" \
VERTEX_DOWNLOADS_DIR="${VERTEX_DOWNLOADS_DIR:-$TEST_ISO_DIR/downloads}" \
VERTEX_DEFAULTS_SUITE="$TEST_DEFAULTS_SUITE" \
VERTEX_NOTIFICATIONS_DISABLED=1 \
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

            # Regression gate: the total region coverage ($4 of TOTAL) may not
            # fall below the recorded floor. Raise VERTEX_MIN_COVERAGE as it grows.
            total="$(awk '/^TOTAL/ {gsub("%", "", $4); print $4}' "$COVERAGE_DIR/coverage.txt")"
            minimum="${VERTEX_MIN_COVERAGE:-63}"
            if [ -z "$total" ]; then
                echo "✗ Impossibile estrarre la percentuale TOTAL da $COVERAGE_DIR/coverage.txt" >&2
                exit 1
            fi
            if ! awk -v t="$total" -v m="$minimum" \
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
