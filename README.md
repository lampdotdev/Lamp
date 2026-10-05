# Forge

**A Mac app that builds the apps your work is missing.**

Describe what you need, and Forge builds a real Mac app (with AI inside when it helps) that you can keep using, change whenever you like, and share. Make a tool for one annoying task, then keep improving it until it works exactly your way.

![Forge icon](Resources/AppIcon.png)

Some things people build with it:

- **Downloads Tidy:** a menu bar app that groups everything in Downloads by what it is (receipts, installers, screenshots), suggests clear names, and only moves files once you approve.
- **Screenshot Notes:** drop screenshots on it and it pulls out the text and key details (who, what, dates, amounts) into a searchable list.
- **Reading Queue:** drop in PDFs and links, describe what you're working on, and it ranks them by what matters, with a one-line summary and a reason for each.

Each one is a real `.app` in `~/Applications/Forge Apps`, with **Edit with Forge (⇧⌘E)** in its menu for when you want it to work differently. Its data is kept safe through every change, and you can send it to a coworker, who gets their own copy to adapt.

[Download the latest release](https://github.com/RooCodeInc/Forge/releases/latest), open it, and add an OpenRouter key. That's the whole setup.

## Requirements

| What | Why | Notes |
|---|---|---|
| macOS 14 (Sonoma) or later | Forge and the apps it generates target macOS 14 | |
| Apple's Command Line Tools (Xcode 15 or later) | Swift compiler, the macOS SDK and `git` | Free. **The full Xcode app is not required**, but works too. With Xcode 26, icons get native Liquid Glass rendering on macOS 26. |
| An AI to build with | Writes the apps | An [OpenRouter](https://openrouter.ai/keys) key is easiest. You can also use ~20 other providers, Claude Code, Codex or opencode if installed, or a model running on your Mac. See [Choosing the AI](#choosing-the-ai). |
| An OpenRouter key (optional) | Image generation, icon artwork, and the fast in-app AI models | Without one, apps' text AI uses whatever builds them (pi's provider, a local model, or your Claude Code, Codex or opencode sign-in) |
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

   The first build takes about a minute. It also creates a self-signed **Forge App Signing** certificate in Forge's own keychain, `~/Library/Application Support/Forge/Signing` (see `scripts/signing-identity.sh`). That gives every build the same signature. Forge's keychain has a password Forge generated and keeps beside it, so signing never asks for keychain access the way the login keychain does. It's only used to sign Forge on your Mac. It produces `build/Forge.app`, which you can drag into `/Applications` if you like.

3. **Finish setup in the app.** On first launch, Forge checks for anything missing:
   - **App-building tools:** if the Command Line Tools are missing, Forge opens Apple's installer right away (click **Install**, then **Agree**). It then checks every few seconds and carries on by itself when they're installed, so there's no button to press afterwards.
   - **An OpenRouter key:** paste one from [openrouter.ai/keys](https://openrouter.ai/keys) while the tools install. Forge checks it with OpenRouter before saving, so a mistyped key or an account with no credit shows up straight away. One key covers building and everything AI inside apps. Under **Use something you already have instead**, you can pick Claude Code, Codex or opencode if they're installed, **A model on this Mac…**, or **Other providers…**. Keys are stored per provider. Releases signed with an Apple Developer ID keep them in your login Keychain. Local builds have no Team ID, and macOS would ask for Keychain access again after every rebuild, so they keep them in `~/Library/Application Support/Forge/keys.json`, readable only by your user account.

   You can change the key and models later in **Forge → Settings (⌘,)**.

## Using it

- A new app's empty chat shows six ideas to start from (a Downloads sorter, screenshot notes, a clipboard history, a reading queue, a focus timer and a photo studio). Clicking one fills in the request, ready to change before you send it. They go away once you start typing.
- Click **New App** at the bottom of the app list, give the app a name and (optionally) describe it. Forge builds it and opens it, usually in under a minute.
- If a request is too vague to build well ("an app for my sales stuff"), the agent asks up to three short questions, each with likely answers, before writing any code; answering starts the build. Clear requests are built straight away, and the agent ends by naming the main assumptions it made so you can correct them.
- Type changes into the chat. Each change rebuilds and relaunches the app. **Undo** reverts the last change. **Return** sends, and **Shift-Return** starts a new line.
- While a new app's first version is built, the chat shows a build card: the app's name and icon as they're chosen, the agent's plan with each part ticked off as it's written, what it's doing right now, and at the end a picture of the app's real window. Later changes show one line with the current step and the time so far. Progress is said in everyday words ("Working on the interface", "Making your app look nice"), never as file names or code, and the chat keeps to your requests, the agent's answers and what happened to the app.
- You can keep typing while Forge works. Messages sent in the meantime wait in the chat (click the ✕ to take one back) and go out together as the next change.
- Attach screenshots, mockups, logos, data files or documents with the paperclip, by dropping them on the chat, or by pasting (a screenshot copied with ⌃⇧⌘4 pastes as an image). The agent sees images and small text files directly. Attachments are saved in the app's `Attachments/` folder and bundled inside the app, where code loads them with `ForgeAssets.url/image/text("name")`. Shared apps include only the attachments the app's code uses; screenshots and documents you attached just for the chat stay on your Mac.
- In any generated app, press **⇧⌘E** to jump back to its chat in Forge.
- While an app is open, the toolbar's Play button becomes a Stop button that quits it (**Quit** is also in the app's right-click menu). That's the way to stop a menu bar app, which has no Dock icon to quit from. To bring an open app to the front instead, double-click it in the sidebar.
- Every app records which Forge built it. When an app was built by an older Forge, it gets an orange badge in the sidebar and a banner above the message box with a **Rebuild** button. The app's info panel shows the version under **Built with**.
- Apps are signed with Forge's local certificate ("Forge App Signing", made in Forge's own keychain the first time and never shared, so building never asks for keychain access), so permissions you grant an app, such as Files and Folders or Screen Recording, survive rebuilds instead of being asked for again after every change.
- Generated apps are installed to `~/Applications/Forge Apps/`, so they show up in Spotlight and Launchpad.
- If you're in another app when Forge finishes, it sends a notification saying the app is ready, has a reply, or needs your attention. Click it to jump to that chat. macOS asks for permission the first time one is sent. Turn notifications off in **Settings → Building**. The Dock icon shows how many chats you haven't seen.
- Double-click an app in the sidebar to build and open it. A blue dot means its chat has a reply you haven't seen. The buttons at the bottom of the sidebar switch between a list and icon tiles.
- Right-click an app in the sidebar for **Run**, **New Icon**, **Show in Finder**, **Share…** or **Export…**. Toggle **Agent Details** (the wrench and screwdriver) in the toolbar to see the agent's working: every file it reads and writes, the commands it runs and what it says along the way.

## Sharing apps

Click **Share** (the toolbar button), or right-click an app and choose **Share…**, to send it through AirDrop, Messages, Mail and so on. You can also use **Export…** to save the file. Apps travel as small `.forgeapp` files containing the app's Swift code, `APP.md`, `icon.json`, icon artwork and any attached files the code uses (a logo, say). Your chat, other attachments, tokens, agent sessions and git history are never included.

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

- **Agent loop:** each message runs the chosen agent in the app's folder. It can read, search and edit files and read the web freely. **Shell commands can need your approval** (Settings → Building → "Ask before running commands"):
  - **Only when needed** (default): routine commands run on their own and still show in the chat. Anything risky or unexpected comes to you. Claude Code decides with its own safety classifier (`--permission-mode auto`, falling back to Always if your account doesn't offer it). Other agents use the decision model (Jev), which judges each command against your request, and obviously risky patterns (sudo, piping into a shell, deleting outside the app, `git push`) always ask.
  - **Always**: every command asks first.
  - **Never**: commands run without asking.

  Approvals show in the app's chat as a plain-English summary of what the command does and how risky it is (written by the in-app AI model), with the command itself under **Show command**, and **Allow**, **Allow All This Turn** and **Deny**. High-risk commands default to Deny and can't be allowed for the whole turn. Nothing runs until you answer, and **Stop** denies it. pi asks through Forge's extension (`Resources/forge-tools.ts`), and Claude Code through a `PreToolUse` hook. Claude Code runs isolated from your own setup (`--restricted --strict-mcp-config --disable-slash-commands`): it uses your sign-in, but none of your hooks, permission rules, plugins, MCP servers or skills. Codex sends each shell command to Forge through a `PreToolUse` hook (read-only commands go straight through) and stays in its sandbox, writing only in the app's folder. opencode's shell stays off unless approvals are set to Never, because it can't ask when run this way. Codex also runs isolated from your own setup (`--ignore-user-config --ignore-rules`), with Forge's instructions as developer instructions, live web search and resumed conversations. Claude Code and Codex don't need a command-line install: Forge also finds the copies bundled with the Claude app (in `~/Library/Application Support/Claude/claude-code`) and the ChatGPT app (inside `ChatGPT.app`), and Settings → Building says which app it's using. When several copies of a tool are installed, Forge uses the newest. Settings → Building picks the model: Opus, Sonnet, Haiku or Fable for Claude Code (Opus unless changed; Forge passes `--model`, since it runs Claude Code without your personal settings), and any model ID for Codex (`-m`). Settings shows whether the tool is signed in, and **Sign In…** runs its own login (`claude auth login`, `codex login`), which finishes in the browser; picking one of them on the welcome screen signs in the same way when needed. To read a GitHub repo, the agent clones it into `.forge/reference/` (with `gh` when installed, so private repos work). Forge then runs `./build.sh` itself and sends any compiler errors back, up to three times. After that it commits to the app's git repo, installs the app and relaunches it. Each app keeps one agent conversation, so the agent remembers earlier requests. **Undo** is `git reset` and starts a fresh conversation.
- **Privacy** (Settings → Building): the built-in agent's file tools work in the app's own folder. To read or change anything else on your Mac it asks first, with the same card as shell commands; system and developer files and temporary folders need no asking, and Forge's keys, its agent's sign-ins and your other apps are never opened whatever the setting. Links inside the app's folder that lead outside it count as outside. Two more switches decide whether the agent sees what an app prints while it runs and pictures of its windows, both of which go to the AI model you chose. The folder rule covers the built-in agent's file tools; shell commands go through the approvals above, and Claude Code, Codex and opencode follow their own rules.
- **Seeing the app run:** the agent can't run anything, so Forge shows it what happened. Every app saves what it prints (`print`, `NSLog`, SwiftUI runtime warnings, fatal errors, failed AI calls) to `.forge/runtime/log.txt` in its project, and the agent reads that when you say something doesn't work. If an app quits within a few seconds of opening, Forge sends the macOS crash report and the last lines it printed back to the agent, up to twice, the same way it does with compiler errors. A crash later on is mentioned to the agent with your next message. Apps also save a picture of their own windows (`.forge/runtime/screenshot.png`) shortly after opening and whenever you switch away from them, so an agent that can view images sees what you were looking at. An app may picture its own windows, so there's no screen recording permission. The built-in agent can also check its own work mid-turn: its `look_at_app` tool has Forge build the app with the changes so far, open it behind your windows, and hand back the pictures, what the app printed and any build errors or crash. It can also try the app with `use_app`: click at points in the latest picture, type, press keys and scroll, then see the result. Forge tells it what each click landed on (a button, row 3 of a list, a text field), whether the window changed at all, what the app printed meanwhile, and whether the code has changed since the app was built, so a click that missed isn't mistaken for a bug. It can pick from pop-up, pull-down, right-click and menu bar menus by name (they're read out to it, never opened on your screen), answer dialogs and sheets, accept or cancel a save panel, and open the panel behind a menu bar app's icon. The app performs all of this on its own windows, so no Accessibility permission is needed; it can't drag. The pictures are the windows as the system shows them, so video, maps and web content are included, still without screen recording permission. Claude Code, Codex and opencode don't have this tool.
- **Live editing:** every generated app has an **Edit with Forge** command (⇧⌘E) that jumps back to its chat.
- **Mac building blocks:** each app's `ForgeSupport.swift` also has tested helpers the agent uses instead of writing its own: `ForgeFolderWatcher` (FSEvents) and `ForgeFolders`, `ForgeHotKey` (global shortcuts via Carbon, no permission needed), `ForgeLoginItem` (`SMAppService`), `ForgeText` (on-device text from PDFs, scanned PDFs and images with Vision, plus RTF, Word and HTML), `.forgeDropFiles` / `ForgeDropZone` (drops from Finder and other apps), `ForgeClipboardWatcher` and `ForgeNotifications`. Menu bar apps use SwiftUI's `MenuBarExtra`.
- **Per-app models:** the info panel (ⓘ) sets an app's own text, image and decision models, overriding Settings → Apps for that app only. Choices are kept in the app's `.forge/models.json` and apply on the next AI call, without rebuilding. Text models are Claude Sonnet (the default), Haiku, Opus and Fable; decisions always use the decision model (Jev) and images the image model.
- **Using other apps:** `ForgeComputer.ask("…")` reads and `ForgeComputer.perform("…")` acts in the other apps on the Mac (Slack, Mail, or Gmail and LinkedIn in the browser) with the person's own sign-ins, so apps need no connectors or API keys. It's built on [cua-driver](https://github.com/trycua/cua) (MIT), which drives apps in the background through Accessibility and window captures. It's off until the person turns on **Settings → Apps → Let apps use your other apps**, which installs a pinned, checksummed and signature-checked CuaDriver.app in /Applications (asking for an administrator's password on standard accounts) (it holds the Accessibility and Screen Recording permissions) and turns its telemetry off. Forge talks to it over MCP and runs the loop itself through OpenRouter with the text model the app chose in its info panel (Sonnet if it hasn't chosen one), offering only reading tools for `ask`. For `perform`, every click, keystroke or key press waits for the person's OK in a Forge dialog built from the action itself (the target app from its process, the exact text to be typed, the keys, the menu path, the element as named in the window last read), with the model's own description shown only second, since what's on screen could steer it ("Allow All for This Task" covers the rest of that task). Shared apps that use it are flagged on import.
- **App data:** generated apps keep their data with `ForgeStore` (in each app's generated `ForgeSupport.swift`), backed by SQLite (built into macOS) in `~/Library/Application Support/<bundle id>/data.sqlite`. It offers single Codable values (`load`/`save`), collections of Codable items saved one at a time with filtering and sorting (`collection(_:of:)`), and plain SQL (`execute`/`query`) for an app's own tables. Values and items are stored as JSON, so adding optional properties never breaks old data. Before the first change of each launch, the database is copied to `Backups/` (newest 20 kept). Data the app can't read is never overwritten or deleted: the user is told once, and the decoding error is logged so the agent can fix the types and the data loads again.
- **AI inside apps:** Forge runs a local gateway on `127.0.0.1:47811`. Generated apps call it through `ForgeAI.ask(...)` (text, images, typed JSON) and `ForgeAI.makeImage(...)` / `editImage(...)` / `editImages(...)` (create, edit or combine pictures with the image model from Settings), plus decisions: `ForgeAI.isTrue` / `choose` / `rate` / `decide` (fast typed judgments with probabilities and confidence from a decision model, TypeSafe's Jev, via OpenRouter or TypeSafe directly; set in Settings → AI → Decisions) with a per-app token, so the API key never leaves Forge. Per-app usage shows in Forge.
- **Icons:** icons follow Apple's layered structure: one object on a calm background. The AI only chooses the object (`icon.json`: a `subject`, an SF Symbol and a background from a fixed palette). Forge controls the grid, margins and lighting. The icon starts as the SF Symbol. Forge then generates three artwork candidates of the object alone, cuts each out with Vision on the device, and has a vision model choose the one that best fits the guidelines. If the full **Xcode 26** app is installed, Forge also writes an Icon Composer document (`.forge/AppIcon.icon`) and compiles it with `actool`, so macOS 26 shows the icon in Liquid Glass with dark and tinted variants. With only the Command Line Tools, Forge draws the layers itself.
- **Providers:** see [Choosing the AI](#choosing-the-ai). pi uses its own config folder (`~/Library/Application Support/Forge/pi`), with update checks and telemetry off, so it never touches a pi you run yourself (unless you choose **My pi setup**). Forge registers local and Ollama/LM Studio models with pi through that folder's `models.json`. In-app AI uses OpenRouter when there's a key, and otherwise falls back to the building model: through llama.cpp, Ollama or LM Studio directly, or a one-shot pi call. With Claude Code, Codex or opencode, it's a one-shot call with your sign-in, isolated from your own setup and with no tools (Claude Code gets Read for images). Image generation and decisions need OpenRouter (or TypeSafe for decisions).

## Layout

| Path | What |
|---|---|
| `Sources/Forge/Store.swift` | App state and the build / install / undo loop |
| `Sources/Forge/Agent.swift` | pi invocation, system prompt, JSON event parsing, shell helper |
| `Sources/Forge/Engines.swift` | Engine choice (pi, Claude Code, Codex, opencode), commands and parsers, finding installed tools |
| `Sources/Forge/LocalModels.swift` | Hugging Face downloads, the bundled llama.cpp server, Ollama / LM Studio detection |
| `Sources/Forge/Composer.swift` | Chat input (Return / Shift-Return, paste and drop) and attachments |
| `Sources/Forge/Template.swift` | Scaffold for new apps, including the generated `ForgeSupport.swift` |
| `Sources/Forge/AppSigning.swift` | The stable signature on built apps, so macOS permissions survive rebuilds |
| `Sources/Forge/BuildStamp.swift` | The Forge version stamped on each built app, and the warning for apps built by an older one |
| `Sources/Forge/Runtime.swift` | What Forge sees of a running app: its log and its crash reports |
| `Sources/Forge/Gateway.swift` | Local AI gateway and provider calls |
| `Sources/Forge/Icons.swift` | Icon design, rendering and artwork generation |
| `Sources/Forge/Provider.swift` | Provider catalog, friendly errors, per-provider key storage (Keychain or private file) |
| `Sources/Forge/Setup.swift` | First-run setup and Settings |
| `Sources/Forge/ComputerUse.swift` | Using other apps: installing CuaDriver, an MCP client, and the agent loop behind `ForgeComputer` |
| `Sources/Forge/Sharing.swift` | `.forgeapp` export and import, and the import review (checklist + AI) |
| `Resources/forge-tools.ts` | The agent's `look_at_app`, `use_app`, `plan` and `delete_file` tools (a pi extension) |
| `Sources/Forge/Updater.swift` | Updates for release builds (Sparkle); the feed is served by `updates/` (see RELEASING.md) |
| `updates/` | The Vercel app that serves the update feed and downloads from the private GitHub releases |
| `Resources/Icon/` | How Forge's own icon was made: its `icon.json`, the chosen artwork and the Icon Composer document. It comes from the same pipeline as the apps' icons; the results are `Resources/AppIcon.icns`, `Resources/Assets.car` (Liquid Glass on macOS 26) and `Resources/AppIcon.png` |
| `Resources/THIRD_PARTY_NOTICES.md` | Licences for the bundled pi agent and llama.cpp (both MIT) |

Generated apps live in `~/Library/Application Support/Forge/Apps/<app>/`, each with its own git history.
