# Forge

A Mac app that builds Mac apps. Describe what you want, and Forge has an AI agent write a native SwiftUI app, build it, and open it. Keep chatting to change it live. Every app is a real `.app`, installed in `~/Applications/Forge Apps`.

![Forge icon](Resources/AppIcon.png)

## Requirements

| What | Why | Notes |
|---|---|---|
| macOS 14 (Sonoma) or later | Forge and the apps it generates target macOS 14 | |
| Apple's Command Line Tools (Xcode 15 or later) | Swift compiler, the macOS SDK and `git` | Free. **The full Xcode app is not required**, but works too. |
| An AI provider: an [OpenRouter](https://openrouter.ai/keys) key **or** a signed-in [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Powers the agent that writes the apps, plus AI features inside them | Illustrated icon artwork needs OpenRouter |
| Claude Code CLI | The agent Forge drives | Forge installs it automatically on first launch if it's missing |

No Apple developer account, signing certificate or notarization is needed. Forge and every app it builds are ad-hoc signed and run only on your own Mac.

## Setup

1. **Install the Command Line Tools** (skip this if you already have Xcode, or if `xcode-select -p` prints a path):

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
   - **App-building tools:** if the Command Line Tools aren't there, **Install…** opens Apple's installer.
   - **AI builder:** Claude Code is downloaded automatically in the background.
   - **OpenRouter key:** paste a key from [openrouter.ai/keys](https://openrouter.ai/keys). It's stored in your login Keychain. If you already use Claude Code with your own login, choose **I already use Claude Code** to skip this.

   You can change the key and models later in **Forge → Settings (⌘,)**.

## Using it

- Click **+**, give the app a name and (optionally) describe it. Forge builds it and opens it, usually in under a minute.
- Type changes into the chat. Each change rebuilds and relaunches the app. **Undo** reverts the last change.
- In any generated app, press **⇧⌘E** to jump back to its chat in Forge.
- Generated apps are installed to `~/Applications/Forge Apps/`, so they show up in Spotlight and Launchpad.
- Right-click an app in the sidebar for **New Icon** or **Show in Finder**. Toggle **Show Details** in the toolbar to see what the agent is doing.

## Troubleshooting

- **`xcrun: error: invalid active developer path`**: the Command Line Tools are missing or broken after a macOS update. Run `xcode-select --install`.
- **Build errors mentioning the SDK, with Xcode installed**: point at it explicitly with `sudo xcode-select -s /Applications/Xcode.app`.
- **Keychain asks "Forge wants to use your confidential information"**: rebuilding Forge changes its ad-hoc signature, so macOS asks again. Click **Always Allow**.
- **Apps can't use AI ("Couldn't reach Forge")**: Forge must be running, and port `47811` must be free (check with `lsof -i :47811`).
- **⇧⌘E opens the wrong Forge**: you have more than one `Forge.app` on disk. Open the one you want once, or delete the old one.
- **Old icon in the Dock**: run `killall Dock`.

## How it works

- **Agent loop:** each message runs Claude Code headless (`claude -p`) in the app's folder. It edits `Sources/`, runs `./build.sh` and fixes its own build errors. Forge then commits to the app's git repo, installs the app and relaunches it. **Undo** is `git reset`.
- **Live editing:** every generated app has an **Edit with Forge** command (⇧⌘E) that jumps back to its chat.
- **AI inside apps:** Forge runs a local gateway on `127.0.0.1:47811`. Generated apps call it through `ForgeAI.ask(...)` (text, images, typed JSON) with a per-app token, so the API key never leaves Forge. Per-app usage shows in Forge.
- **Icons:** the AI designs `icon.json` (SF Symbol and gradient). Forge renders it instantly and, with an OpenRouter key, swaps in generated artwork.
- **Providers:** an OpenRouter key (stored in the Keychain) routes everything through OpenRouter, using an isolated Claude Code config. Without a key, Forge falls back to your existing Claude Code login.

## Layout

| Path | What |
|---|---|
| `Sources/Forge/Store.swift` | App state and the build / install / undo loop |
| `Sources/Forge/Agent.swift` | Claude Code invocation, system prompt, stream parsing |
| `Sources/Forge/Template.swift` | Scaffold for new apps, including the generated `ForgeSupport.swift` |
| `Sources/Forge/Gateway.swift` | Local AI gateway and provider calls |
| `Sources/Forge/Icons.swift` | Icon design, rendering and artwork generation |
| `Sources/Forge/Provider.swift` | OpenRouter / Claude login, Keychain |
| `Sources/Forge/Setup.swift` | First-run setup and Settings |
| `Resources/make-icon.swift` | Draws Forge's own icon |

Generated apps live in `~/Library/Application Support/Forge/Apps/<app>/`, each with its own git history.
