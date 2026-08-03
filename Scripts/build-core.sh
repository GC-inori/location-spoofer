#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/Core"
BUILD="$CORE/build"

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN_IOS_VERSION="15.0"

export CGO_ENABLED=1
export CGO_CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=$MIN_IOS_VERSION"
export CGO_LDFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=$MIN_IOS_VERSION"
export GOOS="ios"
export GOARCH="arm64"

mkdir -p "$BUILD"
cd "$CORE"
go mod download
go build -buildmode=c-archive -ldflags="-s -w" -o "$BUILD/libwloccore.a" .
cp "$BUILD/libwloccore.h" "$ROOT/Core/wloccore.h"
test -s "$ROOT/Core/wloccore.h"

echo "Built $BUILD/libwloccore.a"
