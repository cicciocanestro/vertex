#!/usr/bin/env bash
set -euo pipefail

# Smoke test for the built bundle. Two checks:
#   1. a hardened-runtime signature without a Team ID will fail library
#      validation when dyld loads the bundled libtorrent;
#   2. the executable must stay alive for five seconds and must not log dyld
#      errors.
# The second check is the one that would have caught 1.17.7 and 1.17.8.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/Scripts/app.env"

APP="${1:-$ROOT/dist/${VERTEX_APP_NAME}.app}"
BIN="$APP/Contents/MacOS/${VERTEX_APP_NAME}"

if [ ! -x "$BIN" ]; then
    echo "✗ Eseguibile assente: $BIN" >&2
    exit 1
fi

SIGNATURE="$(codesign -dvv "$APP" 2>&1 || true)"
if grep -q "flags=.*runtime" <<<"$SIGNATURE" && grep -q "TeamIdentifier=not set" <<<"$SIGNATURE"; then
    echo "✗ Hardened runtime senza Team ID: le dylib incluse falliranno la library validation" >&2
    exit 1
fi

LOG="$(mktemp -t vertex-launch)"
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/vertex-launch-home.XXXXXX")"
DEFAULTS_SUITE="app.vertex.torrent.check-launch.$$"
PID=""
CLEANED_UP=0
cleanup() {
    if [ "$CLEANED_UP" -eq 1 ]; then
        return 0
    fi
    CLEANED_UP=1
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        for _ in $(seq 1 8); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.25
        done
        kill -9 "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    defaults delete "$DEFAULTS_SUITE" >/dev/null 2>&1 || true
    rm -rf "$LOG" "$FAKE_HOME"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Isolate data/download directories, UserDefaults suite and Keychain/notifications
# so running the smoke test locally never touches the user's real resume folder,
# Downloads folder, preferences or login Keychain (macOS FileManager ignores $HOME).
HOME="$FAKE_HOME" \
VERTEX_DATA_DIR="$FAKE_HOME/Application Support/Vertex" \
VERTEX_DOWNLOADS_DIR="$FAKE_HOME/Downloads" \
VERTEX_DEFAULTS_SUITE="$DEFAULTS_SUITE" \
VERTEX_KEYCHAIN_DISABLED=1 \
VERTEX_NOTIFICATIONS_DISABLED=1 \
"$BIN" >"$LOG" 2>&1 &
PID=$!

for _ in $(seq 1 20); do
    sleep 0.25
    if ! kill -0 "$PID" 2>/dev/null; then
        STATUS=0
        wait "$PID" || STATUS=$?
        PID=""
        echo "✗ L'app è uscita durante l'avvio (status $STATUS)" >&2
        sed -n '1,40p' "$LOG" >&2
        exit 1
    fi
done

if grep -Eq "Library not loaded|different Team IDs|code signature invalid|dyld:" "$LOG"; then
    echo "✗ Errori dyld nel log di avvio:" >&2
    grep -E "Library not loaded|different Team IDs|code signature invalid|dyld:" "$LOG" >&2
    exit 1
fi

echo "✓ L'app resta in esecuzione dopo 5 s"
