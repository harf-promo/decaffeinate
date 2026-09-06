#!/usr/bin/env bash
# Localization structure check — the same two rules as LocalizationTests, in a
# form that runs without Xcode.
#
#   1. Every shipped .lproj defines exactly the same keys.
#   2. Every literal key passed to L10n.localized(…) exists in the base table.
#
# `swift test` is the gate CI enforces; this exists so the check is also runnable
# on a machine with no Swift toolchain (the Linux side of this project's split
# scope), and so a translator can run it without building the app.
#
# Usage: ./Scripts/check-l10n.sh   — exits non-zero on any gap.
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 - "$@" <<'PY'
import re
import sys
from pathlib import Path

SOURCES = Path("Sources/Decaffeinate")
RESOURCES = SOURCES / "Resources"
BASE = "en"

# Keys the app looks up that no table defines. They render as their English key
# text in every language. Keep in step with `untabledKeyLedger` in
# Tests/DecaffeinateTests/LocalizationTests.swift.
UNTABLED_LEDGER = 5


def unescape(text: str) -> str:
    """Swift source escapes -> the characters a .strings table stores."""
    text = re.sub(r"\\u\{([0-9A-Fa-f]+)\}", lambda m: chr(int(m.group(1), 16)), text)
    for source, target in (('\\"', '"'), ("\\n", "\n"), ("\\t", "\t"), ("\\\\", "\\")):
        text = text.replace(source, target)
    return text


def literal_keys(text: str):
    """Every L10n.localized("…") key that is built only from literals.

    Adjacent literals are joined: several long strings are written as "a " + "b"
    to stay inside the line limit, and the key Swift looks up is the whole
    sentence. Computed keys are skipped — there is nothing to check.
    """
    for call in re.finditer(r"L10n\.localized\(", text):
        i, depth, parts, between = call.end(), 1, [], []
        while i < len(text) and depth > 0:
            char = text[i]
            if char == '"':
                j, buf = i + 1, []
                while j < len(text):
                    if text[j] == "\\":
                        buf.append(text[j : j + 2])
                        j += 2
                        continue
                    if text[j] == '"':
                        break
                    buf.append(text[j])
                    j += 1
                parts.append("".join(buf))
                i = j + 1
                continue
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    break
            elif char == "," and depth == 1:
                break
            between.append(char)
            i += 1
        if parts and not any(c.isalpha() for c in between):
            line = text[: call.start()].count("\n") + 1
            yield unescape("".join(parts)), line


def table_keys(language: str):
    path = RESOURCES / f"{language}.lproj" / "Localizable.strings"
    keys = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r'^"((?:[^"\\]|\\.)*)"\s*=', line)
        if match:
            keys.add(unescape(match.group(1)))
    return keys


languages = sorted(p.name[: -len(".lproj")] for p in RESOURCES.glob("*.lproj"))
if BASE not in languages:
    sys.exit(f"no {BASE}.lproj under {RESOURCES}")

base = table_keys(BASE)
print(f"languages: {', '.join(languages)}   base keys: {len(base)}")

failed = False
for language in languages:
    if language == BASE:
        continue
    other = table_keys(language)
    missing, extra = sorted(base - other), sorted(other - base)
    if missing or extra:
        failed = True
        print(f"\n{language}.lproj is not at parity with {BASE}:")
        for key in missing:
            print(f"  missing: {key!r}")
        for key in extra:
            print(f"  extra:   {key!r}")
    else:
        print(f"{language}.lproj: at parity ({len(other)} keys)")

used, seen = [], set()
for path in sorted(SOURCES.rglob("*.swift")):
    for key, line in literal_keys(path.read_text(encoding="utf-8")):
        if key not in base and key not in seen:
            seen.add(key)
            used.append((f"{path}:{line}", key))

print(f"\nuntabled keys: {len(used)} (ledger {UNTABLED_LEDGER})")
for anchor, key in sorted(used):
    print(f"  {anchor}  {key!r}")
if len(used) != UNTABLED_LEDGER:
    failed = True
    print(
        f"\nledger mismatch: expected {UNTABLED_LEDGER}, found {len(used)}."
        "\nAdd each key to every .lproj, then update UNTABLED_LEDGER here and"
        "\nuntabledKeyLedger in Tests/DecaffeinateTests/LocalizationTests.swift."
    )

sys.exit(1 if failed else 0)
PY
