#!/usr/bin/env bash
# Bumps pubspec.yaml's version (patch +1, build number = today, see
# tool/bump_version.py) THEN builds the release APK — in that order, as two
# separate steps, because Flutter's own tool reads pubspec.yaml's version
# before it ever hands off to Gradle; a hook living inside
# android/app/build.gradle.kts runs too late to affect the very build it's
# part of (verified: the built APK still carried the pre-bump version and
# versionCode). This script is the actual "automatic on every release
# build" mechanism — run builds through this, not a raw `flutter build`,
# for the version bump to actually take effect.
#
# Usage: scripts/build_release.sh <env> [extra flutter build apk flags]
#   <env> names a settings file, config/<env>.json (git-ignored; copy
#   config/<env>.example.json to create it). It is passed to Flutter with
#   --dart-define-from-file, so API_BASE_URL etc. are baked into the APK.
# Example:
#   scripts/build_release.sh prod
#   scripts/build_release.sh dev --dart-define=LOGGING=true
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -lt 1 ] || [[ "$1" == -* ]]; then
  echo "Usage: $0 <env> [extra flutter build apk flags]" >&2
  echo "  <env> = name of a file in config/ (e.g. prod -> config/prod.json)" >&2
  exit 1
fi
env_name="$1"
shift
cfg="config/${env_name}.json"
if [ ! -f "$cfg" ]; then
  echo "Missing $cfg — copy config/${env_name}.example.json to $cfg and fill it in." >&2
  exit 1
fi

python3 tool/bump_version.py
flutter build apk --release --dart-define-from-file="$cfg" \
  --dart-define=BUILD_TIME="$(date '+%Y-%m-%d %H:%M %Z')" "$@"
