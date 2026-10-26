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
(`swift build -c release -Xlinker -random_uuid` for that build, not committed). To see what someone with a bare Mac
sees, `LAMP_PRETEND_MISSING` (`Pretend`, Lamp Dev only) makes Lamp's own checks miss the Command Line Tools,
Xcode, the person's own Claude Code and Codex or tools from the PATH; a new check for something a fresh Mac lacks goes through it too.

