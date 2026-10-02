# Forge

A Mac app that builds Mac apps. Describe what you want, and Forge has an AI agent write a native SwiftUI app, build it, and open it. Keep chatting to change it live. Every app is a real `.app`, installed in `~/Applications/Forge Apps`.

![Forge icon](Resources/AppIcon.png)

## Run it

```bash
./build.sh && open build/Forge.app
```

On first launch, Forge walks you through setup: Apple's free command line tools, the Claude Code agent (installed automatically) and an OpenRouter key. No Apple developer account is needed.

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
