#!/bin/zsh
# Builds build/Lamp Dev.app, the development build (FLAVOR=release: Lamp.app, the one people install; FLAVOR=nightly:
# Lamp Nightly.app, the one made from every change merged).
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
# touching it. release.sh sets FLAVOR=release, or FLAVOR=nightly for "Lamp Nightly": a release in everything but
# its name, icon, folders and update feed, made from every change merged (.github/workflows/nightly.yml).
FLAVOR="${FLAVOR:-dev}"
if [ "$FLAVOR" = release ]; then
  NAME="Lamp"; BUNDLE_ID="dev.lamp.host"; SCHEME="lamp"; HANDLER_RANK="Owner"
elif [ "$FLAVOR" = nightly ]; then
  NAME="Lamp Nightly"; BUNDLE_ID="dev.lamp.host.nightly"; SCHEME="lamp-nightly"; HANDLER_RANK="Owner"
else
  # A worktree's build is an instance of its own (scripts/instance.sh): "Lamp Dev <name>", with its own bundle
  # id, folders, ports and scheme, so builds from two worktrees run side by side (Edition.instance).
  INSTANCE="$(scripts/instance.sh)"
  NAME="Lamp Dev${INSTANCE:+ $INSTANCE}"; BUNDLE_ID="dev.lamp.host.dev${INSTANCE:+.$INSTANCE}"
  SCHEME="lamp-dev${INSTANCE:+-$INSTANCE}"; HANDLER_RANK="Alternate"
fi

# Lamp Dev builds unoptimized, which is several times faster to compile: it's built again and again while a change is
# checked, often by several worktrees at once. Lamp itself, the one people install, is always optimized.
# CONFIG=release ./build.sh optimizes Lamp Dev too, to see how it runs for people.
if [ "$FLAVOR" != dev ]; then CONFIG=release; else CONFIG="${CONFIG:-debug}"; fi
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Lamp"
APP="${BUILD_DIR:-build}/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"   # the process is named after the app, so the two Lamps tell apart in every tool
# Sparkle (updates for release builds). Lamp isn't sandboxed, so Sparkle's XPC services aren't needed.
mkdir -p "$APP/Contents/Frameworks"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
# xwin (MIT or Apache-2.0, github.com/Jake-Shadle/xwin) fetches Microsoft's Windows SDK on the person's Mac, once they've
# accepted Microsoft's license there, for Xbox games (WindowsTools.swift). It publishes no build for a Mac, so it's built
# here from its published crate, pinned and with its own lock file, and cached in vendor/. A release can't go without it.
XWIN_VERSION="0.10.0"
XWIN="vendor/xwin-$XWIN_VERSION/bin/xwin"
if [ ! -x "$XWIN" ]; then
  if PATH="$PATH:$HOME/.cargo/bin" command -v cargo >/dev/null 2>&1; then
    echo "Building xwin $XWIN_VERSION…"
    PATH="$PATH:$HOME/.cargo/bin" cargo install xwin --version "$XWIN_VERSION" --locked --root "vendor/xwin-$XWIN_VERSION" --quiet \
      || { echo "xwin didn't build" >&2; exit 1; }
  elif [ "$FLAVOR" != dev ]; then
    echo "A release needs xwin, which is built with Rust's cargo: install Rust (rustup.rs) first." >&2
    exit 1
  else
    echo "warning: no cargo here, so this Lamp Dev can't fetch the Windows SDK for Xbox games." >&2
  fi
fi
# Lamp's icon, made with the same pipeline as the apps' icons (see Resources/Icon): the classic .icns,
# plus the compiled Icon Composer icon that macOS 26 draws in Liquid Glass.
SPARKLE_KEYS='<key>SUPublicEDKey</key><string>/CAEd8+y31zAUX1M2jdBf+0plXRw1Bv5IEdrX6r6irA=</string>
  <key>SUEnableAutomaticChecks</key><true/>'
if [ "$FLAVOR" = release ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  cp Resources/Assets.car "$APP/Contents/Resources/Assets.car"
  ICON_NAME_KEY='<key>CFBundleIconName</key><string>AppIcon</string>'
  UPDATE_KEYS="<key>SUFeedURL</key><string>https://updates.lamp.dev/appcast.xml</string>
  $SPARKLE_KEYS"
else
  # The same icon with a band across it (orange DEV, or a dark NIGHTLY), so the Lamps tell apart in the Dock. Made
  # once per change of the source icon (no Liquid Glass variant: the classic icon is enough to tell them apart).
  BAND=DEV; [ "$FLAVOR" = nightly ] && BAND=NIGHTLY
  DEV_ICON="${BUILD_DIR:-build}/AppIcon-$BAND.icns"
  if [ ! -f "$DEV_ICON" ] || [ Resources/AppIcon.png -nt "$DEV_ICON" ] || [ scripts/dev-icon.swift -nt "$DEV_ICON" ]; then
    swift scripts/dev-icon.swift Resources/AppIcon.png "$DEV_ICON" "$BAND"
  fi
  cp "$DEV_ICON" "$APP/Contents/Resources/AppIcon.icns"
  ICON_NAME_KEY=''
  if [ "$FLAVOR" = nightly ]; then
    # Lamp Nightly updates itself from its own feed: every nightly, never a release.
    UPDATE_KEYS="<key>SUFeedURL</key><string>https://updates.lamp.dev/nightly/appcast.xml</string>
  $SPARKLE_KEYS"
  else
    UPDATE_KEYS=''   # a development build never updates itself
  fi
fi
# The relay between TV apps and their phones (ControllerRelay): a process of its own, so a game's messages and files
# never pass through Lamp's.
mkdir -p "$APP/Contents/Helpers"
cp "$(dirname "$BIN")/LampRelay" "$APP/Contents/Helpers/LampRelay"
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
cp Resources/vendors.xz "$APP/Contents/Resources/"   # network hardware makers by address prefix, from the IEEE's registry (Vendors, scripts/update-vendors.sh)
rm -rf "$APP/Contents/Resources/Devices" && if [[ -d Resources/Devices ]]; then cp -R Resources/Devices "$APP/Contents/Resources/Devices"; fi   # the device integrations Lamp ships (Integrations)
cp scripts/signing-identity.sh "$APP/Contents/Resources/"   # gives the apps Lamp builds a stable signature
cp -R Resources/ProviderLogos "$APP/Contents/Resources/"
cp -R Resources/Onboarding "$APP/Contents/Resources/"
cp -R Resources/Starters "$APP/Contents/Resources/"   # the wishes Lamp comes with (Starters.swift)
rm -rf "$APP/Contents/Resources/WebLibraries" && cp -R Resources/WebLibraries "$APP/Contents/Resources/"   # libraries device apps may take, such as three.js (DeviceSupport.Library)
cp -R Resources/TVCertificates "$APP/Contents/Resources/"   # Samsung's public certificate authorities a TV app's signatures end in (TizenSigning)
rm -rf "$APP/Contents/Resources/GameKit" && cp -R Resources/GameKit "$APP/Contents/Resources/GameKit"   # what a game is written against, and its hosts (GameKit.swift)
rm -rf "$APP/Contents/Resources/WebHost" && cp -R Resources/WebHost "$APP/Contents/Resources/WebHost"   # the program that shows an Xbox web app in WebView2 (WebHost.swift)
rm -rf "$APP/Contents/Resources/bin"
if [ -x "$XWIN" ]; then mkdir -p "$APP/Contents/Resources/bin" && install -m 755 "$XWIN" "$APP/Contents/Resources/bin/xwin"; fi
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
  <key>NSLocalNetworkUsageDescription</key><string>Lamp finds your TVs and phones on your network and puts your apps on them.</string>
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
sign "$APP/Contents/Resources/LampSidebar"
if [ -f "$APP/Contents/Resources/bin/xwin" ]; then sign "$APP/Contents/Resources/bin/xwin"; fi
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/Helpers/LampRelay"
sign --entitlements Resources/QuickLook.entitlements "$APP/Contents/PlugIns/LampThumbnail.appex"
sign --entitlements Resources/QuickLook.entitlements "$APP/Contents/PlugIns/LampPreview.appex"
# Lamp's player (GameKit.playerSources, Resources/GameKit/apple/LampPlayer.swift): the Mac app around a game's or a
# screen's page, compiled once here and copied for every one Lamp makes, so a game opens in a second and with none of
# Apple's tools. Lamp writes its Swift (what it writes into a game, with nothing of one game in it) and names it by its
# contents; a development build keeps it in .build/player under that name and the compiler's, and builds it again only
# when either changes. A release builds it afresh.
# Not an .app, so the system never lists it as an app of its own. Before the starters, which a game's prebuild copies.
PLAYER_SOURCES="$(mktemp -d)"
"$APP/Contents/MacOS/$NAME" --player-sources "$PLAYER_SOURCES"
PLAYER_VERSION="$(cat "$PLAYER_SOURCES/version")"
PLAYER_KEY=$( { echo "$PLAYER_VERSION"; xcrun swiftc --version 2>&1; xcrun --show-sdk-version; echo "${SDKROOT:-}"; } | shasum | cut -c1-16 )
PLAYER=".build/player/$PLAYER_KEY/LampPlayer.bundle"
if [ "$FLAVOR" != dev ] || [ ! -d "$PLAYER" ]; then
  echo "Building Lamp's player…"
  PLAYER_FLAGS=(-c release --package-path "$PLAYER_SOURCES" -Xlinker -sectcreate -Xlinker __RESTRICT -Xlinker __restrict -Xlinker "$PLAYER_SOURCES/restrict")
  : > "$PLAYER_SOURCES/restrict"   # dyld ignores DYLD_INSERT_LIBRARIES for it, as for every app Lamp builds (GameKit.webBuildSh)
  swift build "${PLAYER_FLAGS[@]}"
  PLAYER_BIN="$(swift build "${PLAYER_FLAGS[@]}" --show-bin-path)/LampPlayer"
  rm -rf .build/player
  PARTIAL="$PLAYER.partial"
  mkdir -p "$PARTIAL/Contents/MacOS"
  cp "$PLAYER_BIN" "$PARTIAL/Contents/MacOS/LampPlayer"
  # It names the SDK it was really built with, as a game's own build does, so macOS draws it as that SDK does.
  if SDKVER="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null)" \
    && MINOS="$(otool -l "$PARTIAL/Contents/MacOS/LampPlayer" | awk '/minos/ {print $2; exit}')" && [ -n "$MINOS" ]; then
    xcrun vtool -set-build-version macos "$MINOS" "$SDKVER" -replace -output "$PARTIAL/Contents/MacOS/LampPlayer" "$PARTIAL/Contents/MacOS/LampPlayer" >/dev/null 2>&1 || true
  fi
  cat > "$PARTIAL/Contents/Info.plist" <<PLAYERPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>LampPlayer</string>
  <key>CFBundleIdentifier</key><string>dev.lamp.player</string>
  <key>CFBundleName</key><string>LampPlayer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LampPlayerVersion</key><string>$PLAYER_VERSION</string>
</dict></plist>
PLAYERPLIST
  mv "$PARTIAL" "$PLAYER"
fi
rm -rf "$PLAYER_SOURCES" "$APP/Contents/Resources/LampPlayer.bundle"
cp -R "$PLAYER" "$APP/Contents/Resources/LampPlayer.bundle"
sign "$APP/Contents/Resources/LampPlayer.bundle"
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
DEFAULT_PREBUILD=0; [ "$FLAVOR" != dev ] && DEFAULT_PREBUILD=1
if [[ "${PREBUILD_STARTERS:-$DEFAULT_PREBUILD}" != 0 ]]; then
  STARTERS="$APP/Contents/Resources/Starters"
  KEY=$( {
    echo "$FLAVOR"; xcrun swiftc --version 2>&1; xcrun --show-sdk-version
    find Resources/Starters Sources/Lamp/Template*.swift Sources/Lamp/Connectors.swift Sources/Lamp/Starters.swift \
      Sources/Lamp/PrebuiltStarters.swift Sources/Lamp/Edition.swift -type f ! -name '.DS_Store' ! -name Prebuilt.zip ! -path '*/Prebuilt/*' | LC_ALL=C sort | xargs shasum
  } | shasum | cut -c1-16 )
  CACHE=".build/prebuilt-starters/$KEY"
  if [ "$FLAVOR" = dev ] && [ -d "$CACHE" ]; then
    echo "Using the starters built before ($KEY)…"
    for cached in "$CACHE"/*(N/); do
      rm -rf "$STARTERS/${cached:t}/Prebuilt"
      cp -R "$cached" "$STARTERS/${cached:t}/Prebuilt"
    done
    PREBUILD_STARTERS=1 "$APP/Contents/MacOS/$NAME" --restamp-starters
  else
    echo "Building the starters Lamp ships…"
    PREBUILD_STARTERS=1 "$APP/Contents/MacOS/$NAME" --prebuild-starters
    if [ "$FLAVOR" = dev ]; then
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
