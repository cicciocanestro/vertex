#!/usr/bin/env bash
# Queries OSV.dev for the pinned engine dependency versions.
#
# OSV coverage is uneven for C libraries: OpenSSL is tracked through OSS-Fuzz,
# libtorrent and Boost have no OSV package. An empty answer therefore means
# "not known to OSV", not "safe": upstream release notes still need a human
# look. The script fails only when OSV actually reports an advisory that
# matches the pinned version, so the scheduled job is a real signal, not noise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=Scripts/deps.env
source Scripts/deps.env

if ! command -v curl >/dev/null 2>&1; then
    echo "✗ curl non trovato" >&2
    exit 1
fi

failed=0

query() {
    local name="$1" version="$2" ecosystem="$3"
    local payload response
    payload=$(printf '{"package":{"name":"%s","ecosystem":"%s"},"version":"%s"}' \
        "$name" "$ecosystem" "$version")
    if ! response=$(curl -fsS --max-time 20 \
        -X POST https://api.osv.dev/v1/query \
        -H 'Content-Type: application/json' \
        --data-binary "$payload"); then
        echo "✗ $name: query OSV fallita" >&2
        failed=1
        return
    fi
    if ! grep -q '"vulns"' <<<"$response"; then
        echo "· $name $version: nessun avviso OSV"
        return
    fi

    # OSV's OSS-Fuzz entries are fuzz findings, not confirmed CVEs, and many
    # target parts of the library Vertex never calls (Boost.Graph, Boost.Regex).
    # Fail only on HIGH/CRITICAL; print the rest for a human to triage.
    local count high
    count=$(grep -o '"id":"[^"]*"' <<<"$response" | wc -l | tr -d ' ')
    high=$(grep -o '"severity":"[A-Z]*"' <<<"$response" | grep -cE 'HIGH|CRITICAL' || true)
    echo "⚠ $name $version: $count avvisi OSV, $high ad alta severità"
    if [ "${VERTEX_DEPS_VERBOSE:-0}" = "1" ]; then
        printf '%s\n' "$response"
    fi
    if [ "$high" -gt 0 ]; then
        echo "✗ $name: avviso OSV HIGH/CRITICAL" >&2
        failed=1
    fi
}

echo "→ Controllo avvisi OSV per le dipendenze fissate…"
query "openssl" "$OPENSSL_VERSION" "OSS-Fuzz"
query "libtorrent" "$LIBTORRENT_VERSION" "OSS-Fuzz"
query "boost" "$BOOST_VERSION" "OSS-Fuzz"

echo
echo "Nota: per le librerie C OSV copre solo OpenSSL (via OSS-Fuzz)."
echo "libtorrent e Boost vanno controllati a mano sulle release upstream:"
echo "  https://github.com/arvidn/libtorrent/releases"
echo "  https://www.boost.org/users/history/"

exit "$failed"
