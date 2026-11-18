#!/usr/bin/env bash
set -euo pipefail

# Verify the localization tables.
#
# 1. English and Italian expose the same keys, without duplicates, in both
#    Localizable.strings and InfoPlist.strings; Italian source keys are identity
#    mappings and format specifiers (%ld, %@) match across languages.
# 2. Every key used by the Swift sources exists in the tables. The scan covers
#    the runtime lookups (`L(...)`, `LF(...)`), ternary branches, and the
#    SwiftUI / component literals that are localized on purpose, so a new
#    user-facing string cannot reach a release untranslated.
# 3. Orphaned entries in Localizable.strings that no longer appear anywhere in
#    Sources/ are rejected so stale keys do not accumulate.
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
en_plist_path = os.path.join(root, "Resources/en.lproj/InfoPlist.strings")
it_plist_path = os.path.join(root, "Resources/it.lproj/InfoPlist.strings")
sources = os.path.join(root, "Sources")

PAIR = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.MULTILINE)
SPECIFIERS = re.compile(r'%%|%(?:\d+\$)?l*[dDuUxXoOfeEgGcCsSpaAF@]')
STRING_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')

# Patterns that always produce a localization lookup at runtime.
KEY_CALLS = re.compile(
    r'\b(?:L|LF)\(\s*"((?:[^"\\]|\\.)*)"'          # L("...") / LF("...")
    r'|\b(?:Text|Button|Label|Toggle|SecureField|TextField|Menu|SectionLabel)'
    r'\(\s*"((?:[^"\\]|\\.)*)"'                     # Text("..."), Button("..."), ...
    r'|\b(?:text|title|subtitle|help):\s*"((?:[^"\\]|\\.)*)"'  # component parameters
    r'|statCell\(\s*"((?:[^"\\]|\\.)*)"'           # statCell("...", ...)
)

# Ternary expressions passed to L(...) or localized component parameters.
TERNARY_CALLS = re.compile(
    r'(?:\bL\(\s*|\b(?:title|subtitle|help):\s*)'
    r'[^;\n{}]*\?\s*([^,\n]+)'
)

TITLE_KEY_BLOCK = re.compile(r'var\s+titleKey\s*:\s*String\s*\{([^}]*)\}', re.DOTALL)
CPP_LAST_ERROR = re.compile(r'last_error\s*=\s*"((?:[^"\\]|\\.)*)"')

failed = False


def strip_block_comments(text):
    return re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)


def read_table(path, label, check_identity=False):
    global failed
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError as error:
        print(f"✗ Impossibile leggere {path}: {error}", file=sys.stderr)
        sys.exit(1)

    pairs = PAIR.findall(strip_block_comments(raw))
    keys = [k for k, _ in pairs]
    duplicates = sorted({key for key in keys if keys.count(key) > 1})
    if duplicates:
        failed = True
        print(f"✗ Chiavi duplicate in {label}: {', '.join(duplicates)}", file=sys.stderr)

    mapping = dict(pairs)
    if check_identity:
        non_identity = [k for k, v in pairs if k != v]
        if non_identity:
            failed = True
            print(f"✗ Chiavi non identiche in {label}: {', '.join(non_identity)}", file=sys.stderr)

    print(f"  {label}: {len(mapping)} chiavi")
    return mapping


en_map = read_table(en_path, "en")
it_map = read_table(it_path, "it", check_identity=True)
en_plist = read_table(en_plist_path, "InfoPlist (en)")
it_plist = read_table(it_plist_path, "InfoPlist (it)")

for name, left, right in [
    ("Localizable.strings", set(en_map), set(it_map)),
    ("InfoPlist.strings", set(en_plist), set(it_plist)),
]:
    only_en = sorted(left - right)
    only_it = sorted(right - left)
    if only_en:
        failed = True
        print(f"✗ {name} — presenti solo in inglese:", ", ".join(only_en), file=sys.stderr)
    if only_it:
        failed = True
        print(f"✗ {name} — presenti solo in italiano:", ", ".join(only_it), file=sys.stderr)

for key in sorted(set(en_map) & set(it_map)):
    key_specs = SPECIFIERS.findall(key)
    en_specs = SPECIFIERS.findall(en_map[key])
    it_specs = SPECIFIERS.findall(it_map[key])
    if key_specs != en_specs or key_specs != it_specs:
        failed = True
        print(
            f"✗ Format specifier non allineati per {key!r}: it={it_specs}, en={en_specs}",
            file=sys.stderr,
        )


def strip_comments(text):
    """Remove // and /* */ comments while keeping string literals intact."""
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


SWIFT_MAPPED_CASE = re.compile(r'case\s*"((?:[^"\\]|\\.)*)"\s*:\s*return')

used = {}
mapped_cases = set()
all_source_literals = set()

# Scan Swift first
for directory, _, files in os.walk(sources):
    for name in files:
        if name.endswith(".swift"):
            path = os.path.join(directory, name)
            text = strip_comments(open(path, encoding="utf-8").read())
            base = os.path.basename(path)
            for lit in STRING_LITERAL.findall(text):
                all_source_literals.add(lit)
            for match in KEY_CALLS.finditer(text):
                key = next(group for group in match.groups() if group is not None)
                if key:
                    used.setdefault(key, set()).add(base)
            for match in TERNARY_CALLS.finditer(text):
                for lit in STRING_LITERAL.findall(match.group(1)):
                    if lit:
                        used.setdefault(lit, set()).add(base)
            for block in TITLE_KEY_BLOCK.findall(text):
                for lit in STRING_LITERAL.findall(block):
                    if lit:
                        used.setdefault(lit, set()).add(base)
            for match in SWIFT_MAPPED_CASE.finditer(text):
                mapped_cases.add(match.group(1))

# Check that every Italian C++ last_error is mapped in Swift localizedError
for directory, _, files in os.walk(sources):
    for name in files:
        if name.endswith(".cpp") or name.endswith(".h"):
            path = os.path.join(directory, name)
            text = strip_comments(open(path, encoding="utf-8").read())
            for lit in STRING_LITERAL.findall(text):
                all_source_literals.add(lit)
            for match in CPP_LAST_ERROR.finditer(text):
                raw_err = match.group(1)
                # Skip pure English technical errors handled via lowercase substring matching
                if any(raw_err.startswith(prefix) for prefix in [
                    "Magnet URI exceeds", "Torrent path is not", "Cannot stat", "Torrent file exceeds"
                ]):
                    continue
                if raw_err not in mapped_cases and raw_err not in en_map:
                    failed = True
                    print(f"✗ Errore C++ non mappato né localizzato: {raw_err!r} ({os.path.basename(path)})", file=sys.stderr)

missing = sorted(key for key in used if key not in en_map)
print(f"  codice: {len(used)} chiavi distinte usate nei sorgenti")
if missing:
    failed = True
    for key in missing:
        files = ", ".join(sorted(used[key]))
        print(f"✗ Chiave non localizzata: {key!r} ({files})", file=sys.stderr)

orphaned = sorted(key for key in en_map if key not in all_source_literals)
if orphaned:
    failed = True
    for key in orphaned:
        print(f"✗ Chiave orfana non più presente nei sorgenti: {key!r}", file=sys.stderr)

if failed:
    sys.exit(1)

print(f"✓ Localizzazioni allineate ({len(en_map)} chiavi, 0 orfane)")
PY
