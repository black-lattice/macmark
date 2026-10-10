#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.5}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "版本号必须为 x.y.z"; exit 1; }
mkdir -p .build dist
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O -whole-module-optimization \
    -sdk "$SDK" -target "$ARCH-apple-macos14.0" Sources/*.swift -o ".build/MacMark-$ARCH"
done
APP="dist/MacMark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/MacMark-arm64 .build/MacMark-x86_64 -output "$APP/Contents/MacOS/MacMark"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-5}" "$APP/Contents/Info.plist"
swift scripts/Icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signing makes the arm64 executable valid. This is not Developer ID signing.
codesign --force --sign - --identifier io.github.black-lattice.macmark "$APP"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/MacMark" -verify_arch arm64 x86_64
plutil -lint "$APP/Contents/Info.plist"
