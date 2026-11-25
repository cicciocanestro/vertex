#!/usr/bin/env bash
set -euo pipefail

# Submits the release DMG to Apple's notary service and staples the ticket.
#
# Preconditions:
#   VERTEX_SIGN_IDENTITY   "Developer ID Application: ..." used by build.sh
#   VERTEX_NOTARY_PROFILE  profile created with
#                          `xcrun notarytool store-credentials <profile> \
#                              --apple-id <id> --team-id <team> --password <pw>`
#   VERTEX_NOTARIZATION_REQUIRED=1 makes a missing profile a hard failure
#                          (used by the release workflow gate).
#
# Usage: Scripts/notarize.sh [path/to/Vertex-<version>-<os>-<arch>.dmg]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=Scripts/app.env
source "$ROOT/Scripts/app.env"

PROFILE="${VERTEX_NOTARY_PROFILE:-}"
if [ -z "$PROFILE" ]; then
    if [ "${VERTEX_NOTARIZATION_REQUIRED:-0}" = "1" ]; then
        echo "✗ VERTEX_NOTARIZATION_REQUIRED=1 ma VERTEX_NOTARY_PROFILE non è impostato" >&2
        exit 1
    fi
    echo "· Notarizzazione saltata: VERTEX_NOTARY_PROFILE non impostato."
    exit 0
fi

# Derive the expected file name instead of taking the newest DMG in dist/: a
# stale image from another version or architecture must not be notarized.
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
DEFAULT_DMG="dist/${VERTEX_APP_NAME}-${VERSION}-macOS${VERTEX_MIN_MACOS}-${VERTEX_ARCH}.dmg"
DMG="${1:-$DEFAULT_DMG}"
if [ ! -f "$DMG" ]; then
    echo "✗ DMG non trovato: $DMG" >&2
    echo "  Esegui prima ./Scripts/make-dmg.sh --no-build" >&2
    exit 1
fi

# Verify the application that is actually inside the image: dist/Vertex.app may
# be newer or older than the DMG that is about to be submitted.
attach_image() {
    local help
    help=$(diskutil image attach --help 2>/dev/null || true)
    if grep -q -- '--mountPoint' <<<"$help" &&
        grep -q -- '--readOnly' <<<"$help" &&
        grep -q -- '--nobrowse' <<<"$help"; then
        diskutil image attach --nobrowse --readOnly --mountPoint "$2" "$1" >/dev/null
    else
        hdiutil attach "$1" -nobrowse -readonly -mountpoint "$2" >/dev/null
    fi
}

detach_image() {
    if diskutil eject "$1" >/dev/null 2>&1; then
        return 0
    fi
    hdiutil detach "$1" >/dev/null 2>&1 || true
}

MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/vertex-notarize.XXXXXX")"
cleanup() {
    detach_image "$MOUNT"
    rmdir "$MOUNT" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

attach_image "$DMG" "$MOUNT"
APP_IN_IMAGE="$MOUNT/${VERTEX_APP_NAME}.app"
if [ ! -d "$APP_IN_IMAGE" ]; then
    echo "✗ L'immagine non contiene ${VERTEX_APP_NAME}.app" >&2
    exit 1
fi

"$ROOT/Scripts/verify-bundle.sh" "$APP_IN_IMAGE" "$VERTEX_MIN_MACOS" "$VERTEX_ARCH"

if ! codesign -dv --verbose=2 "$APP_IN_IMAGE" 2>&1 | grep -q "Authority=Developer ID Application"; then
    echo "✗ La notarizzazione richiede un certificato Developer ID." >&2
    echo "  Un certificato self-signed serve solo a rendere stabile l'identità, non è accettato da Apple." >&2
    exit 1
fi

cleanup
trap - EXIT INT TERM

echo "→ Invio a Apple (profilo: $PROFILE)…"
set +e
SUBMIT_OUTPUT="$(xcrun notarytool submit "$DMG" \
    --keychain-profile "$PROFILE" --wait --timeout 30m 2>&1)"
SUBMIT_STATUS=$?
set -e
printf '%s\n' "$SUBMIT_OUTPUT"

if [ "$SUBMIT_STATUS" -ne 0 ] || ! printf '%s\n' "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    SUBMISSION_ID="$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^ *id:/ {print $2; exit}')"
    if [ -n "$SUBMISSION_ID" ]; then
        echo "→ Log della submission $SUBMISSION_ID:" >&2
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" >&2 || true
    fi
    echo "✗ Notarizzazione rifiutata" >&2
    exit 1
fi

echo "→ Applico il ticket…"
stapled=0
for attempt in 1 2 3; do
    if xcrun stapler staple "$DMG"; then
        stapled=1
        break
    fi
    echo "· Tentativo $attempt fallito, riprovo…" >&2
    sleep 5
done
if [ "$stapled" -ne 1 ]; then
    echo "✗ Impossibile applicare il ticket" >&2
    exit 1
fi
xcrun stapler validate "$DMG"

echo "→ Verifica Gatekeeper…"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

# stapling rewrites the image: the published checksum must be recomputed.
echo "→ Rigenero il checksum…"
( cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )
echo "✓ DMG notarizzato: $DMG"
