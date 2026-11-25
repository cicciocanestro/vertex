#!/usr/bin/env bash
set -euo pipefail

# Generates a self-signed code-signing certificate and a .p12 bundle for CI.
#
# Why: ad-hoc signatures change on every build, so macOS treats each rebuild as
# a different application and re-prompts for the Keychain item holding the
# SOCKS5 password. A self-signed identity is stable across builds, which keeps
# the designated requirement (and the Keychain access) valid. Gatekeeper still
# warns because the certificate is not trusted by Apple.
#
# This does NOT replace notarization: that requires an Apple Developer account.
#
# Usage:
#   VERTEX_SIGN_P12_PASSWORD='<password>' ./Scripts/make-signing-cert.sh
#
# Outputs (in the current directory):
#   vertex-signing.p12          the PKCS#12 bundle to keep private
#   vertex-signing.p12.base64   paste this into the VERTEX_SIGN_P12 secret
#
# Secrets to create in the repository:
#   VERTEX_SIGN_P12           base64 of vertex-signing.p12
#   VERTEX_SIGN_P12_PASSWORD  the password above
#   VERTEX_SIGN_IDENTITY      "Vertex Self-Signed" (or the CN you choose)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CN="${VERTEX_SIGN_CERT_CN:-Vertex Self-Signed}"
OUT="${VERTEX_SIGN_P12_OUT:-vertex-signing.p12}"
PASSWORD="${VERTEX_SIGN_P12_PASSWORD:-}"

if [ -z "$PASSWORD" ]; then
    PASSWORD="$(openssl rand -base64 24)"
    echo "· Password generata (salvala nel secret VERTEX_SIGN_P12_PASSWORD):"
    echo "  $PASSWORD"
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "✗ openssl non trovato" >&2
    exit 1
fi

umask 077
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vertex-cert.XXXXXX")"
cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CN
O = Vertex
C = IT
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "→ Generazione del certificato self-signed (10 anni)…"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -config "$WORK/openssl.cnf"

echo "→ Creazione del bundle PKCS#12…"
# macOS `security import` rejects the PBES2/AES defaults of OpenSSL 3/4 with
# "MAC verification failed": use the 3DES + SHA-1 combination it understands.
# If the local openssl does not support these flags, fall back to its defaults
# (LibreSSL already produces the legacy format).
P12_ARGS=(-certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1)
if ! VERTEX_EXPORT_PW="$PASSWORD" openssl pkcs12 -export \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$CN" -out "$OUT" -passout env:VERTEX_EXPORT_PW \
    "${P12_ARGS[@]}" 2>/dev/null; then
    VERTEX_EXPORT_PW="$PASSWORD" openssl pkcs12 -export \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -name "$CN" -out "$OUT" -passout env:VERTEX_EXPORT_PW
fi

# Single-line base64: a secret pasted with line breaks is the classic way this
# step fails in CI.
base64 < "$OUT" | tr -d '\n' > "$OUT.base64"

echo "✓ Certificato creato: $OUT"
echo "  Identità:  $CN"
echo "  Secret:    VERTEX_SIGN_P12=$(pwd)/$OUT.base64"
echo "  Password:  VERTEX_SIGN_P12_PASSWORD"
echo
echo "  Nel workflow, con questi secret impostati, build.sh firma il bundle con"
echo "  questa identità stabile. Gatekeeper continuerà a mostrare l'avviso:"
echo "  per distribuirlo senza avvisi serve un certificato Developer ID."
