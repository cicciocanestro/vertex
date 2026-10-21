#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Vertex"
APP_PATH="dist/${APP_NAME}.app"
APP_BIN="${APP_PATH}/Contents/MacOS/${APP_NAME}"
FRAMEWORKS="${APP_PATH}/Contents/Frameworks"

if command -v brew >/dev/null 2>&1; then
    export HOMEBREW_PREFIX="$(brew --prefix)"
else
    export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
fi

LIBTORRENT_LIB="${HOMEBREW_PREFIX}/opt/libtorrent-rasterbar/lib/libtorrent-rasterbar.2.1.dylib"
OPENSSL_LIB="${HOMEBREW_PREFIX}/opt/openssl@4/lib"

if [ ! -f "$LIBTORRENT_LIB" ]; then
    echo "✗ libtorrent-rasterbar non trovata. Installa con: brew install libtorrent-rasterbar"
    exit 1
fi

echo "→ Compilazione ($CONFIG)…"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"

echo "→ Creazione del bundle…"
rm -rf "$APP_PATH"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources" "$FRAMEWORKS"

cp "$BIN_PATH" "$APP_BIN"
cp "Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"

if [ ! -f "Resources/AppIcon.icns" ]; then
    echo "→ Generazione dell'icona…"
    swift Scripts/make-icon.swift
fi

cp "Resources/AppIcon.icns" "${APP_PATH}/Contents/Resources/AppIcon.icns"

if [ -d "Resources/Licenses" ]; then
    cp -R "Resources/Licenses" "${APP_PATH}/Contents/Resources/Licenses"
fi

echo "→ Inclusione delle librerie…"
cp -L "$LIBTORRENT_LIB" "${FRAMEWORKS}/libtorrent-rasterbar.2.1.dylib"
cp -L "${OPENSSL_LIB}/libssl.4.dylib" "${FRAMEWORKS}/libssl.4.dylib"
cp -L "${OPENSSL_LIB}/libcrypto.4.dylib" "${FRAMEWORKS}/libcrypto.4.dylib"

# Make the bundle independent from the Homebrew prefix.
install_name_tool -id "@rpath/libtorrent-rasterbar.2.1.dylib" "${FRAMEWORKS}/libtorrent-rasterbar.2.1.dylib"
install_name_tool -id "@rpath/libssl.4.dylib" "${FRAMEWORKS}/libssl.4.dylib"
install_name_tool -id "@rpath/libcrypto.4.dylib" "${FRAMEWORKS}/libcrypto.4.dylib"

install_name_tool -change "${HOMEBREW_PREFIX}/opt/openssl@4/lib/libssl.4.dylib" "@loader_path/libssl.4.dylib" "${FRAMEWORKS}/libtorrent-rasterbar.2.1.dylib"
install_name_tool -change "${HOMEBREW_PREFIX}/opt/openssl@4/lib/libcrypto.4.dylib" "@loader_path/libcrypto.4.dylib" "${FRAMEWORKS}/libtorrent-rasterbar.2.1.dylib"

CRYPTO_REF=$(otool -L "${FRAMEWORKS}/libssl.4.dylib" | awk '/libcrypto\.4\.dylib/ {print $1; exit}')
if [ -n "${CRYPTO_REF:-}" ] && [ "$CRYPTO_REF" != "@loader_path/libcrypto.4.dylib" ]; then
    install_name_tool -change "$CRYPTO_REF" "@loader_path/libcrypto.4.dylib" "${FRAMEWORKS}/libssl.4.dylib"
fi

install_name_tool -change "${HOMEBREW_PREFIX}/opt/libtorrent-rasterbar/lib/libtorrent-rasterbar.2.1.dylib" "@executable_path/../Frameworks/libtorrent-rasterbar.2.1.dylib" "$APP_BIN"
install_name_tool -change "${HOMEBREW_PREFIX}/opt/openssl@4/lib/libssl.4.dylib" "@executable_path/../Frameworks/libssl.4.dylib" "$APP_BIN"
install_name_tool -change "${HOMEBREW_PREFIX}/opt/openssl@4/lib/libcrypto.4.dylib" "@executable_path/../Frameworks/libcrypto.4.dylib" "$APP_BIN"

echo "→ Firma ad-hoc…"
codesign --force --sign - "${FRAMEWORKS}/libtorrent-rasterbar.2.1.dylib" >/dev/null 2>&1 || true
codesign --force --sign - "${FRAMEWORKS}/libssl.4.dylib" >/dev/null 2>&1 || true
codesign --force --sign - "${FRAMEWORKS}/libcrypto.4.dylib" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || true

if otool -L "$APP_BIN" | grep -q "${HOMEBREW_PREFIX}"; then
    echo "✗ Il bundle contiene ancora riferimenti a Homebrew."
    exit 1
fi

echo "✓ App creata: $APP_PATH"
echo "  Avvio: open \"$APP_PATH\""
