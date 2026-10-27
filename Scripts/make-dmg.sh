#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=Scripts/app.env
source Scripts/app.env

if [ "${1:-}" != "--no-build" ]; then
    ./build.sh
fi

APP="dist/${VERTEX_APP_NAME}.app"
if [ ! -d "$APP" ]; then
    echo "✗ $APP non trovata. Esegui prima ./build.sh"
    exit 1
fi

BIN="$APP/Contents/MacOS/${VERTEX_APP_NAME}"
INFO="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
MIN_OS="$VERTEX_MIN_MACOS"
ARCHS=$(lipo -archs "$BIN")

echo "→ Verifica del bundle prima della DMG…"
./Scripts/verify-bundle.sh "$APP"

if [[ "$ARCHS" == *" "* ]]; then
    ARCH_LABEL="universal"
else
    ARCH_LABEL="$ARCHS"
fi

DMG="dist/${VERTEX_APP_NAME}-${VERSION}-macOS${MIN_OS}-${ARCH_LABEL}.dmg"
DMG_SHA="$DMG.sha256"
VOLUME="${VERTEX_APP_NAME} ${VERSION}"
STAGE="dist/.dmg-stage"

MOUNT=""
cleanup() {
    if [ -n "$MOUNT" ]; then
        hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
        rmdir "$MOUNT" 2>/dev/null || true
    fi
    rm -rf "$STAGE"
}
trap cleanup EXIT

echo "→ Preparazione della DMG ($ARCH_LABEL, macOS $MIN_OS)…"
rm -rf "$STAGE"
mkdir -p "$STAGE"

ditto "$APP" "$STAGE/${VERTEX_APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/Leggimi.txt" <<EOF
${VERTEX_APP_NAME} ${VERSION} — client BitTorrent per macOS
================================================

Requisiti
---------
- macOS ${MIN_OS} o successivo
- Architettura: ${ARCH_LABEL}

Installazione
-------------
1. Trascina ${VERTEX_APP_NAME} nella cartella Applicazioni.
2. Al primo avvio, se macOS blocca l'app:
   - fai clic destro su ${VERTEX_APP_NAME} e scegli "Apri", oppure
   - vai in Impostazioni di Sistema > Privacy e Sicurezza e scegli "Apri comunque".

Note
----
- L'app è firmata ad-hoc e non è notarizzata da Apple.
- libtorrent, OpenSSL e le rispettive licenze sono incluse nell'app.
- Licenze: menu ${VERTEX_APP_NAME} > Licenze open source.
- Progetto: https://github.com/cicciocanestro/vertex
- Interfaccia: italiano se il sistema è in italiano, altrimenti inglese.

${VERTEX_APP_NAME} ${VERSION} — BitTorrent client for macOS
================================================

Requirements
------------
- macOS ${MIN_OS} or later
- Architecture: ${ARCH_LABEL}

Installation
------------
1. Drag ${VERTEX_APP_NAME} into the Applications folder.
2. On first launch, if macOS blocks the app:
   - right-click ${VERTEX_APP_NAME} and choose "Open", or
   - go to System Settings > Privacy & Security and choose "Open Anyway".

Notes
-----
- The app is ad-hoc signed and not notarized by Apple.
- libtorrent, OpenSSL and their licenses are bundled with the app.
- Licenses: ${VERTEX_APP_NAME} menu > Open source licenses.
- Project: https://github.com/cicciocanestro/vertex
- Interface: Italian when the system language is Italian, English otherwise.
EOF

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
    SetFile -a C "$STAGE" 2>/dev/null || true
fi

rm -f "$DMG" "$DMG_SHA"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG" >/dev/null

hdiutil verify "$DMG" >/dev/null
(
    cd "$(dirname "$DMG")"
    shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256"
)

echo "→ Verifica del contenuto montato…"
MOUNT=$(mktemp -d /tmp/vertex-dmg.XXXXXX)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
./Scripts/verify-bundle.sh "$MOUNT/${VERTEX_APP_NAME}.app"
test -L "$MOUNT/Applications"
test -d "$MOUNT/${VERTEX_APP_NAME}.app/Contents/Resources/Licenses"
test -f "$MOUNT/Leggimi.txt"
hdiutil detach "$MOUNT" >/dev/null
rmdir "$MOUNT"
MOUNT=""

rm -rf "$STAGE"

echo "✓ DMG creata: $DMG"
echo "  SHA256:     $DMG_SHA"
echo "  Dimensione: $(du -h "$DMG" | awk '{print $1}')"
echo
echo "Nota: la firma è ad-hoc. Per una distribuzione pubblica senza avvisi"
echo "      Gatekeeper serve una firma Developer ID e la notarizzazione Apple."
