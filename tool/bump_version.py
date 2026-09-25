#!/usr/bin/env python3
"""Bumps pubspec.yaml's version for a release build: increments the patch
number, sets the build number to today's date (YYYYMMDD). Run automatically
by android/app/build.gradle.kts before a release-flavored Gradle task, only
for that build type — see the guard there for why (Gradle evaluates this
file once per invocation, config-phase, before flutter.versionCode/
versionName are read).

Writes back only the `version:` line; the rest of pubspec.yaml is untouched.
"""
import re
import sys
from datetime import date
from pathlib import Path

PUBSPEC = Path(__file__).resolve().parent.parent / "pubspec.yaml"
# [ \t]*, not \s* — \s matches newlines too, which let this eat the blank
# line that follows `version:` in pubspec.yaml (confirmed by a real test
# run: the blank line before `environment:` vanished). Stay on this one line.
PATTERN = re.compile(r"^version:[ \t]*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?[ \t]*$", re.MULTILINE)


def bump(text: str) -> tuple[str, str]:
    m = PATTERN.search(text)
    if not m:
        raise SystemExit(f"bump_version.py: no 'version: X.Y.Z' line found in {PUBSPEC}")
    major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    new_version = f"{major}.{minor}.{patch + 1}+{date.today().strftime('%Y%m%d')}"
    new_text = text[: m.start()] + f"version: {new_version}" + text[m.end():]
    return new_text, new_version


def main() -> None:
    text = PUBSPEC.read_text()
    new_text, new_version = bump(text)
    PUBSPEC.write_text(new_text)
    print(f"bump_version.py: pubspec.yaml version -> {new_version}")


if __name__ == "__main__":
    sys.exit(main())
