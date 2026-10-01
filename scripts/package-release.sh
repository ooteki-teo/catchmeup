#!/bin/bash
# Build a distributable CatchMeUp.app that contains NO personal signing identity.
#
# Why: signing with an "Apple Development: you@example.com (XXXXXXXXXX)" certificate
# embeds your email and Team ID inside the app's code signature, visible via
# `codesign -dv`. For public uploads we re-sign the bundle ad-hoc instead.
#
# Note: ad-hoc signed apps are not notarized; macOS Gatekeeper will warn on first
# open (right-click → Open). This is expected for an open-source build.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Always make sure the app exists and is current.
bash scripts/build.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist 2>/dev/null || echo 0.0.0)"
STAGE="$(mktemp -d)"
OUT="$PROJECT_ROOT/dist/CatchMeUp-$VERSION.zip"

cp -R "dist/CatchMeUp.app" "$STAGE/CatchMeUp.app"

# Drop extended attributes (TCC markers, quarantine, ...).
xattr -cr "$STAGE/CatchMeUp.app" 2>/dev/null || true

# Replace the personal signature with an ad-hoc one.
codesign --force --sign - "$STAGE/CatchMeUp.app"

echo
echo "签名信息（应为 adhoc，无 Authority / TeamIdentifier）："
codesign -dv "$STAGE/CatchMeUp.app" 2>&1 | grep -E "Identifier|Signature|Authority|TeamIdentifier" || true

rm -f "$OUT"
ditto -c -k --norsrc --keepParent "$STAGE/CatchMeUp.app" "$OUT"
rm -rf "$STAGE"

printf '\n可分发文件：%s\n' "$OUT"
