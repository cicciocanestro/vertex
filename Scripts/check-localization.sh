#!/usr/bin/env bash
set -euo pipefail

# Verify the localization tables.
#
# 1. English and Italian expose the same keys, without duplicates. A key missing
#    from one of the two files would silently fall back to the key itself.
# 2. Every key used by the Swift sources exists in the tables. The scan covers
#    the runtime lookups (`L(...)`, `LF(...)`) and the SwiftUI / component
#    literals that are localized on purpose, so a new user-facing string cannot
#    reach a release untranslated.
#
# `Text(verbatim:)` and friends are ignored: verbatim strings are not keys.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import os
import re
import sys

root = sys.argv[1]
en_path = os.path.join(root, "Resources/en.lproj/Localizable.strings")
it_path = os.path.join(root, "Resources/it.lproj/Localizable.strings")
sources = os.path.join(root, "Sources")

ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=', re.MULTILINE)

# Patterns that always produce a localization lookup at runtime.
KEY_CALLS = re.compile(
    r'\b(?:L|LF)\(\s*"((?:[^"\\]|\\.)*)"'          # L("...") / LF("...")
    r'|\b(?:Text|Button|Label|Toggle|SecureField|TextField|Menu|SectionLabel)'
    r'\(\s*"((?:[^"\\]|\\.)*)"'                     # Text("..."), Button("..."), ...
    r'|\b(?:text|title|subtitle|help):\s*"((?:[^"\\]|\\.)*)"'  # component parameters
)

failed = False


def read_table(path, language):
    global failed
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as error:
        print(f"✗ Impossibile leggere {path}: {error}", file=sys.stderr)
        sys.exit(1)

    parsed = ENTRY.findall(text)
    duplicates = sorted({key for key in parsed if parsed.count(key) > 1})
    if duplicates:
        failed = True
        print(f"✗ Chiavi duplicate in {language}: {', '.join(duplicates)}", file=sys.stderr)
    print(f"  {language}: {len(set(parsed))} chiavi")
    return set(parsed)


tables = {
    "en": read_table(en_path, "en"),
    "it": read_table(it_path, "it"),
}

only_en = sorted(tables["en"] - tables["it"])
only_it = sorted(tables["it"] - tables["en"])
if only_en:
    failed = True
    print("✗ Presenti solo in inglese:", ", ".join(only_en), file=sys.stderr)
if only_it:
    failed = True
    print("✗ Presenti solo in italiano:", ", ".join(only_it), file=sys.stderr)

def strip_comments(text):
    """Remove // and /* */ comments while keeping string literals intact.

    Doc comments contain example calls such as Text("..."), which are not keys.
    A plain regex would either keep them or destroy URLs inside string literals.
    """
    out = []
    i = 0
    n = len(text)
    in_string = False
    in_line_comment = False
    in_block_comment = False
    while i < n:
        c = text[i]
        pair = text[i:i + 2]
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
                out.append(c)
            i += 1
            continue
        if in_block_comment:
            if pair == "*/":
                in_block_comment = False
                i += 2
                continue
            if c == "\n":
                out.append(c)
            i += 1
            continue
        if in_string:
            out.append(c)
            if c == "\\":
                if i + 1 < n:
                    out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if pair == "//":
            in_line_comment = True
            i += 2
            continue
        if pair == "/*":
            in_block_comment = True
            i += 2
            continue
        if c == '"':
            in_string = True
            out.append(c)
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


used = {}
for directory, _, files in os.walk(sources):
    for name in files:
        if not name.endswith(".swift"):
            continue
        path = os.path.join(directory, name)
        text = strip_comments(open(path, encoding="utf-8").read())
        for match in KEY_CALLS.finditer(text):
            key = next(group for group in match.groups() if group is not None)
            if key:
                used.setdefault(key, set()).add(os.path.basename(path))

missing = sorted(key for key in used if key not in tables["en"])
print(f"  codice: {len(used)} chiavi distinte usate nei sorgenti")
if missing:
    failed = True
    for key in missing:
        files = ", ".join(sorted(used[key]))
        print(f"✗ Chiave non localizzata: {key!r} ({files})", file=sys.stderr)

unused = sorted(tables["en"] - set(used))
if unused:
    # Informational only: a table entry can be used by the views indirectly.
    print(f"  · {len(unused)} chiavi non referenziate direttamente dai sorgenti")

if failed:
    sys.exit(1)

print(f"✓ Localizzazioni allineate ({len(tables['en'])} chiavi)")
PY
