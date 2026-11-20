#!/usr/bin/env bash
set -euo pipefail

# Regenerates Resources/GeoIP/country-v4.bin.z from the pinned DB-IP Lite CSV.
# The generated table is committed: run this only when refreshing the dataset.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=Scripts/geoip.env
source "$ROOT/Scripts/geoip.env"

DOWNLOADS="${VERTEX_GEOIP_DOWNLOADS:-$ROOT/.build/geoip-downloads}"
ARCHIVE="$DOWNLOADS/dbip-country-lite-${GEOIP_VERSION}.csv.gz"

if ! command -v python3 >/dev/null 2>&1; then
    echo "✗ python3 non trovato (serve per l'encoder)" >&2
    exit 1
fi

mkdir -p "$DOWNLOADS" "$(dirname "$GEOIP_OUTPUT")"

if [ ! -f "$ARCHIVE" ]; then
    echo "→ Download DB-IP Lite $GEOIP_VERSION"
    part="${ARCHIVE}.part"
    rm -f "$part"
    if ! curl --fail --location \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --retry 3 --connect-timeout 20 \
        --output "$part" "$GEOIP_URL"; then
        rm -f "$part"
        echo "✗ Download fallito: $GEOIP_URL" >&2
        exit 1
    fi
    mv "$part" "$ARCHIVE"
fi

actual="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [ "$actual" != "$GEOIP_SHA256" ]; then
    rm -f "$ARCHIVE"
    echo "✗ Checksum non valido per dbip-country-lite-${GEOIP_VERSION}.csv.gz" >&2
    echo "  atteso:   $GEOIP_SHA256" >&2
    echo "  ottenuto: $actual" >&2
    exit 1
fi

CSV="$DOWNLOADS/dbip-country-lite-${GEOIP_VERSION}.csv"
gzip -dc "$ARCHIVE" > "$CSV"

echo "→ Codifica tabella paesi"
python3 "$ROOT/Scripts/geoip-encode.py" "$CSV" "$GEOIP_OUTPUT"

echo "✓ Tabella pronta: $GEOIP_OUTPUT ($(du -h "$GEOIP_OUTPUT" | awk '{print $1}'))"
