#!/bin/zsh
# Builds build/Lamp Dev.app, the development build (FLAVOR=release: Lamp.app, the one people install).
#
# Local builds are signed with a self-signed "Forge Local Signing" identity (see scripts/signing-identity.sh).
# Releases set SIGN_IDENTITY to a Developer ID certificate (see release.sh): everything is then signed with
# hardened runtime, entitlements and a secure timestamp, ready for notarization.
#   APP_VERSION=0.2.0 SIGN_IDENTITY="Developer ID Application: …" ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

# The version. Releases pass APP_VERSION (the tag). A local build takes it from git: "0.3.1" on the
# release tag itself, "0.3.1+6" six commits after it, so a build from source says which release it's
# ahead of. APP_BUILD is the all-numeric form macOS compares when two copies of Lamp are on disk.
if [[ -z "${APP_VERSION:-}" ]]; then
  described="$(git describe --tags --match 'v[0-9]*' 2>/dev/null || true)"   # v0.3.1 or v0.3.1-6-g8065f74
  if [[ "$described" =~ '^v([0-9.]+)(-([0-9]+)-g[0-9a-f]+)?$' ]]; then
    APP_VERSION="${match[1]}${match[3]:++${match[3]}}"
    APP_BUILD="${match[1]}${match[3]:+.${match[3]}}"
  else
    APP_VERSION="0.1"   # no git, or no release tags fetched
  fi
fi
APP_BUILD="${APP_BUILD:-$APP_VERSION}"

# The pi coding agent (MIT, github.com/badlogic/pi-mono) is bundled inside Lamp.app.
# Pinned version + checksums from the release's SHA256SUMS; downloads are cached in vendor/.
PI_VERSION="1.0.0"
case "$(uname -m)" in
  arm64)  PI_ARCH="arm64"; PI_SHA256="97291e7d2eb2d7d95ab1f67d26de7902302201bc8786c132bbbc9e53fa8526cc" ;;
  x86_64) PI_ARCH="x64";   PI_SHA256="62fb78fcdbc7c0dbd21044dd44bfb3af20df447285bb55e9debf86ff4838776d" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
PI_TARBALL="vendor/pi-$PI_VERSION-darwin-$PI_ARCH.tar.gz"

# llama.cpp's server runs downloaded models on this Mac (MIT, github.com/ggml-org/llama.cpp).
LLAMA_BUILD="b11346"
case "$(uname -m)" in
  arm64)  LLAMA_ARCH="arm64"; LLAMA_SHA256="25cefd22cf708a14eacea623327a2320fa07493a29b4c37bf3376623de581553" ;;
  x86_64) LLAMA_ARCH="x64";   LLAMA_SHA256="1f91f85611d1573c53409c99d96d43451cd89e928ce1882b6739fd1cf7befaf2" ;;
esac
LLAMA_TARBALL="vendor/llama-$LLAMA_BUILD-bin-macos-$LLAMA_ARCH.tar.gz"
if [ ! -f "$LLAMA_TARBALL" ] || ! echo "$LLAMA_SHA256  $LLAMA_TARBALL" | shasum -a 256 -c - >/dev/null 2>&1; then
  mkdir -p vendor
  echo "Downloading llama.cpp $LLAMA_BUILD ($LLAMA_ARCH)…"
  curl -fL --progress-bar -o "$LLAMA_TARBALL" \
    "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD/llama-$LLAMA_BUILD-bin-macos-$LLAMA_ARCH.tar.gz"
  echo "$LLAMA_SHA256  $LLAMA_TARBALL" | shasum -a 256 -c - >/dev/null || { echo "llama.cpp checksum mismatch" >&2; rm -f "$LLAMA_TARBALL"; exit 1; }
fi
if [ ! -f "$PI_TARBALL" ] || ! echo "$PI_SHA256  $PI_TARBALL" | shasum -a 256 -c - >/dev/null 2>&1; then
  mkdir -p vendor
  echo "Downloading pi $PI_VERSION ($PI_ARCH)…"
  curl -fL --progress-bar -o "$PI_TARBALL" \
    "https://github.com/badlogic/pi-mono/releases/download/v$PI_VERSION/pi-darwin-$PI_ARCH.tar.gz"
  echo "$PI_SHA256  $PI_TARBALL" | shasum -a 256 -c - >/dev/null || { echo "pi checksum mismatch" >&2; rm -f "$PI_TARBALL"; exit 1; }
fi

# The macOS 27 SDK makes @State a macro, and its compiler plugin only ships with full Xcode.
# With just the Command Line Tools, build against the newest installed SDK that doesn't need it.
# (Lamp does the same for the apps it builds: Shell.compatibleSDK in Sources/Lamp/Agent.swift.)
dev="$(xcode-select -p 2>/dev/null)"
if [ -z "${SDKROOT:-}" ] && [ -d "$dev/SDKs" ] && [ ! -e "$dev/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
  for sdk in "$dev"/SDKs/MacOSX*.sdk(/NnOn); do
    if ! grep -qs StateMacro /dev/null "$sdk"/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/*-macos.swiftinterface(N); then
      export SDKROOT="$sdk"; break
    fi
  done
fi

# Which Lamp this is (see Sources/Lamp/Edition.swift). A build from source is "Lamp Dev": its own name,
# icon, bundle id, folders, ports and URL scheme, so it lives beside the Lamp you installed without
# touching it. release.sh sets FLAVOR=release.
FLAVOR="${FLAVOR:-dev}"
if [ "$FLAVOR" = release ]; then
  NAME="Lamp"; BUNDLE_ID="dev.lamp.host"; SCHEME="lamp"; HANDLER_RANK="Owner"
else
  NAME="Lamp Dev"; BUNDLE_ID="dev.lamp.host.dev"; SCHEME="lamp-dev"; HANDLER_RANK="Alternate"
fi

swift build -c release -j "${BUILD_JOBS:-2}"
BIN="$(swift build -c release --show-bin-path)/Lamp"
APP="${BUILD_DIR:-build}/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"   # the process is named after the app, so the two Lamps tell apart in every tool
# Sparkle (updates for release builds). Lamp isn't sandboxed, so Sparkle's XPC services aren't needed.
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
# Lamp's icon, made with the same pipeline as the apps' icons (see Resources/Icon): the classic .icns,
# plus the compiled Icon Composer icon that macOS 26 draws in Liquid Glass.
if [ "$FLAVOR" = release ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  cp Resources/Assets.car "$APP/Contents/Resources/Assets.car"
  ICON_NAME_KEY='<key>CFBundleIconName</key><string>AppIcon</string>'
  UPDATE_KEYS='<key>SUFeedURL</key><string>https://updates.lamp.dev/appcast.xml</string>
  <key>SUPublicEDKey</key><string>/CAEd8+y31zAUX1M2jdBf+0plXRw1Bv5IEdrX6r6irA=</string>
  <key>SUEnableAutomaticChecks</key><true/>'
else
  # The same icon with a DEV banner across it, so the two Lamps tell apart in the Dock. Made once per
  # change of the source icon (no Liquid Glass variant: the classic icon is enough to tell them apart).
  DEV_ICON="${BUILD_DIR:-build}/AppIcon-Dev.icns"
  if [ ! -f "$DEV_ICON" ] || [ Resources/AppIcon.png -nt "$DEV_ICON" ] || [ scripts/dev-icon.swift -nt "$DEV_ICON" ]; then
    swift scripts/dev-icon.swift Resources/AppIcon.png "$DEV_ICON"
  fi
  cp "$DEV_ICON" "$APP/Contents/Resources/AppIcon.icns"
  ICON_NAME_KEY=''
  UPDATE_KEYS=''   # a development build never updates itself
fi
cp Resources/THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
install -m 755 Resources/lamp-approve.sh "$APP/Contents/Resources/lamp-approve.sh"
cp Resources/lamp-tools.ts Resources/lamp-tools.json "$APP/Contents/Resources/"   # the agent's tools: pi's extension and the registry both it and the MCP endpoint read
cp scripts/signing-identity.sh "$APP/Contents/Resources/"   # gives the apps Lamp builds a stable signature
cp -R Resources/ProviderLogos "$APP/Contents/Resources/"
cp -R Resources/Onboarding "$APP/Contents/Resources/"
tar xzf "$PI_TARBALL" -C "$APP/Contents/Resources" --exclude 'pi/examples'
# Only the server and its libraries (symlinks kept), not llama.cpp's other tools.
mkdir -p "$APP/Contents/Resources/llama"
tar xzf "$LLAMA_TARBALL" -C "$APP/Contents/Resources/llama" --strip-components 1 \
  --include "llama-$LLAMA_BUILD/llama-server" --include "llama-$LLAMA_BUILD/LICENSE" --include "llama-$LLAMA_BUILD/*.dylib"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  $ICON_NAME_KEY
  $UPDATE_KEYS
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>dev.lamp.lampapp</string>
    <key>UTTypeDescription</key><string>Lamp App</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    <key>UTTypeIconFile</key><string>AppIcon</string>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key><array><string>lampapp</string></array>
    </dict>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Lamp App</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>$HANDLER_RANK</string>
    <key>LSItemContentTypes</key><array><string>dev.lamp.lampapp</string></array>
  </dict></array>
  <key>NSMicrophoneUsageDescription</key><string>Lamp listens to your microphone when you dictate a change.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Lamp turns your dictation into text for the prompt box.</string>
  <key>NSAppleEventsUsageDescription</key><string>Lamp lists and switches your browser tabs when one of your apps reads a web page you have open.</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
    <key>CFBundleURLSchemes</key><array><string>$SCHEME</string></array>
  </dict></array>
</dict></plist>
PLIST
# Local builds: a stable self-signed identity, so macOS sees every rebuild as the same app.
# Falls back to ad-hoc signing if that isn't possible.
SIGN_ID="${SIGN_IDENTITY:-$(./scripts/signing-identity.sh 2>/dev/null || echo -)}"
if [[ "$SIGN_ID" == "Developer ID Application:"* ]]; then
  # Release: hardened runtime + secure timestamp (both required for notarization).
  SIGN=(codesign --force --timestamp --options runtime -s "$SIGN_ID")
  PI_ENTITLEMENTS=(--entitlements Resources/pi.entitlements)
  APP_ENTITLEMENTS=(--entitlements Resources/Lamp.entitlements)
  QUIET=/dev/stdout
elif [[ "$SIGN_ID" != "-" ]]; then
  # Local: Lamp's own keychain, which signing-identity.sh unlocks, so codesign never asks.
  SIGN=(codesign --force --keychain "$HOME/Library/Application Support/Lamp/Signing/lamp-signing.keychain-db" -s "$SIGN_ID")
  PI_ENTITLEMENTS=()
  APP_ENTITLEMENTS=()
  QUIET=/dev/null
else
  SIGN=(codesign --force -s "$SIGN_ID")
  PI_ENTITLEMENTS=()
  APP_ENTITLEMENTS=()
  QUIET=/dev/null
fi
# Signs one item. codesign's routine chatter stays quiet for local builds, but a failure always says what
# went wrong, instead of the script stopping silently partway.
sign() {
  local output
  if ! output="$("${SIGN[@]}" "$@" 2>&1)"; then
    echo "$output" >&2
    echo "Couldn't sign ${@[-1]} with \"$SIGN_ID\". For an unsigned build to try things out: SIGN_IDENTITY=- ./build.sh" >&2
    return 1
  fi
  [[ -n "$output" ]] && echo "$output" >$QUIET
  return 0
}
# Nested code first (pi's native module, llama.cpp's libraries and server, pi), then the app.
find "$APP/Contents/Resources/pi" -name '*.node' -print0 | while IFS= read -r -d '' item; do sign "$item"; done
find "$APP/Contents/Resources/llama" -type f \( -name '*.dylib' -o -name 'llama-server' \) -print0 |
  while IFS= read -r -d '' item; do sign "$item"; done
sign "${PI_ENTITLEMENTS[@]}" "$APP/Contents/Resources/pi/pi"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "${APP_ENTITLEMENTS[@]}" "$APP"
[ "$SIGN_ID" = "-" ] && echo "Signed ad-hoc (macOS may ask for Keychain access after each rebuild)"
echo "Built $APP"
