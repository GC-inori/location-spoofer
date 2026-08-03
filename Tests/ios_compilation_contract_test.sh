#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

test -f "$ROOT/App/ProxyManager.swift" || fail "ProxyManager must exist"
test -f "$ROOT/Shared/RuntimeLog.swift" || fail "RuntimeLog must exist"
test -f "$ROOT/App/RealtimeLocationManager.swift" || fail "RealtimeLocationManager must exist"

# VPNManager and Tunnel must NOT exist
test ! -f "$ROOT/App/VPNManager.swift" || fail "VPNManager must be removed"
test ! -d "$ROOT/Tunnel" || fail "Tunnel directory must be removed"

# MobileConfigGenerator removed (unusable)
test ! -f "$ROOT/Shared/MobileConfigGenerator.swift" || fail "MobileConfigGenerator must be removed"

# No duplicate flow test logic
grep -q 'func runVerificationTest' "$ROOT/App/SetupCoordinator.swift" || fail "runVerificationTest must exist in SetupCoordinator"
if grep -q 'func runFullFlowTest' "$ROOT/App/LocationActionCoordinator.swift"; then
  fail "runFullFlowTest duplicate logic must be removed"
fi

echo "PASS: iOS compilation contract"
