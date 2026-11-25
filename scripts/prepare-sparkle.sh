#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$PWD/.build/sparkle-sdk"
mkdir -p "$sdk"
cd "$sdk"
if [[ -x bin/generate_appcast && -f Sparkle.framework/Sparkle && -f .ready-2.10.1 ]]; then exit 0; fi
curl --fail --silent --show-error --location --retry 3 \
    https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz -o sdk.tar.xz
echo '1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27  sdk.tar.xz' | shasum -a 256 -c -
tar -xf sdk.tar.xz
touch .ready-2.10.1
