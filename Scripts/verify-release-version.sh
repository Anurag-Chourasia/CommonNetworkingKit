#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

kit_name="$(basename "$repo_root")"
echo "=== Verifying release version control for $kit_name ==="

if [ ! -f "CHANGELOG.md" ]; then
    echo "ERROR: CHANGELOG.md is missing in $kit_name" >&2
    exit 1
fi

latest_version=$(grep -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]|^## [0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | head -n 1 | sed -E 's/^## \[?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

if [ -z "$latest_version" ]; then
    echo "ERROR: Could not parse latest semantic version from CHANGELOG.md in $kit_name" >&2
    exit 1
fi
echo "Latest documented version: $latest_version"

if ! echo "$latest_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ERROR: Version '$latest_version' does not follow SemVer format" >&2
    exit 1
fi

xcrun swift package dump-package > /dev/null
echo "Manifest validated. Version control check passed for $kit_name."
