#!/usr/bin/env bash
# Shared helpers to inspect Mach-O binaries. Sourced by build.sh,
# build-deps.sh and verify-bundle.sh so the checks cannot drift apart.

macho_dependencies() {
    otool -L "$1" | tail -n +2 | awk '
        /\(compatibility version / {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+\(compatibility version [^)]*\)$/, "", line)
            if (line != "") print line
        }
    '
}

macho_rpaths() {
    otool -l "$1" | awk '
        $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
        in_rpath && $1 == "path" {
            line = $0
            sub(/^[[:space:]]*path[[:space:]]+/, "", line)
            sub(/[[:space:]]+\(offset [0-9]+\)$/, "", line)
            if (line != "") print line
            in_rpath = 0
        }
    '
}

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
