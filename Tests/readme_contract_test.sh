#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZH="$ROOT/README.md"
EN="$ROOT/README.en.md"
fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q 'iOS Location Service Research & Testing Framework' "$ZH" || fail "Chinese README positioning is missing"
grep -q 'iOS Location Service Research & Testing Framework' "$EN" || fail "English README positioning is missing"

grep -q '#### 自签安装说明' "$ZH" || fail "Chinese self-signing instructions are missing"
grep -q '#### Self-Signing Instructions' "$EN" || fail "English self-signing instructions are missing"
grep -q 'Impactor Releases' "$ZH" || fail "Chinese README must link the requested Impactor releases"
grep -q 'Impactor Releases' "$EN" || fail "English README must link the requested Impactor releases"
grep -q '开发者模式' "$ZH" || fail "Chinese README must explain iOS 16 Developer Mode"
grep -q 'Developer Mode' "$EN" || fail "English README must explain iOS 16 Developer Mode"
grep -q '7 天有效期' "$ZH" || fail "Chinese README must disclose free-signing expiry"
grep -q 'seven days' "$EN" || fail "English README must disclose free-signing expiry"

grep -q '^## 功能预览$' "$ZH" || fail "Chinese feature preview is missing"
grep -q '^## Feature Preview$' "$EN" || fail "English feature preview is missing"

images=(
  '主界面.jpg'
  'Apple%20Map.jpg'
  '高德地图.jpg'
  '微信.jpg'
  '钉钉.jpg'
  '高血压.jpg'
)
for image in "${images[@]}"; do
  grep -q "images/$image" "$ZH" || fail "Chinese README is missing image: $image"
  grep -q "images/$image" "$EN" || fail "English README is missing image: $image"
done

image_files=(
  '主界面.jpg'
  'Apple Map.jpg'
  '高德地图.jpg'
  '微信.jpg'
  '钉钉.jpg'
  '高血压.jpg'
)
for image in "${image_files[@]}"; do
  test -f "$ROOT/images/$image" || fail "referenced preview image is missing: $image"
done

test "$(grep -c '^## ' "$ZH")" -eq "$(grep -c '^## ' "$EN")" \
  || fail "Chinese and English README section counts must stay aligned"

! grep -Eq '^## (许可证|License)$' "$ZH" "$EN" || fail "README must not claim a repository license"
grep -q '当前项目不支持在 Windows 上直接构建 iOS 应用' "$ZH" || fail "Chinese README must reject Windows source builds"
grep -q 'Building the iOS app directly on Windows is not supported' "$EN" || fail "English README must reject Windows source builds"

if grep -Rnw --include='*.md' --include='*.sh' \
  "$ROOT/build.sh" "$ROOT/README.md" "$ROOT/README.en.md" "$ROOT/docs" "$ROOT/Scripts" \
  -e 'Impact'; then
  fail "documentation and build output must use the correct Impactor name"
fi

echo "PASS: README contract"
