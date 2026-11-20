#!/usr/bin/env bash
set -euo pipefail

# Removes the temporary signing keychain created by import-signing-cert.sh.
# Always runs as a final CI step (`if: always()`).

if [ -z "${VERTEX_SIGNING_KEYCHAIN:-}" ]; then
    exit 0
fi

if command -v security >/dev/null 2>&1; then
    security delete-keychain "$VERTEX_SIGNING_KEYCHAIN" >/dev/null 2>&1 || true
fi
echo "· Keychain di firma temporaneo rimosso."
