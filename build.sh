#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"

# shellcheck source=Scripts/app.env
source "$ROOT/Scripts/app.env"

CONFIG="release"
REBUILD_DEPS=0

for arg in "$@"; do
    case "$arg" in
        release|debug|test)
            CONFIG="$arg"
            ;;
        --rebuild-deps)
            REBUILD_DEPS=1
            ;;
        -h|--help)
            echo "Uso: $0 [release|debug|test] [--rebuild-deps]"
            exit 0
            ;;
        *)
            echo "✗ Opzione sconosciuta: $arg" >&2
            exit 2
            ;;
    esac
done

# Keep Package.swift and the bundle script on the same dependency prefix.
if [ -z "${VERTEX_DEPS_PREFIX:-}" ]; then
    VERTEX_DEPS_PREFIX="$ROOT/.build/vertex-deps"
else
    case "$VERTEX_DEPS_PREFIX" in
        /*) ;;
        *) VERTEX_DEPS_PREFIX="$ROOT/$VERTEX_DEPS_PREFIX" ;;
    esac
fi
export VERTEX_DEPS_PREFIX
DEPS_PREFIX="$VERTEX_DEPS_PREFIX"

APP_NAME="$VERTEX_APP_NAME"
APP_PATH="dist/${APP_NAME}.app"
APP_BIN="${APP_PATH}/Contents/MacOS/${APP_NAME}"
FRAMEWORKS="${APP_PATH}/Contents/Frameworks"
TARGET_MIN=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)

if [ "$REBUILD_DEPS" -eq 1 ]; then
    "$ROOT/Scripts/build-deps.sh" --force
else
    "$ROOT/Scripts/build-deps.sh"
fi

if [ "$CONFIG" = "test" ]; then
    exec "$ROOT/Scripts/run-tests.sh"
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

for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "${APP_PATH}/Contents/Resources/"
done

# Copy the complete transitive closure of engine dylibs. This intentionally
# does not hard-code libssl/libcrypto/libtorrent versions: the versions come
# from Scripts/deps.env and are discovered from the actual Mach-O dependencies.
echo "→ Inclusione delle librerie…"
copy_dylib_closure() {
    local -a queue=("$APP_BIN")
    local copied=" "
    local current dependency candidate base

    while [ "${#queue[@]}" -gt 0 ]; do
        current="${queue[0]}"
        queue=("${queue[@]:1}")

        while IFS= read -r dependency; do
            [ -n "$dependency" ] || continue

            case "$dependency" in
                "$DEPS_PREFIX"/*)
                    ;;
                @rpath/*|@loader_path/*)
                    candidate="$DEPS_PREFIX/lib/$(basename "$dependency")"
                    [ -f "$candidate" ] || continue
                    dependency="$candidate"
                    ;;
                *)
                    continue
                    ;;
            esac

            base="$(basename "$dependency")"
            case "$copied" in
                *" $base "*)
                    continue
                    ;;
            esac

            cp -L "$dependency" "${FRAMEWORKS}/${base}"
            copied="${copied}${base} "
            queue+=("${FRAMEWORKS}/${base}")
        done < <(otool -L "$current" | tail -n +2 | awk '{print $1}')
    done
}

remove_rpaths() {
    local file="$1"
    local rpath

    while IFS= read -r rpath; do
        [ -n "$rpath" ] || continue
        case "$rpath" in
            /usr/lib/swift)
                continue
                ;;
        esac
        install_name_tool -delete_rpath "$rpath" "$file" 2>/dev/null || true
    done < <(otool -l "$file" | awk '/LC_RPATH/{found=1} found && /path/{print $2; found=0}')
}

rewrite_dependencies() {
    local file="$1"
    local prefix="$2"
    local dependency base

    while IFS= read -r dependency; do
        [ -n "$dependency" ] || continue
        case "$dependency" in
            "$DEPS_PREFIX"/*)
                base="$(basename "$dependency")"
                install_name_tool -change "$dependency" "${prefix}/${base}" "$file"
                ;;
            @rpath/*)
                base="$(basename "$dependency")"
                if [ -f "${FRAMEWORKS}/${base}" ]; then
                    install_name_tool -change "$dependency" "${prefix}/${base}" "$file"
                fi
                ;;
        esac
    done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')
}

copy_dylib_closure

for dylib in "${FRAMEWORKS}"/*.dylib; do
    [ -e "$dylib" ] || continue
    base="$(basename "$dylib")"
    install_name_tool -id "@loader_path/${base}" "$dylib"
    rewrite_dependencies "$dylib" "@loader_path"
    remove_rpaths "$dylib"
done

rewrite_dependencies "$APP_BIN" "@executable_path/../Frameworks"
remove_rpaths "$APP_BIN"

echo "→ Firma ad-hoc…"
for dylib in "${FRAMEWORKS}"/*.dylib; do
    [ -e "$dylib" ] || continue
    codesign --force --sign - "$dylib" >/dev/null
done
codesign --force --sign - "$APP_PATH" >/dev/null
codesign --verify --deep --strict "$APP_PATH"

echo "→ Verifica bundle autosufficiente…"
"$ROOT/Scripts/verify-bundle.sh" "$APP_PATH" "$TARGET_MIN"

echo "✓ App creata: $APP_PATH"
echo "  Avvio: open \"$APP_PATH\""
