#!/bin/zsh
# Type-checks the wishes Lamp ships with (Resources/Starters/<folder>/tree, fetched by scripts/fetch-starters.sh)
# against this checkout's LampSupport.swift, as a build would compile them: the app's own Sources with the library,
# and a widget's Widget/ with its own file. The copies of Lamp's files in each tree are left out: a build writes
# this checkout's afresh.
#
#   scripts/check-starters.sh            every starter
#   scripts/check-starters.sh today      one, by folder name
#
# Run it after changing LampSupport.swift in Template.swift: a starter that no longer compiles would greet a
# new person with a build failure.
set -euo pipefail
here="${0:A:h}/.."
template="$here/Sources/Lamp/Template.swift"
scene_template="$here/Sources/Lamp/TemplateScene.swift"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A raw string of Template.swift, from its `static let <name> = #"""` line to the `"""#` that ends it, with its
# placeholders filled by stand-ins (only their types matter here), and the code Lamp puts in for a wish's apps left out. Of the services Connectors.fill writes into
# LampSupport, each one a starter names (`LampAPI.openfoodfacts`) is declared with its type and no body.
services() {
  local type=$1
  grep -rhoE "\b$type\.[a-z][A-Za-z0-9]*\b" "$here"/Resources/Starters/*/tree/Sources 2>/dev/null | sed "s/^$type\.//" | sort -u |
    while read -r id; do
      grep -qE "static (let|var|func) $id\b" "$template" || print "        static var $id: $type { fatalError() }"
    done
}
export SIGN_IN="$(services LampService)" TOKEN="$(services LampAPI)"
extract() {
  awk -v start="static let $1 = #\"\"\"" '
    index($0, start) { on = 1; next }
    on && /^ *"""#( \+ [A-Za-z]+)?$/ { exit }
    on { print }' "${2:-$template}" |
    perl -pe 's/^ *\/\/ \{\{SIGN_IN_SERVICES\}\}\n/$ENV{SIGN_IN}\n/; s/^ *\/\/ \{\{TOKEN_SERVICES\}\}\n/$ENV{TOKEN}\n/' |
    sed -E 's/\{\{WISH_LEAVES_LAMP_CLOSED\}\}//g; s/\{\{[A-Z_]*(PORT|TRIES)\}\}/7777/g; s/\{\{[A-Z_]+\}\}/stand-in/g'
}
# Lamp's mark, which both files end with (`lampGlyphSwift`, macOS only in LampSupport).
{ extract lampSupportTemplate; print "#if os(macOS)"; extract lampGlyphSwift; print "#endif" } > "$work/LampSupport.swift"
{ extract lampWidgetSupportSwift; extract lampGlyphSwift } > "$work/LampWidgetSupport.swift"
# LampScene.swift, which Lamp writes beside LampSupport.swift into an app whose code imports RealityKit
# (`Template.usesScene`); such an app is built for macOS 15, where RealityView begins (`Template.withScene`).
extract lampSceneSwift "$scene_template" > "$work/LampScene.swift"

sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
check() {
  local macos=$1; shift
  xcrun swiftc -typecheck -parse-as-library -swift-version 5 -target arm64-apple-macos$macos -sdk "$sdk" "$@"
}

starters=("$here"/Resources/Starters/*(/))
[ $# -gt 0 ] && starters=("$here/Resources/Starters/$1")
failed=0
for folder in $starters; do
  name="${folder:t}"
  starter="$folder/tree"
  if [ ! -d "$starter" ]; then print -- "✗ $name: no tree (run scripts/fetch-starters.sh)"; failed=1; continue; fi
  library=("$work/LampSupport.swift") macos=14.0
  # Lamp's own files (`Lamp*.swift`) are this checkout's, extracted above or added below, never the tree's copies.
  sources=("$starter"/Sources/**/*.swift(N)); sources=(${sources:#*/Lamp[A-Z]*.swift})
  # A game's starter may have no Swift of its own (Lamp writes the app around its page): nothing to check.
  if (( ! $#sources )); then print -- "○ $name: no Swift to check"; continue; fi
  # A game's or a screen's Swift (Native.swift) answers its page through LampNative, in Lamp's LampPage.swift.
  [ -f "$starter/Web/index.html" ] && library+=("$here/Resources/GameKit/apple/LampPage.swift")
  if grep -qE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)?import[[:space:]]+RealityKit\b' $sources; then
    library+=("$work/LampScene.swift") macos=15.0
  fi
  if check $macos $library $sources 2>"$work/$name.log"; then
    print "✓ $name"
  else
    print "✗ $name"; cat "$work/$name.log"; failed=1
  fi
  widget=("$starter"/Widget/**/*.swift(N)); widget=(${widget:#*/Lamp[A-Z]*.swift})
  if (( $#widget )); then
    if check 14.0 -D LAMP_WIDGET "$work/LampWidgetSupport.swift" $widget 2>"$work/$name-widget.log"; then
      print "✓ $name widget"
    else
      print "✗ $name widget"; cat "$work/$name-widget.log"; failed=1
    fi
  fi
done
# The same file as an iPhone app compiles it, where the `#if os(iOS)` code counts: against the simulator's SDK, when
# this Xcode has it (the Command Line Tools alone don't).
if sdk_ios="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)"; then
  if xcrun swiftc -typecheck -parse-as-library -swift-version 5 -target arm64-apple-ios17.0-simulator -sdk "$sdk_ios" "$work/LampSupport.swift" 2>"$work/ios.log"; then
    print "✓ LampSupport.swift for the iPhone"
  else
    print "✗ LampSupport.swift for the iPhone"; cat "$work/ios.log"; failed=1
  fi
else
  print "○ LampSupport.swift for the iPhone: no simulator SDK here"
fi
exit $failed
