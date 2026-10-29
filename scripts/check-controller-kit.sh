#!/bin/zsh
# Type-checks Lamp's controller kit (scripts/controller-kit.sh) and the page host that runs it (LampPage.swift) for
# each place a game runs its own phones: the Mac, the iPhone and iPad simulator, and an iPhone or iPad itself. Needs
# Xcode's iOS SDKs (DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer when the Command Line Tools are the
# active ones); a place whose SDK isn't installed is said and skipped.
#
#   scripts/check-controller-kit.sh
set -euo pipefail
here="${0:A:h}/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
"$here/scripts/controller-kit.sh" "$work/LampControllerKit.swift"
# LampPage.swift stands on LampSupport.swift, which Lamp writes into every app: taken from Template.swift as
# scripts/check-starters.sh takes it, its placeholders filled with stand-ins (only their types matter here).
template="$here/Sources/Lamp/Template.swift"
extract() {
  awk -v start="static let $1 = #\"\"\"" '
    index($0, start) { on = 1; next }
    on && /^ *"""#( \+ [A-Za-z]+)?$/ { exit }
    on { print }' "$template" |
    sed -E 's/\{\{WISH_LEAVES_LAMP_CLOSED\}\}//g; s/\{\{[A-Z_]*(PORT|TRIES)\}\}/7777/g; s/\{\{[A-Z_]+\}\}/stand-in/g'
}
{ extract lampSupportTemplate; print "#if os(macOS)"; extract lampGlyphSwift; print "#endif" } > "$work/LampSupport.swift"
failed=0
check() {
  local name="$1" sdk="$2" target="$3"
  local root
  if ! root="$(xcrun --sdk "$sdk" --show-sdk-path 2>/dev/null)"; then print -- "○ $name: no $sdk SDK here, skipped"; return; fi
  if xcrun swiftc -typecheck -sdk "$root" -target "$target" -swift-version 5 \
      -parse-as-library "$work/LampControllerKit.swift" "$work/LampSupport.swift" \
      "$here/Resources/GameKit/apple/LampPage.swift" "$here/Resources/GameKit/apple/Native.swift" 2> "$work/$name.log"; then
    print -- "✓ $name"
  else
    print -- "✗ $name"; sed -n '1,40p' "$work/$name.log"; failed=1
  fi
}
check mac macosx "$(uname -m)-apple-macos14.0"
check ios-simulator iphonesimulator "$(uname -m)-apple-ios17.0-simulator"
check ios-device iphoneos "arm64-apple-ios17.0"
exit $failed
