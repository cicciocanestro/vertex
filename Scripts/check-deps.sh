#!/usr/bin/env bash
# Queries OSV.dev for the pinned engine dependency versions.
#
# OSV coverage is uneven for C/C++ libraries: OpenSSL and Boost are tracked
# through OSS-Fuzz (and tag-indexed advisories when present), whereas libtorrent
# has no OSV package. An empty answer therefore means "not known to OSV", not
# "safe": upstream release notes still need a human look. The script parses the
# OSV JSON schema properly (both ecosystem/database severity labels and numeric
# CVSS scores) and fails on HIGH/CRITICAL findings.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=Scripts/deps.env
source Scripts/deps.env

for cmd in curl python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "✗ $cmd non trovato" >&2
        exit 1
    fi
done

failed=0

TMP_RESP="$(mktemp "${TMPDIR:-/tmp}/vertex-osv.XXXXXX")"
trap 'rm -f "${TMP_RESP:?}"' EXIT

query() {
    local label="$1" payload="$2"
    local summary status
    if ! curl -fsS --max-time 20 \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        -X POST https://api.osv.dev/v1/query \
        -H 'Content-Type: application/json' \
        --data-binary "$payload" \
        -o "$TMP_RESP"; then
        echo "✗ $label: query OSV fallita" >&2
        failed=1
        return
    fi

    status=0
    summary=$(python3 - "$label" "${VERTEX_DEPS_VERBOSE:-0}" "$TMP_RESP" <<'PY'
import json
import sys

label = sys.argv[1]
verbose = sys.argv[2] == "1"
with open(sys.argv[3], "r", encoding="utf-8") as fh:
    raw = fh.read()
doc = json.loads(raw or "{}")
vulns = doc.get("vulns") or []
if not vulns:
    print(f"· {label}: nessun avviso OSV")
    sys.exit(0)

def is_high_or_critical(v):
    labels = []
    for container in (v.get("database_specific") or {}, v.get("ecosystem_specific") or {}):
        sev = container.get("severity")
        if isinstance(sev, str):
            labels.append(sev.upper())
    for affected in v.get("affected") or []:
        for key in ("database_specific", "ecosystem_specific"):
            sev = (affected.get(key) or {}).get("severity")
            if isinstance(sev, str):
                labels.append(sev.upper())
    if any(s in ("HIGH", "CRITICAL") for s in labels):
        return True
    for item in v.get("severity") or []:
        score_str = str(item.get("score") or "")
        try:
            if float(score_str) >= 7.0:
                return True
        except ValueError:
            pass
        # CVSS v3/v4 vector without precomputed numeric score: flag high impact
        # on confidentiality/integrity/availability over network as high risk.
        if score_str.startswith("CVSS:") and "/AV:N/" in score_str:
            if any(h in score_str for h in ("/C:H", "/I:H", "/A:H", "/VC:H", "/VI:H", "/VA:H")):
                return True
    return False

high = sum(1 for v in vulns if is_high_or_critical(v))
print(f"⚠ {label}: {len(vulns)} avvisi OSV, {high} ad alta severità")
if verbose:
    print(raw)
sys.exit(2 if high > 0 else 0)
PY
    ) || status=$?

    printf '%s\n' "$summary"
    if [ "$status" -eq 2 ]; then
        echo "✗ $label: avviso OSV HIGH/CRITICAL" >&2
        failed=1
    elif [ "$status" -ne 0 ]; then
        echo "✗ $label: analisi risposta OSV fallita" >&2
        failed=1
    fi
}

echo "→ Controllo avvisi OSV per le dipendenze fissate…"
query "openssl $OPENSSL_VERSION (OSS-Fuzz)" \
    "$(printf '{"package":{"name":"openssl","ecosystem":"OSS-Fuzz"},"version":"%s"}' "$OPENSSL_VERSION")"
query "openssl openssl-$OPENSSL_VERSION (generic)" \
    "$(printf '{"package":{"purl":"pkg:generic/openssl"},"version":"openssl-%s"}' "$OPENSSL_VERSION")"
query "libtorrent $LIBTORRENT_VERSION" \
    "$(printf '{"package":{"name":"libtorrent","ecosystem":"OSS-Fuzz"},"version":"%s"}' "$LIBTORRENT_VERSION")"
query "boost $BOOST_VERSION" \
    "$(printf '{"package":{"name":"boost","ecosystem":"OSS-Fuzz"},"version":"boost-%s"}' "$BOOST_VERSION")"

echo
echo "Nota: OSV traccia OpenSSL e Boost tramite OSS-Fuzz, ma gli avvisi di sicurezza"
echo "ufficiali di OpenSSL, libtorrent e Boost vanno verificati sulle release upstream:"
echo "  https://openssl-library.org/news/vulnerabilities/"
echo "  https://github.com/arvidn/libtorrent/releases"
echo "  https://www.boost.org/users/history/"

exit "$failed"
