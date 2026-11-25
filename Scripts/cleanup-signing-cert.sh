#!/usr/bin/env bash
set -euo pipefail

# Removes the temporary signing keychain created by import-signing-cert.sh.
# Always runs as a final CI step (`if: always()`).

if [ -z "${VERTEX_SIGNING_KEYCHAIN:-}" ]; then
    exit 0
fi

if command -v security >/dev/null 2>&1; then
    REMAINING=()
    while IFS= read -r kc_line; do
        kc_clean="$(printf '%s' "$kc_line" | sed 's/^ *//; s/"//g')"
        if [ -n "$kc_clean" ] && [ "$kc_clean" != "$VERTEX_SIGNING_KEYCHAIN" ]; then
            REMAINING+=("$kc_clean")
        fi
    done < <(security list-keychains -d user 2>/dev/null || true)
    if [ "${#REMAINING[@]}" -gt 0 ]; then
        security list-keychains -d user -s "${REMAINING[@]}" >/dev/null 2>&1 || true
    fi
    security delete-keychain "$VERTEX_SIGNING_KEYCHAIN" >/dev/null 2>&1 || true
fi
echo "· Keychain di firma temporaneo rimosso."
