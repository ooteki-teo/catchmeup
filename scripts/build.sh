#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build-xcode/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build-xcode/module-cache"
BUILD_CONFIGURATION="${CATCHMEUP_BUILD_CONFIGURATION:-release}"

xcrun swift build --disable-sandbox --cache-path .build-xcode/cache --scratch-path .build-xcode -c "$BUILD_CONFIGURATION"
BIN_DIR="$(xcrun swift build --disable-sandbox --cache-path .build-xcode/cache --scratch-path .build-xcode -c "$BUILD_CONFIGURATION" --show-bin-path)"

APP_DIR="$PROJECT_ROOT/dist/CatchMeUp.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/CatchMeUp" "$APP_DIR/Contents/MacOS/CatchMeUp"
cp "$PROJECT_ROOT/scripts/Info.plist" "$APP_DIR/Contents/Info.plist"

# Build icon if missing
if [ ! -f "$PROJECT_ROOT/artifacts/AppIcon.icns" ]; then
  mkdir -p "$PROJECT_ROOT/artifacts"
  xcrun swift "$PROJECT_ROOT/scripts/make-icon.swift" "$PROJECT_ROOT/artifacts" || true
fi
if [ -f "$PROJECT_ROOT/artifacts/AppIcon.icns" ]; then
  cp "$PROJECT_ROOT/artifacts/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Sign with a stable identity so macOS TCC (Screen Recording, etc.) remembers the
# app across rebuilds. An ad-hoc signature uses a cdhash that changes every build
# and causes repeated permission prompts. Prefer $CODESIGN_IDENTITY, then the first
# available Apple Development identity, then fall back to ad-hoc.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)"
fi
if [ -n "$IDENTITY" ]; then
  echo "使用签名身份：$IDENTITY"
  codesign --force --sign "$IDENTITY" "$APP_DIR"
else
  echo "未找到可用签名身份，回退 ad-hoc（权限可能在重编译后重置）"
  codesign --force --sign - "$APP_DIR"
fi
printf '已生成：%s\n' "$APP_DIR"
printf '双击打开，或运行：open "%s"\n' "$APP_DIR"
