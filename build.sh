#!/bin/zsh
# Builds build/Forge.app (ad-hoc signed, registers the forge:// URL scheme).
set -euo pipefail
cd "$(dirname "$0")"

# The pi coding agent (MIT, github.com/badlogic/pi-mono) is bundled inside Forge.app.
# Pinned version + checksums from the release's SHA256SUMS; downloads are cached in vendor/.
PI_VERSION="1.0.0"
case "$(uname -m)" in
  arm64)  PI_ARCH="arm64"; PI_SHA256="97291e7d2eb2d7d95ab1f67d26de7902302201bc8786c132bbbc9e53fa8526cc" ;;
  x86_64) PI_ARCH="x64";   PI_SHA256="62fb78fcdbc7c0dbd21044dd44bfb3af20df447285bb55e9debf86ff4838776d" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
PI_TARBALL="vendor/pi-$PI_VERSION-darwin-$PI_ARCH.tar.gz"
if [ ! -f "$PI_TARBALL" ] || ! echo "$PI_SHA256  $PI_TARBALL" | shasum -a 256 -c - >/dev/null 2>&1; then
  mkdir -p vendor
  echo "Downloading pi $PI_VERSION ($PI_ARCH)…"
  curl -fL --progress-bar -o "$PI_TARBALL" \
    "https://github.com/badlogic/pi-mono/releases/download/v$PI_VERSION/pi-darwin-$PI_ARCH.tar.gz"
  echo "$PI_SHA256  $PI_TARBALL" | shasum -a 256 -c - >/dev/null || { echo "pi checksum mismatch" >&2; rm -f "$PI_TARBALL"; exit 1; }
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Forge"
APP="build/Forge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Forge"
[ -f Resources/AppIcon.icns ] || swift Resources/make-icon.swift Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
tar xzf "$PI_TARBALL" -C "$APP/Contents/Resources" --exclude 'pi/examples'
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Forge</string>
  <key>CFBundleIdentifier</key><string>dev.forge.host</string>
  <key>CFBundleName</key><string>Forge</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>dev.forge.forgeapp</string>
    <key>UTTypeDescription</key><string>Forge App</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    <key>UTTypeIconFile</key><string>AppIcon</string>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key><array><string>forgeapp</string></array>
    </dict>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Forge App</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key><array><string>dev.forge.forgeapp</string></array>
  </dict></array>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>dev.forge.host</string>
    <key>CFBundleURLSchemes</key><array><string>forge</string></array>
  </dict></array>
</dict></plist>
PLIST
# Sign with a stable local identity so macOS sees every rebuild as the same app
# (Keychain "Always Allow" sticks). Falls back to ad-hoc signing if that isn't possible.
SIGN_ID="$(./scripts/signing-identity.sh 2>/dev/null || echo -)"
# Nested code first (pi and its native module), then the app.
find "$APP/Contents/Resources/pi" -name '*.node' -exec codesign --force -s "$SIGN_ID" {} \; >/dev/null 2>&1
codesign --force -s "$SIGN_ID" "$APP/Contents/Resources/pi/pi" >/dev/null 2>&1
codesign --force -s "$SIGN_ID" "$APP" >/dev/null 2>&1
[ "$SIGN_ID" = "-" ] && echo "Signed ad-hoc (macOS may ask for Keychain access after each rebuild)"
echo "Built $APP"
