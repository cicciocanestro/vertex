#!/usr/bin/env bash
set -euo pipefail

# Submits the release DMG to Apple's notary service and staples the ticket.
#
# Preconditions (none of them is set up in this repository, so the script is a
# no-op unless the operator provides them):
#   VERTEX_SIGN_IDENTITY   "Developer ID Application: ..." used by build.sh
#   VERTEX_NOTARY_PROFILE  profile created with
#                          `xcrun notarytool store-credentials <profile> \
#                              --apple-id <id> --team-id <team> --password <pw>`
#
# Usage: Scripts/notarize.sh [path/to/Vertex-<version>-<os>-<arch>.dmg]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=Scripts/app.env
source "$ROOT/Scripts/app.env"

PROFILE="${VERTEX_NOTARY_PROFILE:-}"
if [ -z "$PROFILE" ]; then
    echo "· Notarizzazione saltata: VERTEX_NOTARY_PROFILE non impostato."
    exit 0
fi

DMG="${1:-}"
if [ -z "$DMG" ]; then
    DMG="$(ls -t dist/"${VERTEX_APP_NAME}"-*.dmg 2>/dev/null | head -1 || true)"
fi
if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then
    echo "✗ DMG non trovato. Esegui prima ./Scripts/make-dmg.sh --no-build" >&2
    exit 1
fi

if ! codesign --verify --strict dist/"${VERTEX_APP_NAME}".app 2>/dev/null; then
    echo "✗ Il bundle non è firmato: imposta VERTEX_SIGN_IDENTITY e ricompila" >&2
    exit 1
fi
if codesign -dv --verbose=2 dist/"${VERTEX_APP_NAME}".app 2>&1 | grep -q "Signature=adhoc"; then
    echo "✗ Firma ad-hoc: la notarizzazione richiede una Developer ID" >&2
    exit 1
fi

echo "→ Invio a Apple (profilo: $PROFILE)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "→ Applico il ticket…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# stapling rewrites the image: the published checksum must be recomputed.
echo "→ Rigenero il checksum…"
( cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )
echo "✓ DMG notarizzato: $DMG"
