#!/usr/bin/env bash
set -euo pipefail

# Verify that a Vertex.app bundle is self-contained and honest about its
# minimum macOS version.
#
# Usage:
#   Scripts/verify-bundle.sh [APP] [EXPECTED_MIN] [EXPECTED_ARCH]
#
# Examples:
#   Scripts/verify-bundle.sh dist/Vertex.app 15.0 arm64
#   Scripts/verify-bundle.sh dist/Vertex.app
#
# It fails if:
#   - the executable or a bundled dylib requires a newer macOS than Info.plist;
#   - there are dependencies outside the bundle/System (for example Homebrew);
#   - a bundled @executable_path/@loader_path dependency is missing;
#   - there are non-system LC_RPATH entries;
#   - the architectures are inconsistent;
#   - the ad-hoc signature is invalid.

APP="${1:-dist/Vertex.app}"
EXPECTED_MIN="${2:-}"
EXPECTED_ARCH="${3:-}"
INFO="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/Vertex"

if [ ! -d "$APP" ]; then
    echo "✗ Bundle non trovato: $APP" >&2
    exit 1
fi
if [ ! -f "$INFO" ] || [ ! -f "$BIN" ]; then
    echo "✗ Bundle incompleto: $APP" >&2
    exit 1
fi

DECLARED_MIN="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO")"
if [ -z "$DECLARED_MIN" ]; then
    echo "✗ LSMinimumSystemVersion mancante in $INFO" >&2
    exit 1
fi

if [ -n "$EXPECTED_MIN" ] && [ "$DECLARED_MIN" != "$EXPECTED_MIN" ]; then
    echo "✗ Info.plist dichiara macOS $DECLARED_MIN, atteso $EXPECTED_MIN" >&2
    exit 1
fi

macho_minos() {
    local minos
    minos="$(otool -l "$1" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')"
    if [ -z "$minos" ]; then
        minos="$(otool -l "$1" | awk '/LC_VERSION_MIN_MACOSX/{found=1} found && /version/{print $2; exit}')"
    fi
    printf '%s' "$minos"
}

version_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        split(a, x, "."); split(b, y, ".");
        for (i = 1; i <= 3; i++) {
            if ((x[i] + 0) > (y[i] + 0)) exit 0;
            if ((x[i] + 0) < (y[i] + 0)) exit 1;
        }
        exit 1;
    }'
}

MACHOS=()
while IFS= read -r -d '' file; do
    if file -b "$file" 2>/dev/null | grep -q 'Mach-O'; then
        MACHOS+=("$file")
    fi
done < <(find "$APP/Contents" -type f -print0)

if [ "${#MACHOS[@]}" -eq 0 ]; then
    echo "✗ Nessun file Mach-O trovato in $APP" >&2
    exit 1
fi

MAX_MINOS="0.0"
BUNDLE_ARCHS=""

for file in "${MACHOS[@]}"; do
    rel="${file#"$APP"/}"

    minos="$(macho_minos "$file")"
    if [ -z "$minos" ]; then
        echo "✗ Minimum OS non rilevabile: $rel" >&2
        exit 1
    fi
    if version_gt "$minos" "$MAX_MINOS"; then
        MAX_MINOS="$minos"
    fi

    archs="$(lipo -archs "$file" 2>/dev/null || true)"
    if [ -z "$archs" ]; then
        echo "✗ Architettura non rilevabile: $rel" >&2
        exit 1
    fi
    if [ -z "$BUNDLE_ARCHS" ]; then
        BUNDLE_ARCHS="$archs"
    elif [ "$archs" != "$BUNDLE_ARCHS" ]; then
        echo "✗ Architetture incoerenti: $rel ha '$archs', il bundle ha '$BUNDLE_ARCHS'" >&2
        exit 1
    fi

    while IFS= read -r dependency; do
        [ -n "$dependency" ] || continue
        case "$dependency" in
            @executable_path/*)
                dependency_path="${dependency/@executable_path/$(dirname "$BIN")}"
                if [ ! -f "$dependency_path" ]; then
                    echo "✗ Dipendenza inclusa mancante in $rel: $dependency" >&2
                    exit 1
                fi
                ;;
            @loader_path/*)
                dependency_path="${dependency/@loader_path/$(dirname "$file")}"
                if [ ! -f "$dependency_path" ]; then
                    echo "✗ Dipendenza inclusa mancante in $rel: $dependency" >&2
                    exit 1
                fi
                ;;
            /usr/lib/*|/System/Library/*|/Library/Apple/*)
                ;;
            *)
                echo "✗ Dipendenza esterna in $rel: $dependency" >&2
                exit 1
                ;;
        esac
    done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')

    while IFS= read -r rpath; do
        [ -n "$rpath" ] || continue
        case "$rpath" in
            /usr/lib/swift)
                continue
                ;;
        esac
        echo "✗ LC_RPATH non ammesso in $rel: $rpath" >&2
        exit 1
    done < <(otool -l "$file" | awk '/LC_RPATH/{found=1} found && /path/{print $2; found=0}')
done

if version_gt "$MAX_MINOS" "$DECLARED_MIN"; then
    echo "✗ Il bundle richiede macOS $MAX_MINOS ma Info.plist dichiara $DECLARED_MIN" >&2
    exit 1
fi

if [ -n "$EXPECTED_ARCH" ] && [ "$BUNDLE_ARCHS" != "$EXPECTED_ARCH" ]; then
    echo "✗ Architettura del bundle '$BUNDLE_ARCHS', attesa '$EXPECTED_ARCH'" >&2
    exit 1
fi

if ! codesign --verify --deep --strict "$APP"; then
    echo "✗ Firma non valida per $APP" >&2
    exit 1
fi

echo "✓ Bundle verificato: $APP"
echo "  macOS minimo dichiarato: $DECLARED_MIN"
echo "  macOS minimo dei binari: $MAX_MINOS"
echo "  Architettura:            $BUNDLE_ARCHS"
