#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$PWD/.build/sparkle-sdk"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
plist=dist/MacMark.app/Contents/Info.plist
version=$(plutil -extract CFBundleShortVersionString raw "$plist")
build=$(plutil -extract CFBundleVersion raw "$plist")
asset="MacMark-$version-universal.zip"
GITHUB_REF_NAME=${GITHUB_REF_NAME:-v$version}
base="https://github.com/${GITHUB_REPOSITORY:-black-lattice/macmark}/releases/download/$GITHUB_REF_NAME/"
test "$GITHUB_REF_NAME" = "v$version"
test "$(plutil -extract SUFeedURL raw "$plist")" = "https://github.com/${GITHUB_REPOSITORY:-black-lattice/macmark}/releases/latest/download/appcast.xml"
cp "dist/$asset" "$stage/"
cp RELEASE_NOTES.md "$stage/${asset%.zip}.md"

sign() {
    local tool="$1"
    shift
    if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
        printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sdk/bin/$tool" --ed-key-file - "$@"
    else
        "$sdk/bin/$tool" --account io.github.black-lattice.macmark "$@"
    fi
}
sign generate_appcast --maximum-deltas 0 --embed-release-notes --download-url-prefix "$base" "$stage"
sign sign_update --verify "$stage/appcast.xml"

# Match the generated feed against the packaged app and verify the update with
# the app's embedded public key, independently of the signing secret.
python3 - "$stage/appcast.xml" "$base$asset" "$stage/$asset" "$version" "$build" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
feed, url, archive, version, build = sys.argv[1:]
ns = {"sp": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
item, = ET.parse(feed).findall("./channel/item")
assert item.findtext("sp:version", namespaces=ns) == build
assert item.findtext("sp:shortVersionString", namespaces=ns) == version
assert item.findtext("sp:minimumSystemVersion", namespaces=ns).split(".")[:2] == ["14", "0"]
enclosure = item.find("enclosure")
assert enclosure.get("url") == url and int(enclosure.get("length")) == pathlib.Path(archive).stat().st_size
pathlib.Path(archive + ".sig").write_text(enclosure.attrib["{" + ns["sp"] + "}edSignature"])
PY
PUBKEY=$(plutil -extract SUPublicEDKey raw "$plist") node --input-type=module - "$stage/$asset" <<'JS'
import {readFileSync} from 'node:fs';
import {createPublicKey, verify} from 'node:crypto';
const archive = process.argv[2];
const x = Buffer.from(process.env.PUBKEY, 'base64').toString('base64url');
const key = createPublicKey({key: {kty: 'OKP', crv: 'Ed25519', x}, format: 'jwk'});
if (!verify(null, readFileSync(archive), key, Buffer.from(readFileSync(archive + '.sig', 'utf8'), 'base64'))) {
    throw Error('更新包与应用内的 Sparkle 公钥不匹配');
}
JS
cp "$stage/appcast.xml" dist/appcast.xml
(cd dist && shasum -a 256 "${asset%.zip}.dmg" "$asset" appcast.xml > SHA256SUMS.txt)
