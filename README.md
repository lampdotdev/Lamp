# Forge

A Mac app that builds Mac apps. Describe what you want, and Forge has an AI agent write a native SwiftUI app, build it, and open it. Keep chatting to change it live. Every app is a real `.app`, installed in `~/Applications/Forge Apps`.

![Forge icon](Resources/AppIcon.png)

## Requirements

| What | Why | Notes |
|---|---|---|
| macOS 14 (Sonoma) or later | Forge and the apps it generates target macOS 14 | |
| Apple's Command Line Tools (Xcode 15 or later) | Swift compiler, the macOS SDK and `git` | Free. **The full Xcode app is not required**, but works too. With Xcode 26, icons get native Liquid Glass rendering on macOS 26. |
| An AI to build with | Writes the apps | An [OpenRouter](https://openrouter.ai/keys) key is easiest. You can also use ~20 other providers, Claude Code, Codex or opencode if installed, or a model running on your Mac. See [Choosing the AI](#choosing-the-ai). |
| An OpenRouter key (optional) | Image generation, icon artwork, and the fast in-app AI models | Without one, apps' text AI uses whatever builds them |
| A TypeSafe key (optional) | Decisions in apps, directly from TypeSafe | Jev is also available through an OpenRouter key |

Nothing else needs installing. The coding agent ([pi](https://github.com/badlogic/pi-mono)) and llama.cpp's model server are bundled inside `Forge.app`; `build.sh` downloads pinned, checksum-verified copies (about 40 MB together). No Apple developer account, signing certificate or notarization is needed. Forge and every app it builds are ad-hoc signed and run only on your own Mac.

## Download

Signed, notarized builds are on [GitHub Releases](https://github.com/RooCodeInc/Forge/releases): open the DMG and drag Forge to Applications. To cut a release, see [RELEASING.md](RELEASING.md).

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

   The first build takes about a minute. It also creates a self-signed **Forge Local Signing** certificate in your login keychain (see `scripts/signing-identity.sh`). That gives every build the same signature. It's only used to sign Forge on your Mac. It produces `build/Forge.app`, which you can drag into `/Applications` if you like.

3. **Finish setup in the app.** On first launch, Forge checks for anything missing:
   - **App-building tools:** if the Command Line Tools are missing, Forge opens Apple's installer right away (click **Install**, then **Agree**). It then checks every few seconds and carries on by itself when they're installed, so there's no button to press afterwards.
   - **The AI that builds your apps:** paste an OpenRouter key from [openrouter.ai/keys](https://openrouter.ai/keys) while the tools install. Alternatively, click Claude Code, Codex or opencode if they're installed, **A model on this Mac…**, or **Other providers…**. Keys are stored per provider. Releases signed with an Apple Developer ID keep them in your login Keychain. Local builds have no Team ID, and macOS would ask for Keychain access again after every rebuild, so they keep them in `~/Library/Application Support/Forge/keys.json`, readable only by your user account.

   You can change the key and models later in **Forge → Settings (⌘,)**.

## Using it

- Click **New App** at the bottom of the app list, give the app a name and (optionally) describe it. Forge builds it and opens it, usually in under a minute.
- Type changes into the chat. Each change rebuilds and relaunches the app. **Undo** reverts the last change. **Return** sends, and **Shift-Return** starts a new line.
- While a new app's first version is built, the chat shows a build card: the app's name and icon as they're chosen, the agent's plan with each part ticked off as it's written, what it's doing right now, and at the end a picture of the app's real window. Later changes show one line with the current step and the time so far.
- You can keep typing while Forge works. Messages sent in the meantime wait in the chat (click the ✕ to take one back) and go out together as the next change.
- Attach screenshots, mockups, logos, data files or documents with the paperclip, by dropping them on the chat, or by pasting (a screenshot copied with ⌃⇧⌘4 pastes as an image). The agent sees images and small text files directly. Attachments are saved in the app's `Attachments/` folder and bundled inside the app, where code loads them with `ForgeAssets.url/image/text("name")`. Shared apps include them.
- In any generated app, press **⇧⌘E** to jump back to its chat in Forge.
- Generated apps are installed to `~/Applications/Forge Apps/`, so they show up in Spotlight and Launchpad.
- Double-click an app in the sidebar to build and open it. A blue dot means its chat has a reply you haven't seen. The buttons at the bottom of the sidebar switch between a list and icon tiles.
- Right-click an app in the sidebar for **Run**, **New Icon**, **Show in Finder**, **Share…** or **Export…**. Toggle **Agent Details** (the wrench and screwdriver) in the toolbar to see what the agent is doing.

## Sharing apps

Click **Share** (the toolbar button), or right-click an app and choose **Share…**, to send it through AirDrop, Messages, Mail and so on. You can also use **Export…** to save the file. Apps travel as small `.forgeapp` files containing the app's Swift code, `APP.md`, `icon.json` and icon artwork. Your chat, tokens, agent sessions and git history are never included.

The recipient double-clicks the file, or uses **File → Import Shared App… (⌘O)**. Before anything is built, Forge shows a review:

- **A fixed checklist** of what the code uses: shell commands, network, AppleScript, Keychain, SSH keys or browser data, deleting files, camera, screen capture, background items, runtime code loading, encoded blobs, and AI. This is plain text search, so comments in the code can't talk it out of anything.
- **An AI review** using the building model. It summarises what the app does, what it can access and any concerns, with a low, medium or high risk rating. It's told to treat the code as untrusted and ignore any instructions in it.

High-risk apps default to **Cancel**. When imported, the shared code is rebuilt with Forge's own `Package.swift`, `build.sh` and `ForgeSupport.swift`, so nothing in the file runs during the build. The app runs only when opened, and becomes a normal app the recipient can keep editing. The review is a guide, not a guarantee: only open apps from people you trust.

## Choosing the AI

**Forge → Settings (⌘,) → AI** chooses what builds your apps:

- **Forge's built-in agent (pi)** with any of these:
  - **An API key** for OpenRouter, Anthropic, OpenAI, Google Gemini, DeepSeek, Mistral, xAI, Groq, Cerebras, Together, Fireworks, Hugging Face, Vercel AI Gateway, Moonshot, Z.ai, MiniMax or NVIDIA. Pick any model from that provider's list; it's searchable.
  - **On this Mac (local models).** **Settings → Local Models** lists every model Forge can run. These include models already in the shared Hugging Face cache (`~/.cache/huggingface/hub`) or in Local's folder, so models downloaded for Local show up without downloading again. Forge's own downloads (a list sized to your Mac's memory, or any GGUF repo) go into that same cache, in the standard `huggingface_hub` layout.
    - **GGUF models** run on Forge's bundled llama.cpp server (`127.0.0.1:47812`, router mode, loading models on demand). It reads them through a folder of symlinks (`~/Library/Application Support/Forge/Router`), so nothing is copied.
    - **MLX models** (like the ones Local uses) run on `mlx_lm.server` (`127.0.0.1:47813`) if it's installed (`uv tool install mlx-lm`).
    - Servers start when needed and stop when Forge quits.
  - **Ollama or LM Studio**, if they're running. Their models appear automatically.
  - **My pi setup:** your own `~/.pi/agent`, including any subscriptions you've signed into with pi's `/login` (Claude Pro/Max, ChatGPT, GitHub Copilot and others).
- **Claude Code, Codex or opencode**, if installed. Forge uses their existing sign-in. It runs them with file editing allowed and the shell turned off (sandboxed, for Codex), and builds the app itself.

With pi, Forge's rules go in the system prompt. Claude Code gets them through `--append-system-prompt`, and Codex and opencode get them at the top of each request. Attachments are passed natively where the tool supports it.

Local models are slower and much less capable than the best cloud models for whole apps; small ones can loop. Forge stops an agent that repeats the same step 6 times or makes more than 150 tool calls in one turn, and **Stop** cancels a turn at any time.

## Troubleshooting

- **`xcrun: error: invalid active developer path`**: the Command Line Tools are missing or broken after a macOS update. Run `xcode-select --install`.
- **Builds fail with "You have not agreed to the Xcode license"** (full Xcode only): run `sudo xcodebuild -license accept`.
- **Builds fail with "plugin for module 'SwiftUIMacros' not found"**: the macOS 27 SDK needs a compiler plugin that only ships with full Xcode. With just the Command Line Tools, Forge builds against the newest older SDK they include, so this only happens when there isn't one. Install Xcode, or an older Command Line Tools SDK.
- **`Downloading pi` fails during `./build.sh`**: GitHub must be reachable. The download is cached in `vendor/` afterwards.
- **Build errors mentioning the SDK, with Xcode installed**: point at it explicitly with `sudo xcode-select -s /Applications/Xcode.app`.
- **Keychain asks "Forge wants to access key dev.forge.host"**: Forge is moving an OpenRouter key saved by an older build out of the Keychain. Allow it once. Local builds don't use the Keychain after that.
- **A local model won't start**: check `~/Library/Logs/Forge/llama-server.log` (GGUF) or `mlx-server.log` (MLX). The model may need more memory than the Mac has; pick a smaller one.
- **Claude Code, Codex or opencode errors**: Forge shows their message. Make sure the tool works on its own in Terminal first: you're signed in, and it's up to date (an old Codex can't use new models, and opencode's free tier only works inside opencode).
- **Apps can't use AI ("Couldn't reach Forge")**: Forge must be running, and port `47811` must be free (check with `lsof -i :47811`).
- **⇧⌘E opens the wrong Forge**: you have more than one `Forge.app` on disk. Open the one you want once, or delete the old one.
- **Old icon in the Dock**: run `killall Dock`.

## How it works

- **Agent loop:** each message runs the bundled [pi](https://github.com/badlogic/pi-mono) agent in JSON mode in the app's folder, with file tools only (read, edit, write, grep, find, ls) and no shell. Forge then runs `./build.sh` itself and sends any compiler errors back to pi, up to three times. After that it commits to the app's git repo, installs the app and relaunches it. Each app keeps one pi conversation, so the agent remembers earlier requests. **Undo** is `git reset` and starts a fresh conversation.
- **Seeing the app run:** the agent can't run anything, so Forge shows it what happened. Every app saves what it prints (`print`, `NSLog`, SwiftUI runtime warnings, fatal errors, failed AI calls) to `.forge/runtime/log.txt` in its project, and the agent reads that when you say something doesn't work. If an app quits within a few seconds of opening, Forge sends the macOS crash report and the last lines it printed back to the agent, up to twice, the same way it does with compiler errors. A crash later on is mentioned to the agent with your next message. Apps also save a picture of their own windows (`.forge/runtime/screenshot.png`) shortly after opening and whenever you switch away from them, so an agent that can view images sees what you were looking at. The app draws the picture itself, so there's no screen recording permission. The built-in agent can also check its own work mid-turn: its `look_at_app` tool has Forge build the app with the changes so far, open it behind your windows, and hand back the pictures, what the app printed and any build errors or crash. It gets three looks per request. Claude Code, Codex and opencode don't have this tool.
- **Live editing:** every generated app has an **Edit with Forge** command (⇧⌘E) that jumps back to its chat.
- **AI inside apps:** Forge runs a local gateway on `127.0.0.1:47811`. Generated apps call it through `ForgeAI.ask(...)` (text, images, typed JSON) and `ForgeAI.makeImage(...)` / `editImage(...)` / `editImages(...)` (create, edit or combine pictures with the image model from Settings), plus decisions: `ForgeAI.isTrue` / `choose` / `rate` / `decide` (fast typed judgments with probabilities and confidence from a decision model, TypeSafe's Jev, via OpenRouter or TypeSafe directly; set in Settings → AI → Decisions) with a per-app token, so the API key never leaves Forge. Per-app usage shows in Forge.
- **Icons:** icons follow Apple's layered structure: one object on a calm background. The AI only chooses the object (`icon.json`: a `subject`, an SF Symbol and a background from a fixed palette). Forge controls the grid, margins and lighting. The icon starts as the SF Symbol. Forge then generates three artwork candidates of the object alone, cuts each out with Vision on the device, and has a vision model choose the one that best fits the guidelines. If the full **Xcode 26** app is installed, Forge also writes an Icon Composer document (`.forge/AppIcon.icon`) and compiles it with `actool`, so macOS 26 shows the icon in Liquid Glass with dark and tinted variants. With only the Command Line Tools, Forge draws the layers itself.
- **Providers:** see [Choosing the AI](#choosing-the-ai). pi uses its own config folder (`~/Library/Application Support/Forge/pi`), with update checks and telemetry off, so it never touches a pi you run yourself (unless you choose **My pi setup**). Forge registers local and Ollama/LM Studio models with pi through that folder's `models.json`. In-app AI uses OpenRouter when there's a key, and otherwise falls back to the building model: through llama.cpp, Ollama or LM Studio directly, or a one-shot pi call. Image generation needs OpenRouter.

## Layout

| Path | What |
|---|---|
| `Sources/Forge/Store.swift` | App state and the build / install / undo loop |
| `Sources/Forge/Agent.swift` | pi invocation, system prompt, JSON event parsing, shell helper |
| `Sources/Forge/Engines.swift` | Engine choice (pi, Claude Code, Codex, opencode), commands and parsers, finding installed tools |
| `Sources/Forge/LocalModels.swift` | Hugging Face downloads, the bundled llama.cpp server, Ollama / LM Studio detection |
| `Sources/Forge/Composer.swift` | Chat input (Return / Shift-Return, paste and drop) and attachments |
| `Sources/Forge/Template.swift` | Scaffold for new apps, including the generated `ForgeSupport.swift` |
| `Sources/Forge/Runtime.swift` | What Forge sees of a running app: its log and its crash reports |
| `Sources/Forge/Gateway.swift` | Local AI gateway and provider calls |
| `Sources/Forge/Icons.swift` | Icon design, rendering and artwork generation |
| `Sources/Forge/Provider.swift` | Provider catalog, friendly errors, per-provider key storage (Keychain or private file) |
| `Sources/Forge/Setup.swift` | First-run setup and Settings |
| `Sources/Forge/Sharing.swift` | `.forgeapp` export and import, and the import review (checklist + AI) |
| `Resources/forge-tools.ts` | The agent's `look_at_app` and `plan` tools (a pi extension) |
| `Resources/make-icon.swift` | Draws Forge's own icon |
| `Resources/THIRD_PARTY_NOTICES.md` | Licences for the bundled pi agent and llama.cpp (both MIT) |

Generated apps live in `~/Library/Application Support/Forge/Apps/<app>/`, each with its own git history.
