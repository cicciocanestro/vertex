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
CLEANED_UP=0
cleanup() {
    if [ "$CLEANED_UP" -eq 1 ]; then
        return 0
    fi
    CLEANED_UP=1
    rm -f "${TMP_RESP:-}"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

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
import math
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


def cvss3_roundup(value):
    int_input = int(round(value * 100000))
    if (int_input % 10000) == 0:
        return int_input / 100000.0
    return (math.floor(int_input / 10000) + 1) / 10.0


def cvss3_base_score(vector):
    """Compute exact FIRST.org CVSS v3.0 / v3.1 Base Score, or None if invalid."""
    if not (vector.startswith("CVSS:3.0/") or vector.startswith("CVSS:3.1/")):
        return None
    metrics = {}
    for token in vector.split("/")[1:]:
        if ":" not in token:
            return None
        key, val = token.split(":", 1)
        metrics[key] = val

    av_map = {"N": 0.85, "A": 0.62, "L": 0.55, "P": 0.20}
    ac_map = {"L": 0.77, "H": 0.44}
    ui_map = {"N": 0.85, "R": 0.62}
    cia_map = {"H": 0.56, "L": 0.22, "N": 0.0}
    scope = metrics.get("S")
    if scope not in ("U", "C"):
        return None
    pr_map = (
        {"N": 0.85, "L": 0.62, "H": 0.27}
        if scope == "U"
        else {"N": 0.85, "L": 0.68, "H": 0.50}
    )

    try:
        av = av_map[metrics["AV"]]
        ac = ac_map[metrics["AC"]]
        pr = pr_map[metrics["PR"]]
        ui = ui_map[metrics["UI"]]
        c = cia_map[metrics["C"]]
        i = cia_map[metrics["I"]]
        a = cia_map[metrics["A"]]
    except KeyError:
        return None

    iss = 1.0 - ((1.0 - c) * (1.0 - i) * (1.0 - a))
    if iss <= 0.0:
        return 0.0
    if scope == "U":
        impact = 6.42 * iss
    else:
        impact = 7.52 * (iss - 0.029) - 3.25 * ((iss - 0.02) ** 15)
    exploitability = 8.22 * av * ac * pr * ui
    if scope == "U":
        return cvss3_roundup(min(impact + exploitability, 10.0))
    return cvss3_roundup(min(1.08 * (impact + exploitability), 10.0))


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
        score_str = str(item.get("score") or "").strip()
        try:
            if float(score_str) >= 7.0:
                return True
            continue
        except ValueError:
            pass
        v3_score = cvss3_base_score(score_str)
        if v3_score is not None:
            if v3_score >= 7.0:
                return True
            continue
        # Conservative fallback for CVSS v4.0 (or unparsed CVSS vectors):
        # treat any high impact on vulnerable/subsequent system as high risk.
        if score_str.startswith("CVSS:"):
            if any(
                h in score_str
                for h in ("/VC:H", "/VI:H", "/VA:H", "/SC:H", "/SI:H", "/SA:H", "/C:H", "/I:H", "/A:H")
            ):
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
query "openssl openssl-$OPENSSL_VERSION (OSS-Fuzz tag)" \
    "$(printf '{"package":{"name":"openssl","ecosystem":"OSS-Fuzz"},"version":"openssl-%s"}' "$OPENSSL_VERSION")"
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
