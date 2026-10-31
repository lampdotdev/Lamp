#!/bin/zsh
# Builds this checkout's LampSupport.swift with scripts/act-checks.swift and runs it: the native `LampActSession`'s own
# guarantees (checks before changes, a change delivered twice running once, cancel, questions back, limits) against a
# stand-in for Lamp. Run it after changing LampActSession in Template.swift.
set -euo pipefail
here="${0:A:h}/.."
template="$here/Sources/Lamp/Template.swift"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The same extraction as scripts/check-starters.sh: the raw string, with its placeholders filled by stand-ins.
extract() {
  awk -v start="static let $1 = #\"\"\"" '
    index($0, start) { on = 1; next }
    on && /^ *"""#( \+ [A-Za-z]+)?$/ { exit }
    on { print }' "$template" |
    perl -pe 's/^ *\/\/ \{\{SIGN_IN_SERVICES\}\}\n/\n/; s/^ *\/\/ \{\{TOKEN_SERVICES\}\}\n/\n/' |
    sed -E 's/\{\{WISH_LEAVES_LAMP_CLOSED\}\}//g; s/\{\{[A-Z_]*(PORT|TRIES)\}\}/7777/g; s/\{\{[A-Z_]+\}\}/stand-in/g'
}
{ extract lampSupportTemplate; print "#if os(macOS)"; extract lampGlyphSwift; print "#endif" } > "$work/LampSupport.swift"

sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
xcrun swiftc -parse-as-library -swift-version 5 -suppress-warnings -target arm64-apple-macos14.0 -sdk "$sdk" \
  "$work/LampSupport.swift" "$here/scripts/act-checks.swift" -o "$work/act-checks"
"$work/act-checks"
