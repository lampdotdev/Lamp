#!/bin/zsh
# Puts Rapier, the physics engine a three.js game takes once its code imports it (GameKit.usesRapier), in
# Resources/WebLibraries/rapier: the ES module of @dimforge/rapier3d-compat, which carries its WebAssembly inside it, so
# a page loads it like any other module, from its own folder, wherever a game is played.
#
# It comes from one release on npm, the package checked against the SHA-512 below (the `integrity` npm lists for that
# version), and rapier.mjs is kept as published under the name rapier.js, which every host serves as JavaScript. Run it
# to move to another release: change both lines below (`npm view @dimforge/rapier3d-compat@<version> dist.integrity`).
set -euo pipefail
cd "${0:A:h}/.."
version=0.21.0
integrity=sha512-tCl1HPGwOhn5aCQbgqWbOH+Nx/5fnr3IPAnzQuR7zIhC/raqi2yxC6LhvZqjdI2El5hQgY5RDAwDrAjAi2FdPA==

out=Resources/WebLibraries/rapier
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/package.tgz" "https://registry.npmjs.org/@dimforge/rapier3d-compat/-/rapier3d-compat-$version.tgz"
got="sha512-$(shasum -a 512 "$work/package.tgz" | cut -d' ' -f1 | xxd -r -p | base64)"
[[ "$got" == "$integrity" ]] || { echo "The package isn't the one npm lists for $version." >&2; exit 1; }
mkdir "$work/package-files" && tar -xzf "$work/package.tgz" -C "$work/package-files" package/dist/rapier.mjs package/LICENSE
mkdir "$work/rapier"
mv "$work/package-files/package/dist/rapier.mjs" "$work/rapier/rapier.js"
mv "$work/package-files/package/LICENSE" "$work/rapier/LICENSE"
cat > "$work/rapier/NOTICE.md" <<EOF
Rapier $version (https://rapier.rs, github.com/dimforge/rapier), the npm package @dimforge/rapier3d-compat at $version,
under the Apache License 2.0 in LICENSE: dist/rapier.mjs as published, named rapier.js here, the package checked
against the SHA-512 npm lists for it (scripts/update-rapier.sh).
EOF
rm -rf "$out" && mv "$work/rapier" "$out"
du -sh "$out"
