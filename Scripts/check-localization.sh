#!/usr/bin/env bash
set -euo pipefail

# Verify that the English and Italian Localizable.strings files expose the
# same keys, without duplicates. Missing translations otherwise fall back
# silently to the key itself.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT/Resources/en.lproj/Localizable.strings" \
          "$ROOT/Resources/it.lproj/Localizable.strings" <<'PY'
import re
import sys


def keys(path):
    text = open(path, encoding="utf-8").read()
    return re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*=', text, re.MULTILINE)


paths = sys.argv[1:3]
languages = ["en", "it"]
tables = {}
failed = False

for language, path in zip(languages, paths):
    try:
        parsed = keys(path)
    except OSError as error:
        print(f"✗ Impossibile leggere {path}: {error}", file=sys.stderr)
        sys.exit(1)
    duplicates = sorted({key for key in parsed if parsed.count(key) > 1})
    if duplicates:
        failed = True
        print(f"✗ Chiavi duplicate in {language}: {', '.join(duplicates)}", file=sys.stderr)
    tables[language] = set(parsed)
    print(f"  {language}: {len(tables[language])} chiavi")

only_en = sorted(tables["en"] - tables["it"])
only_it = sorted(tables["it"] - tables["en"])

if only_en:
    failed = True
    print("✗ Presenti solo in inglese:", ", ".join(only_en), file=sys.stderr)
if only_it:
    failed = True
    print("✗ Presenti solo in italiano:", ", ".join(only_it), file=sys.stderr)

if failed:
    sys.exit(1)

print(f"✓ Localizzazioni allineate ({len(tables['en'])} chiavi)")
PY
