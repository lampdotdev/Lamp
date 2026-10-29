#!/bin/zsh
# Puts ws, the WebSocket server an LG game's phone service speaks with (Resources/LGPhones, LGPhones.swift), in
# Resources/LGPhones/node_modules/ws: its library and license, from the npm registry's tarball, checked against the
# integrity the registry lists for that version. 7.x because it's plain JavaScript that runs on Node 8.3 and later, the
# oldest Node an LG TV that takes the service has (webOS TV 5.0: 8.12); its optional native helpers are left out, as LG's
# services take no C/C++ addons. Run it to move to another version: change the two lines below.
set -euo pipefail
cd "${0:A:h}/.."
version=7.5.10
integrity='sha512-+dbF1tHwZpXcbOJdVOkzLDxZP1ailvSxM6ZweXTegylPny803bFhA+vqBYw4s31NSAk4S2Qz+AKXK9a4wkdjcQ=='

out=Resources/LGPhones/node_modules/ws
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL "https://registry.npmjs.org/ws/-/ws-$version.tgz" -o "$work/ws.tgz"
got="sha512-$(openssl dgst -sha512 -binary "$work/ws.tgz" | base64)"
[[ "$got" == "$integrity" ]] || { print -u2 "ws $version didn't match its integrity: $got"; exit 1; }
tar xzf "$work/ws.tgz" -C "$work"
rm -rf "$out"
mkdir -p "$out"
cp -R "$work/package/lib" "$work/package/index.js" "$work/package/package.json" "$work/package/LICENSE" "$out/"
print "Put ws $version in $out."
