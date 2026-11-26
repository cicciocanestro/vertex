#!/usr/bin/env bash
set -euo pipefail

# Imports the self-signed signing certificate into a temporary keychain.
#
# Used by CI before build.sh. Without VERTEX_SIGN_P12 the step is a no-op and
# the build stays ad-hoc, so this script is safe on forks and local runs.
#
# Environment (from repository secrets):
#   VERTEX_SIGN_P12           base64 of the .p12 (single line)
#   VERTEX_SIGN_P12_PASSWORD  password of the .p12
#   VERTEX_SIGN_IDENTITY      identity name, e.g. "Vertex Self-Signed"

if [ -z "${VERTEX_SIGN_P12:-}" ]; then
    echo "· Certificato di firma non configurato: la build resterà ad-hoc."
    exit 0
fi

: "${VERTEX_SIGN_P12_PASSWORD:?VERTEX_SIGN_P12_PASSWORD non impostata}"

if ! command -v security >/dev/null 2>&1; then
    echo "✗ security non disponibile: questo script gira su macOS" >&2
    exit 1
fi

umask 077
WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vertex-signing.XXXXXX")"
chmod 700 "$WORK"
KEYCHAIN="$WORK/vertex-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"
P12="$WORK/vertex-signing.p12"

EXISTING_KEYCHAINS=()
while IFS= read -r kc_line; do
    kc_clean="$(printf '%s' "$kc_line" | sed 's/^ *//; s/"//g')"
    [ -n "$kc_clean" ] && EXISTING_KEYCHAINS+=("$kc_clean")
done < <(security list-keychains -d user)

# Always wipe the decoded PKCS#12 file. On failure (or in standalone local runs
# where GITHUB_ENV is unset and cleanup-signing-cert.sh will not run later),
# restore the original keychain search list and remove the temporary keychain
# and working directory.
IMPORTED=0
KEYCHAIN_LIST_MODIFIED=0
CLEANED_UP=0
cleanup_keychain() {
    if [ "$CLEANED_UP" -eq 1 ]; then
        return 0
    fi
    CLEANED_UP=1
    rm -f "$P12"
    local keep_keychain=0
    if [ "$IMPORTED" -eq 1 ] && { [ -n "${GITHUB_ENV:-}" ] || [ "${VERTEX_KEEP_SIGNING_KEYCHAIN:-0}" = "1" ]; }; then
        keep_keychain=1
    fi
    if [ "$keep_keychain" -ne 1 ]; then
        if [ "$KEYCHAIN_LIST_MODIFIED" -eq 1 ] && [ "${#EXISTING_KEYCHAINS[@]}" -gt 0 ]; then
            security list-keychains -d user -s "${EXISTING_KEYCHAINS[@]}" >/dev/null 2>&1 || true
        fi
        security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
        rm -rf "$WORK"
    fi
}
trap cleanup_keychain EXIT
trap 'cleanup_keychain; exit 130' INT
trap 'cleanup_keychain; exit 143' TERM

echo "→ Import del certificato in un keychain temporaneo…"
printf '%s' "$VERTEX_SIGN_P12" | tr -d '\n\r' | base64 -D > "$P12"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

security import "$P12" -k "$KEYCHAIN" \
    -P "$VERTEX_SIGN_P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

# Add the keychain to the user search list; codesign looks there.
security list-keychains -d user -s "$KEYCHAIN" "${EXISTING_KEYCHAINS[@]}"
KEYCHAIN_LIST_MODIFIED=1

rm -f "$P12"

IDENTITY="${VERTEX_SIGN_IDENTITY:-Vertex Self-Signed}"
case "$IDENTITY$KEYCHAIN" in
    *$'\n'*|*$'\r'*)
        echo "✗ Caratteri di ritorno a capo non validi nell'identità o nel percorso keychain" >&2
        exit 1
        ;;
esac
if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "✗ Identità '$IDENTITY' non trovata nel keychain importato" >&2
    security find-identity -p codesigning "$KEYCHAIN" >&2 || true
    exit 1
fi

echo "✓ Certificato pronto: $IDENTITY"
IMPORTED=1
if [ -n "${GITHUB_ENV:-}" ]; then
    {
        printf 'VERTEX_SIGN_IDENTITY=%s\n' "$IDENTITY"
        printf 'VERTEX_SIGNING_EXPECTED=1\n'
        printf 'VERTEX_SIGNING_KEYCHAIN=%s\n' "$KEYCHAIN"
        printf 'VERTEX_SIGNING_WORK=%s\n' "$WORK"
    } >> "$GITHUB_ENV"
elif [ "${VERTEX_KEEP_SIGNING_KEYCHAIN:-0}" != "1" ]; then
    echo "· Esecuzione locale senza GITHUB_ENV: il keychain temporaneo verrà rimosso a fine script."
fi
