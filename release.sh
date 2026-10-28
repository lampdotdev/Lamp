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
# FLAVOR=nightly makes Lamp Nightly (build.sh): its own app and DMG names, beside Lamp's.
FLAVOR="${FLAVOR:-release}"
NAME="Lamp"; DMG_STEM="Lamp"
if [[ "$FLAVOR" == nightly ]]; then NAME="Lamp Nightly"; DMG_STEM="Lamp-Nightly"; fi
DMG="$DIST/$DMG_STEM-$VERSION.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-forge-notary}"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
fi
[[ -n "$SIGN_IDENTITY" ]] || { echo "No Developer ID Application certificate found. See RELEASING.md."; exit 1; }
echo "Signing as: $SIGN_IDENTITY"

# A release without its PostHog project key would quietly count nothing (Sources/Lamp/Analytics.swift).
! grep -q 'static let projectKey = ""' "$HERE/Sources/Lamp/Analytics.swift" \
  || { echo "Analytics.projectKey is empty. Set it to the PostHog project key first."; exit 1; }

# 1. Build + sign the app (hardened runtime, entitlements, secure timestamp)
rm -rf "$DIST" && mkdir -p "$DIST"
# Builds into dist/, not build/, so a release never replaces the Lamp you run day to day.
FLAVOR="$FLAVOR" BUILD_DIR="$DIST/build" APP_VERSION="$VERSION" SIGN_IDENTITY="$SIGN_IDENTITY" "$HERE/build.sh"
mv "$DIST/build/$NAME.app" "$DIST/" && rmdir "$DIST/build"
codesign --verify --deep --strict "$DIST/$NAME.app"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$DIST/notary.log"
  grep -q "status: Accepted" "$DIST/notary.log" || { echo "Notarization failed for $1. Details: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"; exit 1; }
  rm "$DIST/notary.log"
}

# 2. Notarize the app itself and staple its ticket, so Lamp.app opens without a network check
#    even after it's copied out of the DMG.
if [[ "${SKIP_NOTARIZE:-}" != 1 ]]; then
  ditto -c -k --keepParent "$DIST/$NAME.app" "$DIST/Lamp-notarize.zip"
  notarize "$DIST/Lamp-notarize.zip"
  rm "$DIST/Lamp-notarize.zip"
  xcrun stapler staple "$DIST/$NAME.app"
fi

# 3. Package as a DMG with a drag-to-Applications layout: Lamp, an arrow and Applications over the night
#    sky (scripts/dmg-settings.py). dmgbuild writes the window's layout without Finder, so CI gets it too.
python3 -m venv "$DIST/.venv"
"$DIST/.venv/bin/pip" install --quiet --disable-pip-version-check dmgbuild==1.6.7
"$DIST/.venv/bin/dmgbuild" -s "$HERE/scripts/dmg-settings.py" -D app="$DIST/$NAME.app" \
  -D background="$HERE/Resources/DMG/background.tiff" "$NAME" "$DMG"
rm -rf "$DIST/.venv"
codesign --force --timestamp -s "$SIGN_IDENTITY" "$DMG"

if [[ "${SKIP_NOTARIZE:-}" == 1 ]]; then
  echo "Built (not notarized): $DMG"
  exit 0
fi

# 4. Notarize the DMG too and staple it, so the download itself opens offline without warnings
notarize "$DMG"
xcrun stapler staple "$DMG"

# 5. Verify Gatekeeper accepts both, with the tickets stapled
spctl --assess --type open --context context:primary-signature -v "$DMG"
spctl --assess --type execute -v "$DIST/$NAME.app"
xcrun stapler validate "$DIST/$NAME.app"
echo
echo "Release ready: $DMG"
echo "Publish:  gh release create v$VERSION \"$DMG\" --title \"Lamp $VERSION\" --generate-notes"
