# Forge

A Mac app that builds Mac apps. Describe what you want, and Forge has an AI agent write a native SwiftUI app, build it, and open it. Keep chatting to change it live. Every app is a real `.app`, installed in `~/Applications/Forge Apps`.

![Forge icon](Resources/AppIcon.png)

## Requirements

| What | Why | Notes |
|---|---|---|
| macOS 14 (Sonoma) or later | Forge and the apps it generates target macOS 14 | |
| Apple's Command Line Tools (Xcode 15 or later) | Swift compiler, the macOS SDK and `git` | Free. **The full Xcode app is not required**, but works too. |
| An [OpenRouter](https://openrouter.ai/keys) key | Pays for the AI: the agent that writes apps, AI features inside apps, and icon artwork | Added in Forge's welcome screen, stored in the Keychain |

Nothing else needs installing. The coding agent ([pi](https://github.com/badlogic/pi-mono)) is bundled inside `Forge.app`, and `build.sh` downloads a pinned, checksum-verified copy (about 30 MB). No Apple developer account, signing certificate or notarization is needed. Forge and every app it builds are ad-hoc signed and run only on your own Mac.

## Setup

1. **Install the Command Line Tools** (skip this if you already have Xcode, or if `xcode-select -p` prints a path). You need them to build Forge from source. People who get a pre-built `Forge.app` don't, because Forge's welcome screen installs them.

   ```bash
   xcode-select --install
   ```

   macOS shows an installer window, which takes a few minutes. Afterwards, `swift --version` should print Swift 5.9 or newer.

2. **Clone and build:**

   ```bash
   git clone https://github.com/RooCodeInc/Forge.git ~/Code/roo/Forge
   cd ~/Code/roo/Forge
   ./build.sh
   open build/Forge.app
   ```

   The first build takes about a minute. It produces `build/Forge.app`, which you can drag into `/Applications` if you like.

3. **Finish setup in the app.** On first launch, Forge checks for anything missing:
   - **App-building tools:** if the Command Line Tools are missing, Forge opens Apple's installer right away (click **Install**, then **Agree**). It then checks every few seconds and carries on by itself when they're installed, so there's no button to press afterwards.
   - **OpenRouter key:** paste a key from [openrouter.ai/keys](https://openrouter.ai/keys) while the tools install. It's stored in your login Keychain.

   You can change the key and models later in **Forge → Settings (⌘,)**.

## Using it

- Click **+**, give the app a name and (optionally) describe it. Forge builds it and opens it, usually in under a minute.
- Type changes into the chat. Each change rebuilds and relaunches the app. **Undo** reverts the last change.
- In any generated app, press **⇧⌘E** to jump back to its chat in Forge.
- Generated apps are installed to `~/Applications/Forge Apps/`, so they show up in Spotlight and Launchpad.
- Right-click an app in the sidebar for **New Icon** or **Show in Finder**. Toggle **Show Details** in the toolbar to see what the agent is doing.

## Troubleshooting

- **`xcrun: error: invalid active developer path`**: the Command Line Tools are missing or broken after a macOS update. Run `xcode-select --install`.
- **Builds fail with "You have not agreed to the Xcode license"** (full Xcode only): run `sudo xcodebuild -license accept`.
- **`Downloading pi` fails during `./build.sh`**: GitHub must be reachable. The download is cached in `vendor/` afterwards.
- **Build errors mentioning the SDK, with Xcode installed**: point at it explicitly with `sudo xcode-select -s /Applications/Xcode.app`.
- **Keychain asks "Forge wants to use your confidential information"**: rebuilding Forge changes its ad-hoc signature, so macOS asks again. Click **Always Allow**.
- **Apps can't use AI ("Couldn't reach Forge")**: Forge must be running, and port `47811` must be free (check with `lsof -i :47811`).
- **⇧⌘E opens the wrong Forge**: you have more than one `Forge.app` on disk. Open the one you want once, or delete the old one.
- **Old icon in the Dock**: run `killall Dock`.

## How it works

- **Agent loop:** each message runs the bundled [pi](https://github.com/badlogic/pi-mono) agent in JSON mode in the app's folder, with file tools only (read, edit, write, grep, find, ls) and no shell. Forge then runs `./build.sh` itself and sends any compiler errors back to pi, up to three times. After that it commits to the app's git repo, installs the app and relaunches it. Each app keeps one pi conversation, so the agent remembers earlier requests. **Undo** is `git reset` and starts a fresh conversation.
- **Live editing:** every generated app has an **Edit with Forge** command (⇧⌘E) that jumps back to its chat.
- **AI inside apps:** Forge runs a local gateway on `127.0.0.1:47811`. Generated apps call it through `ForgeAI.ask(...)` (text, images, typed JSON) with a per-app token, so the API key never leaves Forge. Per-app usage shows in Forge.
- **Icons:** the AI designs `icon.json` (SF Symbol and gradient). Forge renders it instantly and, with an OpenRouter key, swaps in generated artwork.
- **Provider:** everything goes through OpenRouter with the one key in the Keychain. pi uses its own config folder (`~/Library/Application Support/Forge/pi`), with update checks and telemetry off, so it never touches a pi you run yourself.

## Layout

| Path | What |
|---|---|
| `Sources/Forge/Store.swift` | App state and the build / install / undo loop |
| `Sources/Forge/Agent.swift` | pi invocation, system prompt, JSON event parsing, shell helper |
| `Sources/Forge/Template.swift` | Scaffold for new apps, including the generated `ForgeSupport.swift` |
| `Sources/Forge/Gateway.swift` | Local AI gateway and provider calls |
| `Sources/Forge/Icons.swift` | Icon design, rendering and artwork generation |
| `Sources/Forge/Provider.swift` | OpenRouter models, friendly errors, Keychain |
| `Sources/Forge/Setup.swift` | First-run setup and Settings |
| `Resources/make-icon.swift` | Draws Forge's own icon |
| `Resources/THIRD_PARTY_NOTICES.md` | Licence for the bundled pi agent (MIT) |

Generated apps live in `~/Library/Application Support/Forge/Apps/<app>/`, each with its own git history.
