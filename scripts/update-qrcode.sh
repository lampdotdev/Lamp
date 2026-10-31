#!/bin/zsh
# Puts the QR code encoder lamp.js draws phones' join codes with (`LampQR`, DeviceSupport.qrJS) in
# Resources/WebLibraries/qrcode: qrcode-generator by Kazuhiko Arase, plain ES5, so it runs in the TVs' browsers too.
#
# It comes from one release on npm, the package checked against the SHA-512 below (the `integrity` npm lists for that
# version); dist/qrcode.js is kept as published, and its license is the repository's at that release's tag (the package
# carries the notice only in the file's header). Run it to move to another release: change the lines below
# (`npm view qrcode-generator@<version> dist.integrity`, and the release's tag on GitHub).
set -euo pipefail
cd "${0:A:h}/.."
version=2.0.4
tag=js2.0.4
integrity=sha512-mZSiP6RnbHl4xL2Ap5HfkjLnmxfKcPWpWe/c+5XxCuetEenqmNFf1FH/ftXPCtFG5/TDobjsjz6sSNL0Sr8Z9g==

out=Resources/WebLibraries/qrcode
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/package.tgz" "https://registry.npmjs.org/qrcode-generator/-/qrcode-generator-$version.tgz"
got="sha512-$(shasum -a 512 "$work/package.tgz" | cut -d' ' -f1 | xxd -r -p | base64)"
[[ "$got" == "$integrity" ]] || { echo "The package isn't the one npm lists for $version." >&2; exit 1; }
mkdir "$work/package-files" && tar -xzf "$work/package.tgz" -C "$work/package-files" package/dist/qrcode.js
mkdir "$work/qrcode"
mv "$work/package-files/package/dist/qrcode.js" "$work/qrcode/qrcode.js"
curl -fsSL -o "$work/qrcode/LICENSE" "https://raw.githubusercontent.com/kazuhikoarase/qrcode-generator/$tag/LICENSE"
cat > "$work/qrcode/NOTICE.md" <<NOTICE
QR Code Generator for JavaScript $version (github.com/kazuhikoarase/qrcode-generator), Copyright (c) 2009 Kazuhiko
Arase, the npm package qrcode-generator at $version, under the MIT License in LICENSE (the repository's at $tag):
dist/qrcode.js as published, the package checked against the SHA-512 npm lists for it (scripts/update-qrcode.sh).
"QR Code" is a registered trademark of DENSO WAVE INCORPORATED.
NOTICE
rm -rf "$out" && mv "$work/qrcode" "$out"
du -sh "$out"
