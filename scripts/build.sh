#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "版本号必须为 x.y.z"; exit 1; }
bash scripts/prepare-sparkle.sh
mkdir -p .build dist
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -F .build/sparkle-sdk -Xlinker -rpath -Xlinker @executable_path/../Frameworks -swift-version 5 -parse-as-library -O -whole-module-optimization \
    -sdk "$SDK" -target "$ARCH-apple-macos14.0" Sources/*.swift -o ".build/MacMark-$ARCH"
done
APP="dist/MacMark.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/MacMark-arm64 .build/MacMark-x86_64 -output "$APP/Contents/MacOS/MacMark"
mkdir -p "$APP/Contents/Frameworks"
ditto .build/sparkle-sdk/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
cp .build/sparkle-sdk/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-$(plutil -extract CFBundleVersion raw Resources/Info.plist)}" "$APP/Contents/Info.plist"
swift scripts/Icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signing makes the arm64 executable valid. This is not Developer ID signing.
codesign --force --sign - --identifier io.github.black-lattice.macmark "$APP"
codesign --verify --deep --strict "$APP"
for binary in "$APP/Contents/MacOS/MacMark" "$APP/Contents/Frameworks/Sparkle.framework/Sparkle"; do
  architectures=" $(lipo -archs "$binary") "
  [[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]]
done
plutil -lint "$APP/Contents/Info.plist"
