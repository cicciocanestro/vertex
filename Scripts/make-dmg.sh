#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ "${1:-}" != "--no-build" ]; then
    ./build.sh
fi

APP="dist/Vertex.app"
if [ ! -d "$APP" ]; then
    echo "✗ $APP non trovata. Esegui prima ./build.sh"
    exit 1
fi

BIN="$APP/Contents/MacOS/Vertex"
INFO="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
MIN_OS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")
ARCHS=$(lipo -archs "$BIN")
if [[ "$ARCHS" == *" "* ]]; then
    ARCH_LABEL="universal"
else
    ARCH_LABEL="$ARCHS"
fi

DMG="dist/Vertex-${VERSION}-macOS${MIN_OS}-${ARCH_LABEL}.dmg"
DMG_SHA="$DMG.sha256"
VOLUME="Vertex ${VERSION}"
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

ditto "$APP" "$STAGE/Vertex.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/Leggimi.txt" <<EOF
Vertex ${VERSION} — client BitTorrent per macOS
================================================

Requisiti
---------
- macOS ${MIN_OS} o successivo
- Architettura: ${ARCH_LABEL}

Installazione
-------------
1. Trascina Vertex nella cartella Applicazioni.
2. Al primo avvio, se macOS blocca l'app:
   - fai clic destro su Vertex e scegli "Apri", oppure
   - vai in Impostazioni di Sistema > Privacy e Sicurezza e scegli "Apri comunque".

Note
----
- L'app è firmata ad-hoc e non è notarizzata da Apple.
- libtorrent, OpenSSL e le rispettive licenze sono incluse nell'app.
- Licenze: menu Vertex > Licenze open source.
- Progetto: https://github.com/cicciocanestro/vertex
- Interfaccia: italiano se il sistema è in italiano, altrimenti inglese.

Vertex ${VERSION} — BitTorrent client for macOS
================================================

Requirements
------------
- macOS ${MIN_OS} or later
- Architecture: ${ARCH_LABEL}

Installation
------------
1. Drag Vertex into the Applications folder.
2. On first launch, if macOS blocks the app:
   - right-click Vertex and choose "Open", or
   - go to System Settings > Privacy & Security and choose "Open Anyway".

Notes
-----
- The app is ad-hoc signed and not notarized by Apple.
- libtorrent, OpenSSL and their licenses are bundled with the app.
- Licenses: Vertex menu > Open source licenses.
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
codesign --verify --deep --strict "$MOUNT/Vertex.app"
test -L "$MOUNT/Applications"
test -d "$MOUNT/Vertex.app/Contents/Resources/Licenses"
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
