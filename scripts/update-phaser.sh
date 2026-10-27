#!/bin/zsh
# Puts Phaser, the 2D library a game of Lamp's game kind draws with when it's 2D, in Resources/WebLibraries/phaser: the
# ES module build (phaser.esm.min.js, Arcade and Matter physics included) and its license. Lamp writes it into a game's
# Web/phaser only when the game's own files use it (`GameKit.write`), as it writes three.js's node renderer only when used.
#
# It comes from the package Phaser publishes on npm, checked against the SHA-512 the registry lists for that version, so
# what's fetched is exactly that release. Phaser 3 rather than 4: 3.90 is its last release, finished and widely known, so
# the agent writes it well, and it draws with WebGL 1 or a plain canvas where a TV's browser has no WebGL 2. Run it to move
# to another version: change the line below, then check a game on every host (the skills' 2d-game names what Lamp wires).
set -euo pipefail
cd "${0:A:h}/.."
version=3.90.0

out=Resources/WebLibraries/phaser
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL "https://registry.npmjs.org/phaser/$version" -o "$work/release.json"
curl -fsSL "$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["dist"]["tarball"])' "$work/release.json")" -o "$work/package.tgz"
python3 -I - "$work" <<'EOF'
import base64, hashlib, io, json, os, sys, tarfile
work = sys.argv[1]
dist = json.load(open(os.path.join(work, "release.json")))["dist"]
algorithm, digest = dist["integrity"].split("-", 1)
if algorithm != "sha512": sys.exit(f"The registry lists a {algorithm} hash, not SHA-512.")
data = open(os.path.join(work, "package.tgz"), "rb").read()
if hashlib.sha512(data).digest() != base64.b64decode(digest): sys.exit("The package isn't the one the registry lists.")
wanted = {"package/dist/phaser.esm.min.js": "phaser.esm.min.js", "package/LICENSE.md": "LICENSE.md"}
os.makedirs(os.path.join(work, "phaser"))
with tarfile.open(fileobj=io.BytesIO(data)) as tar:
    for member in tar.getmembers():
        if member.name in wanted and member.isfile():
            open(os.path.join(work, "phaser", wanted.pop(member.name)), "wb").write(tar.extractfile(member).read())
if wanted: sys.exit("The package is missing " + ", ".join(wanted))
EOF
rm -rf "$out" && mv "$work/phaser" "$out"
cat > "$out/NOTICE.md" <<EOF
Phaser $version, the npm package phaser@$version (github.com/phaserjs/phaser), under the MIT license in LICENSE.md:
dist/phaser.esm.min.js, checked against the SHA-512 the npm registry lists for the package.
EOF
du -sh "$out"
