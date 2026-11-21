#!/usr/bin/env bash
# Enforces the Swift formatting baseline. The configuration uses four spaces
# and 120 columns, matching the existing style; multiline strings are never
# reflowed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! swift format --version >/dev/null 2>&1; then
    echo "✗ swift format non disponibile: serve la toolchain Swift 6+ (Xcode)" >&2
    exit 1
fi

echo "→ Controllo formato Swift (swift-format)…"
swift format lint --strict --configuration .swift-format --recursive Sources Tests
