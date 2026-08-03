#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

"$ROOT/Scripts/build-core.sh"
xcodegen generate

echo "Project generated. Run make ipa-unsigned to build an unsigned IPA."
