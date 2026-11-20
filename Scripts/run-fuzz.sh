#!/usr/bin/env bash
# Coverage-guided fuzzing for the string escaping shared with the snapshot
# encoder. The target is header-only, so no engine dependency is needed.
#
# Usage: Scripts/run-fuzz.sh [seconds]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SECONDS_TO_RUN="${1:-${VERTEX_FUZZ_SECONDS:-60}}"
OUT="$ROOT/.build/fuzz"
CORPUS="$OUT/corpus"
mkdir -p "$CORPUS"

# Deterministic starting points: plain text, every escape, control bytes, valid
# multi-byte sequences and a malformed one.
if [ -z "$(ls -A "$CORPUS" 2>/dev/null)" ]; then
    printf '%s' 'plain-ascii' >"$CORPUS/plain"
    printf '%s' 'a"b\c' >"$CORPUS/escapes"
    printf '\n\t\r\b\f' >"$CORPUS/control"
    printf '\xc3\xa9\xe2\x9c\x93' >"$CORPUS/utf8"
    printf '\xf0\x9f\x8c\x8d' >"$CORPUS/emoji"
    printf 'bad\xff\xfe' >"$CORPUS/invalid"
fi

# The CommandLineTools clang++ needs the SDK environment that `xcrun` sets;
# invoking its binary path directly cannot find the C++ standard headers.
if command -v xcrun >/dev/null 2>&1; then
    CLANG=(xcrun --sdk macosx clang++)
else
    CLANG=(clang++)
fi

# libFuzzer is the better driver, but the CommandLineTools do not ship its
# runtime. Use it when available, otherwise fall back to the mutation driver
# with the same invariants under ASan/UBSan.
RESOURCE_DIR="$("${CLANG[@]}" -print-resource-dir 2>/dev/null || true)"
if [ -n "$RESOURCE_DIR" ] && [ -f "$RESOURCE_DIR/lib/darwin/libclang_rt.fuzzer_osx.a" ]; then
    echo "→ Compilazione dell'harness libFuzzer…"
    "${CLANG[@]}" -std=c++17 -O1 -g -fno-omit-frame-pointer \
        -fsanitize=fuzzer,address,undefined \
        -I Sources/CTorrent \
        Fuzz/strings_fuzzer.cpp -o "$OUT/strings-fuzzer"

    echo "→ Fuzzing coverage-guided per ${SECONDS_TO_RUN}s…"
    "$OUT/strings-fuzzer" "$CORPUS" \
        -max_total_time="$SECONDS_TO_RUN" \
        -max_len=8192 \
        -print_final_stats=1
else
    echo "→ Runtime libFuzzer assente: driver mutazionale con ASan/UBSan"
    "${CLANG[@]}" -std=c++17 -O1 -g -fno-omit-frame-pointer \
        -fsanitize=address,undefined \
        -I Sources/CTorrent \
        Fuzz/strings_fuzzer.cpp Fuzz/mutation_main.cpp -o "$OUT/strings-fuzzer"

    echo "→ Fuzzing mutazionale per ${SECONDS_TO_RUN}s…"
    "$OUT/strings-fuzzer" "$SECONDS_TO_RUN"
fi
