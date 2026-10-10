#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.5}"
NAME="MacMark-$VERSION-universal"
[[ -d dist/MacMark.app ]] || { echo "请先执行 scripts/build.sh"; exit 1; }
STAGE=".build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto dist/MacMark.app "$STAGE/MacMark.app"
ln -s /Applications "$STAGE/Applications"
cp INSTALL.txt "$STAGE/安装说明.txt"
hdiutil create -volname "轻截 MacMark" -srcfolder "$STAGE" -ov -format UDZO "dist/$NAME.dmg"
ditto -c -k --sequesterRsrc --keepParent dist/MacMark.app "dist/$NAME.zip"
(cd dist && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
