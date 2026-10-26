# Lamp Dev and worktree instances

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

## Two Lamps on one Mac

A build from source is **Lamp Dev**, a separate app from the Lamp people install: its own name and icon (an
orange DEV banner), bundle id (`dev.lamp.host.dev`), folders (`~/Library/Application Support/Lamp Dev`,
`~/Applications/Lamp Dev Apps`, `~/Library/Logs/Lamp Dev`), gateway and model-server ports, URL scheme
(`lamp-dev://`) and Keychain entries, and no self-updating. `Sources/Lamp/Edition.swift` is the one place
these come from, read off the bundle id that `build.sh` writes (`FLAVOR=dev` by default; `release.sh` passes
`FLAVOR=release`). Anything new that names Lamp on disk or on the network goes through `Edition`, and the
generated apps get it from their Info.plist: Lamp writes what an app is told about itself and Lamp (its folder name,
its secrets, Lamp's ports, scheme and folders: `Template.installValues`) into every copy it installs
(`Store.setInstallValues`, and the phone project's Info.plist), and LampSupport reads it at launch (`LampInstall`).
None of it is compiled in, so a compiled app is the same for every install. The app-signing keychain is shared on purpose, so apps keep their permissions whichever
Lamp rebuilds them. `scripts/dev-data.sh` copies your apps, keys, settings and the agent's sign-ins from the
installed Lamp into Lamp Dev, so the development build has something to work on. A build from a checkout under
`.claude/worktrees/` is an instance of its own, "Lamp Dev <worktree>" (`scripts/instance.sh`, which `LAMP_INSTANCE`
overrides; empty makes the plain Lamp Dev): its bundle id ends in the name, and `Edition.instance` gives it its own
folders, four ports from a hash of the name, URL scheme and prefixes, so builds from two worktrees run at once without
sharing a desk, a gateway or Launch Services' idea of which is which. `fresh-start.sh` and `dev-data.sh` work on this
checkout's instance. The agent's sandbox closes every Lamp's folder (`Edition.lampFolderNames`), instances included. The Chrome experiment's native host is the one thing instances share: the extension names it, and Chrome keeps one registration per name, so the instance that connected last owns it. macOS's Local Network
setting goes by the executable's build ID (its Mach-O UUID), not only the bundle id: two instances built from the same
commit have the same executable, so the second is never asked, takes the first's answer and is silently cut off from the
network. To try the Local Network question as a new person meets it, build the instance with a build ID of its own
(`-Xlinker -random_uuid` added to build.sh's `swift build` for that build, not committed). To see what someone with a bare Mac
sees, `LAMP_PRETEND_MISSING` (`Pretend`, Lamp Dev only) makes Lamp's own checks miss the Command Line Tools,
Xcode, the person's own Claude Code and Codex or tools from the PATH; a new check for something a fresh Mac lacks goes through it too.

## Checking a change beside other work

Several worktrees often build and check Lamp Dev on one Mac at once, on one screen, often beside the person using it.
A check is kept light and out of the way:

- **Build fast.** `build.sh` builds Lamp Dev unoptimized, which rebuilds in seconds after an edit where an optimized
  build takes minutes; `CONFIG=release ./build.sh` is for judging speed, and Lamp itself (`FLAVOR=release`) is always
  optimized. Before quitting or rebuilding a running Lamp Dev, look for agent turns under it (its child processes running
  claude, codex or pi) and leave it alone while one runs.
- **Look without the screen where a view can.** A card or chat line is checked in the gallery (Window → Gallery; see
  "The gallery"), and a single view can be drawn off screen with SwiftUI's `ImageRenderer` from a throwaway test that's
  never committed (it draws no controls, such as spinners).
- **Take a window's picture, not the screen's.** `swift scripts/window-shot.swift <pid>` lists an app's windows and
  `swift scripts/window-shot.swift <pid> <title> out.png` pictures one, covered or not, without bringing it forward (it
  needs Screen & System Audio Recording for whatever runs it, and says so when that's missing). A
  region of the screen is whatever is on top: often another worktree's window.
- **Reach the app, not whatever is in front.** Menu items are chosen through System Events on the app's own process
  (`click menu item "Gallery" of menu "Window" of menu bar 1`), and windows moved or raised the same way. Keystrokes,
  and clicks at screen points, go to whatever app is in front at that moment, which another worktree may have just
  brought forward. Type and click only when nothing else can do it, right after bringing the app forward, and look at
  the result.
- **A macOS question stops the check.** A permission, Local Network or keychain prompt waits for the person; a step
  waiting on one isn't stuck, and it's never clicked for them.
- **Put back what was started.** A simulator or emulator a check booted is shut down when the check is done (an Android
  emulator alone keeps several cores busy), and so is a Lamp Dev that was launched only for the check.
