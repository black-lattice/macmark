#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
FILES=()
for FILE in Sources/*.swift; do
  [[ "$FILE" == Sources/MacMarkApp.swift ]] || FILES+=("$FILE")
done
xcrun swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  "${FILES[@]}" Tests/*.swift -o .build/MacMarkTests
.build/MacMarkTests
