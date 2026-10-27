#!/usr/bin/env bash
# Shared helpers to inspect Mach-O binaries. Sourced by build-deps.sh and
# verify-bundle.sh so the two checks cannot drift apart.

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
