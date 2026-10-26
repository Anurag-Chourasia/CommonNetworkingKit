#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(cat "$repo_root/.swiftlint-version")"
[[ "$version" == "0.65.1" ]] || { echo "Update the verified release checksum for SwiftLint $version" >&2; exit 1; }
destination="${1:?Usage: bash Scripts/install-swiftlint.sh ABSOLUTE_DESTINATION}"
[[ "$destination" == /* ]] || { echo "Destination must be absolute" >&2; exit 1; }
mkdir -p "$destination"
archive="$(mktemp -t swiftlint-release).zip"
trap 'rm -f "$archive" "${archive%.zip}"' EXIT
curl --fail --location --retry 3 "https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip" -o "$archive"
printf '%s  %s\n' 'c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0' "$archive" | shasum -a 256 -c -
unzip -oq "$archive" -d "$destination"
[[ "$("$destination/swiftlint" version)" == "$version" ]] || { echo "Unexpected SwiftLint version" >&2; exit 1; }
