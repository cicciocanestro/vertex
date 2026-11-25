#!/usr/bin/env bash
# Emits a CycloneDX 1.5 SBOM for the pinned engine dependencies.
#
# The versions and hashes come from Scripts/deps.env, the same file build-deps.sh
# verifies downloads against, so the SBOM cannot drift from the artifact.
#
# Usage: Scripts/generate-sbom.sh [output]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=Scripts/deps.env
source Scripts/deps.env
# shellcheck source=Scripts/geoip.env
source Scripts/geoip.env

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist)"
BUILD="$(plutil -extract CFBundleVersion raw -o - Resources/Info.plist)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OUT="${1:-$ROOT/dist/sbom.cdx.json}"
mkdir -p "$(dirname "$OUT")"

cat >"$OUT" <<EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "version": 1,
  "metadata": {
    "timestamp": "$TIMESTAMP",
    "tools": [{ "vendor": "Vertex", "name": "generate-sbom.sh", "version": "1" }],
    "component": {
      "type": "application",
      "name": "Vertex",
      "version": "$VERSION",
      "properties": [
        { "name": "vertex:build", "value": "$BUILD" },
        { "name": "vertex:commit", "value": "$COMMIT" },
        { "name": "vertex:minimum_macos", "value": "$VERTEX_MIN_MACOS" },
        { "name": "vertex:architecture", "value": "$VERTEX_ARCH" }
      ]
    }
  },
  "components": [
    {
      "type": "library",
      "name": "libtorrent-rasterbar",
      "version": "$LIBTORRENT_VERSION",
      "hashes": [{ "alg": "SHA-256", "content": "$LIBTORRENT_SHA256" }],
      "externalReferences": [{ "type": "distribution", "url": "$LIBTORRENT_URL" }]
    },
    {
      "type": "library",
      "name": "openssl",
      "version": "$OPENSSL_VERSION",
      "hashes": [{ "alg": "SHA-256", "content": "$OPENSSL_SHA256" }],
      "externalReferences": [{ "type": "distribution", "url": "$OPENSSL_URL" }]
    },
    {
      "type": "library",
      "name": "boost",
      "version": "$BOOST_VERSION",
      "hashes": [{ "alg": "SHA-256", "content": "$BOOST_SHA256" }],
      "externalReferences": [{ "type": "distribution", "url": "$BOOST_URL" }]
    },
    {
      "type": "data",
      "name": "dbip-country-lite",
      "version": "$GEOIP_VERSION",
      "licenses": [{ "license": { "id": "CC-BY-4.0" } }],
      "hashes": [{ "alg": "SHA-256", "content": "$GEOIP_SHA256" }],
      "externalReferences": [{ "type": "distribution", "url": "$GEOIP_URL" }]
    }
  ]
}
EOF

echo "✓ SBOM: $OUT"
