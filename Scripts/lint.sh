#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
version="$(cat .swiftlint-version)"
binary="${SWIFTLINT_BIN:-swiftlint}"

if ! command -v "$binary" >/dev/null 2>&1; then
    if [ -x "/tmp/swiftlint/swiftlint" ]; then
        binary="/tmp/swiftlint/swiftlint"
    fi
fi

command -v "$binary" >/dev/null || { echo "Install SwiftLint $version with: bash Scripts/install-swiftlint.sh /tmp/swiftlint" >&2; exit 1; }
[[ "$("$binary" version)" == "$version" ]] || { echo "SwiftLint $version is required; refusing a different rules engine" >&2; exit 1; }
xcrun --find swiftc >/dev/null
exec "$binary" lint --strict --no-cache --config .swiftlint.yml "$@"
