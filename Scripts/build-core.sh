#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/Core"
BUILD="$CORE/build"
MIN_IOS_VERSION="15.0"

build_archive() {
  local sdk="$1"
  local min_flag="$2"
  local output="$3"
  local sdk_path
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

  CGO_ENABLED=1 \
  CGO_CFLAGS="-arch arm64 -isysroot $sdk_path $min_flag" \
  CGO_LDFLAGS="-arch arm64 -isysroot $sdk_path $min_flag" \
  GOOS=ios GOARCH=arm64 \
  go build -buildmode=c-archive -ldflags="-s -w" -o "$output" .
}

rm -rf "$BUILD"
mkdir -p "$BUILD/iphoneos" "$BUILD/iphonesimulator"
cd "$CORE"
go mod download

build_archive iphoneos "-miphoneos-version-min=$MIN_IOS_VERSION" "$BUILD/iphoneos/libwloccore.a"
build_archive iphonesimulator "-mios-simulator-version-min=$MIN_IOS_VERSION" "$BUILD/iphonesimulator/libwloccore.a"
cp "$BUILD/iphoneos/libwloccore.h" "$ROOT/Core/wloccore.h"

test -s "$BUILD/iphoneos/libwloccore.a"
test -s "$BUILD/iphonesimulator/libwloccore.a"
test -s "$ROOT/Core/wloccore.h"
echo "Built device and simulator Core archives"
