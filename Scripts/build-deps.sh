#!/usr/bin/env bash
set -euo pipefail

# Build the exact libtorrent/OpenSSL/Boost versions used by Vertex.
#
# The result is installed in .build/vertex-deps (or VERTEX_DEPS_PREFIX) and is
# linked by Package.swift. The app bundle later copies the dylibs and rewrites
# every path, so the distributed app does not depend on Homebrew or on this
# build directory.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=Scripts/deps.env
source "$ROOT/Scripts/deps.env"
# shellcheck source=Scripts/toolchain.env
source "$ROOT/Scripts/toolchain.env"
# shellcheck source=Scripts/lib/macho.sh
source "$ROOT/Scripts/lib/macho.sh"

PREFIX="${VERTEX_DEPS_PREFIX:-$ROOT/.build/vertex-deps}"
SRC="${VERTEX_DEPS_SRC:-$ROOT/.build/vertex-deps-src}"
DOWNLOADS="${VERTEX_DEPS_DOWNLOADS:-$ROOT/.build/vertex-deps-downloads}"
TARGET="$VERTEX_DEPS_TARGET"
ARCH="$VERTEX_DEPS_ARCH"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
STAMP="$PREFIX/.vertex-deps-stamp"
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        -h|--help)
            echo "Uso: $0 [--force]"
            echo "  --force  ricostruisce le dipendenze anche se la stamp è valida"
            exit 0
            ;;
        *)
            echo "✗ Opzione sconosciuta: $arg" >&2
            exit 2
            ;;
    esac
done

if [ "${VERTEX_CANONICAL:-0}" = "1" ]; then
    "$ROOT/Scripts/check-toolchain.sh" --strict
else
    "$ROOT/Scripts/check-toolchain.sh" --warn
fi

# The cache stamp must include the actual compiler/build tools, not only the
# dependency versions: a cached dependency tree from a different CMake/Xcode
# must never be reused silently.
toolchain_fingerprint() {
    printf 'arch=%s\n' "$(uname -m)"
    printf 'macos=%s\n' "$(sw_vers -productVersion)"
    printf 'cmake=%s\n' "$({ cmake --version 2>/dev/null || true; } | awk 'NR==1 {print $3; exit}')"
    printf 'xcode=%s\n' "$({ xcodebuild -version 2>/dev/null || true; } | tr '\n' ' ')"
    printf 'swift=%s\n' "$({ swift --version 2>/dev/null || true; } | tr '\n' ' ')"
}
TOOLCHAIN_HASH="$(toolchain_fingerprint | shasum -a 256 | awk '{print $1}')"

if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ]; then
    CURRENT_STAMP="$(cat "$STAMP")"
    LOCK_HASH="$(shasum -a 256 "$ROOT/Scripts/deps.env" | awk '{print $1}')"
    SCRIPT_HASH="$(shasum -a 256 "$0" | awk '{print $1}')"
    EXPECTED_STAMP="lock=$LOCK_HASH script=$SCRIPT_HASH toolchain=$TOOLCHAIN_HASH target=$TARGET arch=$ARCH"
    if [ "$CURRENT_STAMP" = "$EXPECTED_STAMP" ] \
        && [ -n "$(find "$PREFIX/lib" -maxdepth 1 -name 'libtorrent-rasterbar*.dylib' -print -quit)" ] \
        && [ -f "$PREFIX/include/boost/version.hpp" ] \
        && [ -f "$PREFIX/include/openssl/ssl.h" ] \
        && [ -n "$(find "$PREFIX/lib" -maxdepth 1 -name 'libssl.*.dylib' -print -quit)" ] \
        && [ -n "$(find "$PREFIX/lib" -maxdepth 1 -name 'libcrypto.*.dylib' -print -quit)" ]; then
        echo "✓ Dipendenze già compilate: $PREFIX"
        exit 0
    fi
fi

for command in curl tar shasum lipo otool cmake make; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "✗ Comando richiesto non trovato: $command" >&2
        if [ "$command" = "cmake" ]; then
            echo "  Installa CMake con: brew install cmake" >&2
        fi
        exit 1
    fi
done

if [ "$ARCH" != "$(uname -m)" ]; then
    echo "✗ Questa configurazione compila per $ARCH, ma la macchina è $(uname -m)." >&2
    echo "  Per ora le dipendenze sono supportate solo per arm64 nativo." >&2
    exit 1
fi

echo "→ Dipendenze Vertex"
echo "  libtorrent: $LIBTORRENT_VERSION"
echo "  OpenSSL:    $OPENSSL_VERSION"
echo "  Boost:      $BOOST_VERSION (solo header)"
echo "  Target:     macOS $TARGET ($ARCH)"
echo "  Prefix:     $PREFIX"

rm -rf "$PREFIX" "$SRC"
mkdir -p "$PREFIX" "$SRC" "$DOWNLOADS"

fetch() {
    local url="$1"
    local file="$2"
    local expected="$3"
    local path="$DOWNLOADS/$file"

    if [ "$expected" = "__TO_BE_FILLED__" ]; then
        echo "✗ SHA-256 non configurato per $file in Scripts/deps.env" >&2
        exit 1
    fi

    if [ ! -f "$path" ]; then
        echo "→ Download $file"
        local part="${path}.part"
        rm -f "$part"
        if ! curl --fail --location --retry 3 --connect-timeout 20 --output "$part" "$url"; then
            rm -f "$part"
            exit 1
        fi
        mv "$part" "$path"
    fi

    local actual
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        rm -f "$path"
        echo "✗ Checksum non valido per $file" >&2
        echo "  atteso:  $expected" >&2
        echo "  ottenuto: $actual" >&2
        exit 1
    fi
}

archive_root() {
    tar -tf "$1" | head -n 1 | cut -d/ -f1
}

check_macho() {
    local file="$1"
    local minos archs
    minos="$(macho_minos "$file")"
    if [ -z "$minos" ]; then
        echo "✗ Impossibile determinare il minimum OS di $file" >&2
        exit 1
    fi
    if version_gt "$minos" "$TARGET"; then
        echo "✗ $file richiede macOS $minos, target $TARGET" >&2
        exit 1
    fi
    archs="$(lipo -archs "$file")"
    if [ "$archs" != "$ARCH" ]; then
        echo "✗ $file ha architettura '$archs', attesa '$ARCH'" >&2
        exit 1
    fi
    echo "  ✓ $(basename "$file") minos $minos, $archs"
}

# ---------------------------------------------------------------------------
# OpenSSL
# ---------------------------------------------------------------------------
OPENSSL_ARCHIVE="$DOWNLOADS/$(basename "$OPENSSL_URL")"
fetch "$OPENSSL_URL" "$(basename "$OPENSSL_URL")" "$OPENSSL_SHA256"
OPENSSL_SRC="$SRC/$(archive_root "$OPENSSL_ARCHIVE")"
tar -xf "$OPENSSL_ARCHIVE" -C "$SRC"

echo "→ Compilazione OpenSSL $OPENSSL_VERSION"
(
    cd "$OPENSSL_SRC"
    ./Configure darwin64-arm64-cc shared no-tests \
        --prefix="$PREFIX" \
        --openssldir="$PREFIX/ssl" \
        -mmacosx-version-min="$TARGET"
    make -j"$JOBS" build_sw
    make install_sw
)

SSL_LIB="$(find "$PREFIX/lib" -maxdepth 1 -name 'libssl.*.dylib' -print -quit)"
CRYPTO_LIB="$(find "$PREFIX/lib" -maxdepth 1 -name 'libcrypto.*.dylib' -print -quit)"
if [ -z "$SSL_LIB" ] || [ -z "$CRYPTO_LIB" ]; then
    echo "✗ OpenSSL non ha installato le dylib attese in $PREFIX/lib" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Boost headers
# ---------------------------------------------------------------------------
BOOST_ARCHIVE="$DOWNLOADS/$(basename "$BOOST_URL")"
fetch "$BOOST_URL" "$(basename "$BOOST_URL")" "$BOOST_SHA256"
BOOST_SRC="$SRC/$(archive_root "$BOOST_ARCHIVE")"
tar -xf "$BOOST_ARCHIVE" -C "$SRC"

echo "→ Installazione header Boost $BOOST_VERSION"
mkdir -p "$PREFIX/include"
rm -rf "$PREFIX/include/boost"
cp -R "$BOOST_SRC/boost" "$PREFIX/include/boost"

# ---------------------------------------------------------------------------
# libtorrent
# ---------------------------------------------------------------------------
LIBTORRENT_ARCHIVE="$DOWNLOADS/$(basename "$LIBTORRENT_URL")"
fetch "$LIBTORRENT_URL" "$(basename "$LIBTORRENT_URL")" "$LIBTORRENT_SHA256"
LIBTORRENT_SRC="$SRC/$(archive_root "$LIBTORRENT_ARCHIVE")"
LIBTORRENT_BUILD="$SRC/libtorrent-build"
tar -xf "$LIBTORRENT_ARCHIVE" -C "$SRC"

echo "→ Configurazione libtorrent $LIBTORRENT_VERSION"
cmake -S "$LIBTORRENT_SRC" -B "$LIBTORRENT_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_NAME_DIR="$PREFIX/lib" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_CXX_STANDARD=17 \
    -DBUILD_SHARED_LIBS=ON \
    -DOPENSSL_ROOT_DIR="$PREFIX" \
    -DOPENSSL_USE_STATIC_LIBS=OFF \
    -DBOOST_ROOT="$BOOST_SRC" \
    -DBoost_INCLUDE_DIR="$BOOST_SRC" \
    -DBoost_NO_SYSTEM_PATHS=ON \
    -Dbuild_tests=OFF \
    -Dbuild_examples=OFF \
    -Dbuild_tools=OFF \
    -Dpython-bindings=OFF

echo "→ Compilazione libtorrent $LIBTORRENT_VERSION"
cmake --build "$LIBTORRENT_BUILD" --parallel "$JOBS"
cmake --install "$LIBTORRENT_BUILD"

LIBTORRENT_LIB="$(find "$PREFIX/lib" -maxdepth 1 -name 'libtorrent-rasterbar*.dylib' -print -quit)"
if [ -z "$LIBTORRENT_LIB" ]; then
    echo "✗ libtorrent non ha installato la dylib attesa in $PREFIX/lib" >&2
    exit 1
fi

echo "→ Verifica minimum OS e dipendenze"
check_macho "$SSL_LIB"
check_macho "$CRYPTO_LIB"
check_macho "$LIBTORRENT_LIB"

for file in "$SSL_LIB" "$CRYPTO_LIB" "$LIBTORRENT_LIB"; do
    while IFS= read -r dependency; do
        [ -n "$dependency" ] || continue
        case "$dependency" in
            "$PREFIX"/*|@rpath/*|@loader_path/*|/usr/lib/*|/System/Library/*|/Library/Apple/*)
                ;;
            *)
                echo "✗ Dipendenza inattesa in $(basename "$file"): $dependency" >&2
                exit 1
                ;;
        esac
    done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')
done

LOCK_HASH="$(shasum -a 256 "$ROOT/Scripts/deps.env" | awk '{print $1}')"
SCRIPT_HASH="$(shasum -a 256 "$0" | awk '{print $1}')"
printf 'lock=%s script=%s toolchain=%s target=%s arch=%s\n' \
    "$LOCK_HASH" "$SCRIPT_HASH" "$TOOLCHAIN_HASH" "$TARGET" "$ARCH" > "$STAMP"

echo "✓ Dipendenze pronte in $PREFIX"
