#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

MODE="$ROOT/Shared/ProxyRuntimeMode.swift"
MANAGER="$ROOT/Shared/ThirdPartyProxyManager.swift"
CONTENT="$ROOT/App/ContentView.swift"
SETUP="$ROOT/App/FirstSetupView.swift"
SETTINGS="$ROOT/App/SettingsView.swift"
MODULES="$ROOT/Resources/ThirdPartyProxyModules"

grep -q 'return "APP模式"' "$MODE" || fail "APP mode display name is missing"
grep -q 'return "第三方代理模式"' "$MODE" || fail "third-party mode display name is missing"
grep -q 'hasSelectedMode' "$MODE" || fail "first-launch mode selection must be persisted"
grep -q 'guard runtimeMode.hasSelectedMode else' "$CONTENT" || fail "mode selection must gate startup"
grep -q 'phase = .setup' "$CONTENT" || fail "first launch must enter setup before map construction"
grep -q 'case thirdPartyClient' "$SETUP" || fail "third-party client selection step is missing"
grep -q 'case thirdPartyImport' "$SETUP" || fail "third-party import step is missing"
grep -q 'case thirdPartyTest' "$SETUP" || fail "third-party connection test step is missing"
! grep -q '生成并导入配置文件' "$SETUP" || fail "setup must not offer file generation/import"
grep -q '复制订阅地址' "$SETUP" || fail "subscription URL copy action is missing"
grep -Fq 'Label("打开 \(client.name)"' "$SETUP" || fail "setup must expose a client launch action"
grep -Fq 'Label("打开 \(thirdPartyClient.selectedClient.name)"' "$SETTINGS" || fail "Settings must expose a client launch action"
! grep -q '在浏览器打开模块文件' "$SETTINGS" || fail "Settings must not open the module URL as the primary client action"
grep -q 'requestThirdPartySetup' "$SETTINGS" || fail "Settings must reopen third-party setup"

for file in wloc.module wloc.sgmodule wloc.conf wloc.lpx wloc.stoverride; do
  test -s "$MODULES/$file" || fail "missing bundled module: $file"
done

grep -q 'wloc.sgmodule' "$MANAGER" || fail "Surge/Egern module mapping is missing"
grep -q 'wloc.stoverride' "$MANAGER" || fail "Stash must use .stoverride directly"
grep -q 'shadowrocket://' "$MANAGER" || fail "Shadowrocket launch URL is missing"
for scheme in surge quantumult-x loon stash egern; do
  grep -q "${scheme}://" "$MANAGER" || fail "$scheme launch URL is missing"
done
grep -q '复制解密域名' "$SETUP" || fail "Shadowrocket MITM hostname copy action is missing"
grep -q '配置 → 模块' "$SETUP" || fail "Shadowrocket module import guidance is missing"
grep -q 'HTTPS 解密' "$SETUP" || fail "Shadowrocket HTTPS decryption guidance is missing"
! grep -q 'ToolbarItem(placement: .navigationBarLeading)' "$SETUP" || fail "setup must not show a top-left navigation action"
grep -q 'presentSuccessfulOperationTip(.activation)' "$ROOT/App/MapHomeView.swift" || fail "third-party save must present the activation tip"
grep -q 'presentSuccessfulOperationTip(.deactivation)' "$ROOT/App/MapHomeView.swift" || fail "third-party clear must present the deactivation tip"
grep -q 'if spoofState == .active' "$ROOT/App/MapHomeView.swift" || fail "manual help must follow the shared spoof state"
grep -q 'MARKETING_VERSION: "1.0.1"' "$ROOT/project.yml" || fail "marketing version must be 1.0.1"
grep -q 'CURRENT_PROJECT_VERSION: "2"' "$ROOT/project.yml" || fail "build version must be 2"

echo "PASS: third-party proxy mode contract"
