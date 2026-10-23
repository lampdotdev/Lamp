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
dev="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null)}"
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
  # A worktree's build is an instance of its own (scripts/instance.sh): "Lamp Dev <name>", with its own bundle
  # id, folders, ports and scheme, so builds from two worktrees run side by side (Edition.instance).
  INSTANCE="$(scripts/instance.sh)"
  NAME="Lamp Dev${INSTANCE:+ $INSTANCE}"; BUNDLE_ID="dev.lamp.host.dev${INSTANCE:+.$INSTANCE}"
  SCHEME="lamp-dev${INSTANCE:+-$INSTANCE}"; HANDLER_RANK="Alternate"
fi

swift build -c release
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
# One generic browser companion, installed through Lamp's setup guide, never generated per app.
if [ "$FLAVOR" = dev ]; then
  mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/BrowserCompanion"
  xcrun swiftc -O -target arm64-apple-macos14 experiments/browser-connector/NativeHost.swift -o "$APP/Contents/Helpers/BrowserNativeHost"
  cp -R experiments/browser-connector/extension "$APP/Contents/Resources/BrowserCompanion/"
  cp experiments/browser-connector/extension-id.txt "$APP/Contents/Resources/BrowserCompanion/"
fi
# Quick Look for shared .lampapp files: the app's icon as their thumbnail, and its picture when Space is pressed.
# macOS shows Quick Look only from sandboxed extensions in an app it knows, so they live in Lamp's PlugIns.
for EXT in LampThumbnail:thumbnail LampPreview:preview; do
  EXE="${EXT%%:*}"; KIND="${EXT##*:}"
  APPEX="$APP/Contents/PlugIns/$EXE.appex"
  mkdir -p "$APPEX/Contents/MacOS"
  cp "$(dirname "$BIN")/$EXE" "$APPEX/Contents/MacOS/$EXE"
  if [ "$KIND" = preview ]; then
    PRINCIPAL=PreviewProvider; EXTRA='<key>QLIsDataBasedPreview</key><true/><key>QLSupportsSearchableItems</key><false/>'
  else
    PRINCIPAL=ThumbnailProvider; EXTRA='<key>QLThumbnailMinimumDimension</key><integer>0</integer>'
  fi
  cat > "$APPEX/Contents/Info.plist" <<APPEXPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID.$KIND</string>
  <key>CFBundleName</key><string>$EXE</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.quicklook.$KIND</string>
    <key>NSExtensionPrincipalClass</key><string>$PRINCIPAL</string>
    <key>NSExtensionAttributes</key><dict>
      <key>QLSupportedContentTypes</key><array><string>dev.lamp.lampapp</string></array>
      $EXTRA
    </dict>
  </dict>
</dict></plist>
APPEXPLIST
done
# The chat Lamp puts inside each Mac app's window (LampSidebar), copied into every app when it's installed.
cp "$(dirname "$BIN")/LampSidebar" "$APP/Contents/Resources/LampSidebar"
cp Resources/THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
install -m 755 Resources/lamp-approve.sh "$APP/Contents/Resources/lamp-approve.sh"
cp Resources/lamp-tools.ts Resources/lamp-tools.json "$APP/Contents/Resources/"
rm -rf "$APP/Contents/Resources/skills" && cp -R Resources/skills "$APP/Contents/Resources/skills"   # guidance the agent opens with read_skill (Skills)   # the agent's tools: pi's extension and the registry both it and the MCP endpoint read
rm -rf "$APP/Contents/Resources/Devices" && if [[ -d Resources/Devices ]]; then cp -R Resources/Devices "$APP/Contents/Resources/Devices"; fi   # the device integrations Lamp ships (Integrations)
cp scripts/signing-identity.sh "$APP/Contents/Resources/"   # gives the apps Lamp builds a stable signature
cp -R Resources/ProviderLogos "$APP/Contents/Resources/"
cp -R Resources/Onboarding "$APP/Contents/Resources/"
cp -R Resources/Starters "$APP/Contents/Resources/"   # the wishes Lamp comes with (Starters.swift)
rm -rf "$APP/Contents/Resources/WebLibraries" && cp -R Resources/WebLibraries "$APP/Contents/Resources/"   # libraries device apps may take, such as Babylon.js (DeviceSupport.Library)
cp -R Resources/TVCertificates "$APP/Contents/Resources/"   # Samsung's public certificate authorities a TV app's signatures end in (TizenSigning)
tar xzf "$PI_TARBALL" -C "$APP/Contents/Resources" --exclude 'pi/examples'
# Only the server and its libraries (symlinks kept), not llama.cpp's other tools.
mkdir -p "$APP/Contents/Resources/llama"
tar xzf "$LLAMA_TARBALL" -C "$APP/Contents/Resources/llama" --strip-components 1 \
  --include "llama-$LLAMA_BUILD/llama-server" --include "llama-$LLAMA_BUILD/LICENSE" --include "llama-$LLAMA_BUILD/*.dylib"
# Apps in Chrome (Lamp Dev only): an app serves its sidebar page at a name of its own under .localhost, and Lamp's
# preview of it loads that page and checks it's the app's. macOS lets an app use plain http to localhost but not to
# names under it without saying so here.
SIDEBAR_ATS=""
if [ "$FLAVOR" = dev ]; then
  SIDEBAR_ATS='<key>NSAppTransportSecurity</key><dict><key>NSExceptionDomains</key><dict><key>localhost</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict></dict></dict>'
fi
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
  <key>NSLocalNetworkUsageDescription</key><string>Lamp finds your TVs and phones on your network and puts your apps on them.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Lamp turns your dictation into text for the prompt box.</string>
  <key>NSAppleEventsUsageDescription</key><string>Lamp lists and switches your browser tabs when one of your apps reads a web page you have open.</string>
  $SIDEBAR_ATS
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
sign "$APP/Contents/Resources/LampSidebar"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
if [ "$FLAVOR" = dev ]; then sign "$APP/Contents/Helpers/BrowserNativeHost"; fi
sign --entitlements Resources/QuickLook.entitlements "$APP/Contents/PlugIns/LampThumbnail.appex"
sign --entitlements Resources/QuickLook.entitlements "$APP/Contents/PlugIns/LampPreview.appex"
# Lamp ships the starters already built (PrebuiltStarters.swift): Lamp builds each one as a person's Mac would, with
# this checkout's LampSupport, once Lamp's own parts are signed and before Lamp is: the stamp on what Lamp builds
# (BuildStamp) covers the signed chat sidebar. Each built app is signed like the rest of Lamp and zipped beside its
# starter's files, so the system never takes it for an app of its own.
# A release does it, afresh. Building them takes minutes and what they're made from (the code Lamp writes into every
# app, above all) changes with most work on Lamp, so a development build leaves them out unless asked
# (PREBUILD_STARTERS=1): a Lamp Dev without them builds the starters on first launch, out of sight, as before they
# shipped built. Asked, it keeps them in .build/prebuilt-starters under a key of what they're made from: the starters,
# that code, the edition and the compiler; a build that finds them there only stamps them for itself
# (--restamp-starters).
DEFAULT_PREBUILD=0; [ "$FLAVOR" = release ] && DEFAULT_PREBUILD=1
if [[ "${PREBUILD_STARTERS:-$DEFAULT_PREBUILD}" != 0 ]]; then
  STARTERS="$APP/Contents/Resources/Starters"
  KEY=$( {
    echo "$FLAVOR"; xcrun swiftc --version 2>&1; xcrun --show-sdk-version
    find Resources/Starters Sources/Lamp/Template*.swift Sources/Lamp/Connectors.swift Sources/Lamp/Starters.swift \
      Sources/Lamp/PrebuiltStarters.swift Sources/Lamp/Edition.swift -type f ! -name '.DS_Store' ! -name Prebuilt.zip ! -path '*/Prebuilt/*' | LC_ALL=C sort | xargs shasum
  } | shasum | cut -c1-16 )
  CACHE=".build/prebuilt-starters/$KEY"
  if [ "$FLAVOR" != release ] && [ -d "$CACHE" ]; then
    echo "Using the starters built before ($KEY)…"
    for cached in "$CACHE"/*(N/); do
      rm -rf "$STARTERS/${cached:t}/Prebuilt"
      cp -R "$cached" "$STARTERS/${cached:t}/Prebuilt"
    done
    PREBUILD_STARTERS=1 "$APP/Contents/MacOS/$NAME" --restamp-starters
  else
    echo "Building the starters Lamp ships…"
    PREBUILD_STARTERS=1 "$APP/Contents/MacOS/$NAME" --prebuild-starters
    if [ "$FLAVOR" != release ]; then
      rm -rf .build/prebuilt-starters
      mkdir -p "$CACHE.partial"
      for prebuilt in "$STARTERS"/*/Prebuilt(N/); do cp -R "$prebuilt" "$CACHE.partial/${prebuilt:h:t}"; done
      mv "$CACHE.partial" "$CACHE"
    fi
  fi
  for prebuilt in "$STARTERS"/*/Prebuilt(N/); do
    for built in "$prebuilt"/*.app; do
      for extension in "$built"/Contents/PlugIns/*.appex(N); do sign "$extension"; done
      sign "$built"
    done
    (cd "$prebuilt:h" && rm -f Prebuilt.zip && ditto -c -k --norsrc --keepParent Prebuilt Prebuilt.zip && rm -rf Prebuilt)
  done
fi
sign "${APP_ENTITLEMENTS[@]}" "$APP"
[ "$SIGN_ID" = "-" ] && echo "Signed ad-hoc (macOS may ask for Keychain access after each rebuild)"
echo "Built $APP"
