#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/Shared/AppRemoteConfiguration.swift"
CONTENT="$ROOT/App/ContentView.swift"
MAP="$ROOT/App/MapHomeView.swift"
SETUP="$ROOT/App/FirstSetupView.swift"
SETTINGS="$ROOT/App/SettingsView.swift"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

python3 - "$ROOT/version.txt" <<'PY' || exit 1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

assert config["latestVersion"] == "1.0.2"
assert config["minimumSupportedVersion"] == "1.0.0"
assert "shadowrocket" not in config["communityPromptClients"]
assert set(config["communityPromptClients"]) == {
    "surge", "quantumultX", "loon", "stash", "egern"
}
PY

grep -q 'static let fallback = AppRemoteConfiguration' "$CONFIG" \
  || fail "the app must ship a built-in remote-configuration fallback"
grep -q 'timeoutIntervalForRequest = 1.5' "$CONFIG" \
  || fail "remote configuration requests must use a short timeout"
grep -q 'timeoutIntervalForResource = 2' "$CONFIG" \
  || fail "remote configuration resource loading must use a short timeout"
! grep -q 'data.count' "$CONFIG" \
  || fail "the client must not impose a remote configuration file-size limit"
grep -q 'docs/releases/v\\(version).md' "$CONFIG" \
  || fail "update notes must come from the archived release document"
grep -q '/releases/latest' "$CONFIG" \
  || fail "missing release notes must fall back to the latest Release page"
grep -q '.task { await checkForUpdates() }' "$CONTENT" \
  || fail "update detection must run asynchronously outside bootstrap"
! grep -A90 'private func bootstrap() async' "$CONTENT" | grep -q 'fetch()' \
  || fail "remote configuration must not block the startup gate"

grep -q '社区分享成功配置？' "$MAP" \
  || fail "non-Shadowrocket success must offer community contribution"
grep -q 'Button("去提交")' "$MAP" \
  || fail "community contribution prompt must expose the submit action"
grep -q 'Button("复制模板")' "$MAP" \
  || fail "community contribution prompt must expose an explicit copy action"
grep -q 'Button("取消", role: .cancel)' "$MAP" \
  || fail "the first community prompts must expose cancel"
grep -q 'Button("不再提示", role: .cancel)' "$MAP" \
  || fail "the third community prompt must allow permanent suppression"
grep -q '匿名收录，不在 README 展示投稿账号' "$MAP" \
  || fail "the contribution template must offer anonymous README attribution"
grep -q 'community-config,client-\\(client.rawValue)' "$MAP" \
  || fail "community submissions must be categorized by client labels"
grep -q 'UIPasteboard.general.string = communityContributionIssueBody' "$MAP" \
  || fail "the explicit copy action must copy the issue template"
! grep -A25 'private func openCommunityContributionIssue' "$MAP" | grep -q 'UIPasteboard.general.string' \
  || fail "opening GitHub must not copy the template automatically"

for obsolete in \
  '我已配置，开始检测' \
  '确认完成，重新检测' \
  '下一步：导入配置' \
  '我已导入，检测接口连接'; do
  ! grep -q "$obsolete" "$SETUP" \
    || fail "setup footer must not retain dynamic label: $obsolete"
done
test "$(grep -c 'actionLabel("完成")' "$SETUP")" -eq 4 \
  || fail "all setup footer primary actions must use the fixed 完成 label"

application_line="$(grep -n 'Section("应用")' "$SETTINGS" | head -n 1 | cut -d: -f1)"
certificate_line="$(grep -n 'Section("证书")' "$SETTINGS" | head -n 1 | cut -d: -f1)"
test "$application_line" -lt "$certificate_line" \
  || fail "the APP certificate reset section must appear below the application section"

echo "PASS: update and community contribution contract"
