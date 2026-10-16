#!/bin/zsh
# Type-checks the wishes Lamp ships with (Resources/Starters) against this checkout's LampSupport.swift, as
# a build would compile them: the app's Sources with the library, and a widget's Widget/ with its own file.
#
#   scripts/check-starters.sh            every starter
#   scripts/check-starters.sh today      one, by folder name
#
# Run it after changing LampSupport.swift in Template.swift: a starter that no longer compiles would greet a
# new person with a build failure.
set -euo pipefail
here="${0:A:h}/.."
template="$here/Sources/Lamp/Template.swift"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A raw string of Template.swift, from its `static let <name> = #"""` line to the `"""#` that ends it, with its
# placeholders filled by stand-ins (only their types matter here).
extract() {
  awk -v start="static let $1 = #\"\"\"" '
    index($0, start) { on = 1; next }
    on && /^ *"""#$/ { exit }
    on { print }' "$template" | sed -E 's/\{\{(PORT|WIDGET_PORT)\}\}/7777/g; s/\{\{[A-Z_]+\}\}/stand-in/g'
}
extract lampSupportSwift > "$work/LampSupport.swift"
extract lampWidgetSupportSwift > "$work/LampWidgetSupport.swift"

sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
check() {
  xcrun swiftc -typecheck -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 -sdk "$sdk" "$@"
}

starters=("$here"/Resources/Starters/*(/))
[ $# -gt 0 ] && starters=("$here/Resources/Starters/$1")
failed=0
for starter in $starters; do
  name="${starter:t}"
  if check "$work/LampSupport.swift" "$starter"/Sources/**/*.swift(N) 2>"$work/$name.log"; then
    print "✓ $name"
  else
    print "✗ $name"; cat "$work/$name.log"; failed=1
  fi
  if [ -d "$starter/Widget" ]; then
    if check -D LAMP_WIDGET "$work/LampWidgetSupport.swift" "$starter"/Widget/**/*.swift(N) 2>"$work/$name-widget.log"; then
      print "✓ $name widget"
    else
      print "✗ $name widget"; cat "$work/$name-widget.log"; failed=1
    fi
  fi
done
exit $failed
