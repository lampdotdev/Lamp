#!/bin/zsh
# Builds a signed, notarized, stapled DMG that anyone can download and open.
#
# One-time setup (see RELEASING.md):
#   1. A "Developer ID Application" certificate in your login keychain
#   2. Notary credentials saved under a keychain profile:
#        xcrun notarytool store-credentials forge-notary --apple-id you@example.com --team-id ABCDE12345
#
# Usage:
#   ./release.sh 0.2.0
#   SIGN_IDENTITY="Developer ID Application: Roo Code, Inc. (ABCDE12345)" NOTARY_PROFILE=other ./release.sh 0.2.0
set -euo pipefail

VERSION="${1:?usage: ./release.sh <version>}"
HERE="${0:A:h}"
DIST="$HERE/dist"
DMG="$DIST/Forge-$VERSION.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-forge-notary}"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
fi
[[ -n "$SIGN_IDENTITY" ]] || { echo "No Developer ID Application certificate found. See RELEASING.md."; exit 1; }
echo "Signing as: $SIGN_IDENTITY"

# 1. Build + sign the app (hardened runtime, entitlements, secure timestamp)
rm -rf "$DIST" && mkdir -p "$DIST"
# Builds into dist/, not build/, so a release never replaces the Forge you run day to day.
BUILD_DIR="$DIST/build" APP_VERSION="$VERSION" SIGN_IDENTITY="$SIGN_IDENTITY" "$HERE/build.sh"
mv "$DIST/build/Forge.app" "$DIST/" && rmdir "$DIST/build"
codesign --verify --deep --strict "$DIST/Forge.app"

# 2. Package as a DMG with a drag-to-Applications layout
STAGE=$(mktemp -d)
cp -R "$DIST/Forge.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Forge" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp -s "$SIGN_IDENTITY" "$DMG"

if [[ "${SKIP_NOTARIZE:-}" == 1 ]]; then
  echo "Built (not notarized): $DMG"
  exit 0
fi

# 3. Notarize with Apple and staple the ticket so it opens offline without warnings
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# 4. Verify Gatekeeper accepts it
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo
echo "Release ready: $DMG"
echo "Publish:  gh release create v$VERSION \"$DMG\" --title \"Forge $VERSION\" --generate-notes"
