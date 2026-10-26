#!/usr/bin/env bash
set -euo pipefail

# Verify that the current machine matches the canonical release toolchain.
#
# --warn   (default) print differences but allow local development builds
# --strict fail on any difference; used for tagged release builds in CI

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=Scripts/deps.env
source "$ROOT/Scripts/deps.env"
# shellcheck source=Scripts/toolchain.env
source "$ROOT/Scripts/toolchain.env"

MODE="${1:---warn}"
case "$MODE" in
    --warn|--strict) ;;
    *)
        echo "Uso: $0 [--warn|--strict]" >&2
        exit 2
        ;;
esac

MISMATCHES=0

compare() {
    local label="$1"
    local expected="$2"
    local actual="$3"

    if [ "$actual" = "$expected" ]; then
        printf '  ✓ %-20s %s\n' "$label" "$actual"
    else
        MISMATCHES=$((MISMATCHES + 1))
        printf '  ✗ %-20s atteso %s, trovato %s\n' \
            "$label" "$expected" "${actual:-non disponibile}" >&2
    fi
}

actual_arch="$(uname -m)"
actual_macos="$(sw_vers -productVersion)"

actual_cmake=""
if command -v cmake >/dev/null 2>&1; then
    actual_cmake="$({ cmake --version 2>/dev/null || true; } | awk 'NR==1 {print $3; exit}')"
fi

actual_xcode=""
actual_xcode_build=""
actual_developer_dir="$(xcode-select -p 2>/dev/null || true)"
if command -v xcodebuild >/dev/null 2>&1; then
    xcode_version_output="$(xcodebuild -version 2>/dev/null || true)"
    actual_xcode="$(printf '%s\n' "$xcode_version_output" | awk 'NR==1 {print $2; exit}')"
    actual_xcode_build="$(printf '%s\n' "$xcode_version_output" | awk '/^Build version/ {print $3; exit}')"
fi

actual_sdk=""
if command -v xcrun >/dev/null 2>&1; then
    actual_sdk="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
fi

actual_swift=""
if command -v swift >/dev/null 2>&1; then
    actual_swift="$({ swift --version 2>&1 || true; } | sed -n '1,2p' | tr '\n' ' ')"
fi

echo "→ Toolchain Vertex"
printf '  Runner:              %s\n' "${ImageOS:-locale}"
printf '  Immagine runner:     %s\n' "${ImageVersion:-non impostata}"
printf '  Swift:               %s\n' "${actual_swift:-non disponibile}"

compare "Architettura" "$VERTEX_DEPS_ARCH" "$actual_arch"
compare "macOS" "$VERTEX_CANONICAL_MACOS_VERSION" "$actual_macos"
compare "Xcode" "$VERTEX_CANONICAL_XCODE_VERSION" "$actual_xcode"
compare "Xcode build" "$VERTEX_CANONICAL_XCODE_BUILD" "$actual_xcode_build"
compare "Xcode path" "$VERTEX_CANONICAL_XCODE_PATH/Contents/Developer" "$actual_developer_dir"
compare "macOS SDK" "$VERTEX_CANONICAL_MACOS_SDK" "$actual_sdk"
compare "CMake" "$VERTEX_CANONICAL_CMAKE_VERSION" "$actual_cmake"

if [ -n "${ImageVersion:-}" ]; then
    compare "Immagine runner" "$VERTEX_CANONICAL_RUNNER_IMAGE" "$ImageVersion"
elif [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    MISMATCHES=$((MISMATCHES + 1))
    printf '  ✗ %-20s non impostata in GitHub Actions\n' "Immagine runner" >&2
else
    printf '  · %-20s build locale, non verificabile\n' "Immagine runner"
fi

if [ "$MISMATCHES" -eq 0 ]; then
    echo "✓ Toolchain canonico verificato."
    exit 0
fi

if [ "$MODE" = "--strict" ]; then
    echo "✗ Toolchain non canonico: la release è bloccata." >&2
    echo "  Aggiorna Scripts/toolchain.env solo dopo aver validato il nuovo ambiente." >&2
    exit 1
fi

echo "⚠ Toolchain locale diverso da quello canonico." >&2
echo "  La build è valida per lo sviluppo, ma non è l'artefatto di release." >&2
exit 0
