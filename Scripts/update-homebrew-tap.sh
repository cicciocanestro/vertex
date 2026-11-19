#!/usr/bin/env bash
set -euo pipefail

# Updates the official Homebrew Tap (cicciocanestro/homebrew-tap) with the
# version and SHA-256 of a published Vertex GitHub Release.
#
# Usage:
#   ./Scripts/update-homebrew-tap.sh [v1.14.0]
#
# When no tag is passed, reads CFBundleShortVersionString from Resources/Info.plist.
# Can be run locally after a release (uses `gh` credentials) or from CI when
# HOMEBREW_TAP_TOKEN is configured.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=Scripts/app.env
source "$ROOT/Scripts/app.env"

TAG="${1:-}"
if [ -z "$TAG" ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
    TAG="v${VERSION}"
else
    VERSION="${TAG#v}"
fi

TAP_REPO="${VERTEX_TAP_REPO:-cicciocanestro/homebrew-tap}"
DMG_NAME="${VERTEX_APP_NAME}-${VERSION}-macOS${VERTEX_MIN_MACOS}-${VERTEX_ARCH}.dmg"
SHA_FILE="${DMG_NAME}.sha256"

TMP_DIR="$(mktemp -d /tmp/vertex-tap-update.XXXXXX)"
cleanup() {
    rm -rf "${TMP_DIR:?}"
}
trap cleanup EXIT

echo "→ Recupero checksum canonico per ${TAG} (${DMG_NAME})…"
if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ -f "dist/${SHA_FILE}" ]; then
    SHA256="$(awk '{print $1}' "dist/${SHA_FILE}")"
else
    gh release download "$TAG" --repo "cicciocanestro/vertex" --pattern "$SHA_FILE" --dir "$TMP_DIR"
    SHA256="$(awk '{print $1}' "$TMP_DIR/$SHA_FILE")"
fi

if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "✗ SHA-256 non valido: ${SHA256:-vuoto}" >&2
    exit 1
fi

echo "  Versione: ${VERSION}"
echo "  SHA-256:  ${SHA256}"

TAP_CLONE="$TMP_DIR/homebrew-tap"
if [ -n "${HOMEBREW_TAP_TOKEN:-}" ]; then
    git clone "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP_REPO}.git" "$TAP_CLONE"
else
    gh repo clone "$TAP_REPO" "$TAP_CLONE"
fi

mkdir -p "$TAP_CLONE/Casks"
cat > "$TAP_CLONE/Casks/vertex.rb" <<RUBY
cask "vertex" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/cicciocanestro/vertex/releases/download/v#{version}/Vertex-#{version}-macOS${VERTEX_MIN_MACOS}-${VERTEX_ARCH}.dmg"
  name "Vertex"
  desc "Native BitTorrent client built with SwiftUI and libtorrent"
  homepage "https://github.com/cicciocanestro/vertex"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :${VERTEX_ARCH}
  depends_on macos: :sequoia

  app "Vertex.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "Vertex.app"],
        base: :appdir
  end

  zap trash: [
    "~/Library/Application Support/Vertex",
    "~/Library/Preferences/app.vertex.torrent.plist",
    "~/Library/Saved Application State/app.vertex.torrent.savedState",
  ]
end
RUBY

if git -C "$TAP_CLONE" diff --quiet -- Casks/vertex.rb; then
    echo "✓ ${TAP_REPO} è già aggiornato a Vertex ${VERSION}."
    exit 0
fi

git -C "$TAP_CLONE" add Casks/vertex.rb
git -C "$TAP_CLONE" commit -m "vertex ${VERSION}"
git -C "$TAP_CLONE" push origin main

echo "✓ Tap Homebrew aggiornato: ${TAP_REPO} (vertex ${VERSION})"
