# Approvals and privacy

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

A capability given to one engine must be given to all of them that can take it, in the same change:

- **Approvals and privacy**: shell commands go through `/agent/approve` for every engine (pi's extension,
  Claude Code's hooks, Codex's hooks); file access outside the app's folder is checked the same way.
  Under "Only when risky", Claude Code's own classifier (auto mode, `classifyAllShell`) decides its shell commands:
  Lamp's hook only hands each one back confined, with no decision (`format=claude-confine`), what the classifier asks
  about comes to Lamp's card through `PermissionRequest` with no check or rating of Lamp's, and a command that ran is
  said in the chat from `PostToolUse` and `PostToolUseFailure` (`format=claude-ran`). What the classifier refuses stays
  refused (the agent is told why, `PermissionDenied`, `format=claude-refused`, and the command's step stays as below; no card comes, so `Agent.claudeNote` tells the agent never to say one will). Codex's
  own reviewer (Auto-review: `approval_policy="on-request"`, `approvals_reviewer="auto_review"`) decides its commands the
  same way, with no hook of Lamp's: only a command that needs more than Codex's sandbox gives (below) reaches it, and
  what it refuses stays refused, with nothing coming to Lamp's card. Its policy (`CodexReview`, as `auto_review.policy`)
  is Codex's default copied whole with Lamp's rules after it, since that key replaces the default and `extra_policy`
  didn't reach the reviewer: refresh the copy when Codex's changes. Lamp's rules refuse what `CommandRisk` calls risky
  (outside the app, destructive, uploads, the person's files and secrets). The network is open inside the sandbox, so
  an upload made from inside it never reaches the reviewer. Codex's commands are said in the chat from its own output
  (`AgentEvent.ran`, under "Only when risky" and Never, where no card of Lamp's says them), as every engine's are: by
  the heading of Codex's reasoning summary before each (`AgentEvent.naming`; Codex's output gives a command no
  description of its own, and a quick step often comes with no summary, so it reads "Did a bit of housekeeping"). Codex
  shows a command as started before its reviewer decides, as Claude Code's streams before its classifier does, so a
  refused one, whichever engine's, is no line of its own: it stays the step it was, and only opening it says it didn't
  run (`ChatLook.notRun`, `ChatLook.ranCommand`). The agent says in its own words what it couldn't do and why,
  never the command (`Agent.codexNote`, and the reviewer is asked for a rationale it can pass on). Under Always Lamp's hook asks about every Codex command
  and under Never there's no hook; in both a command needing more than the sandbox is refused (`approval_policy="never"`).
  pi keeps Lamp's own check (`CommandRisk`).
  Claude Code's and pi's approved commands come back confined (`Sandbox`: `sandbox-exec` with a profile
  that opens the app's folder, the system, developer tools, caches, temp folders and the network, and
  closes the rest of the home folder and both Lamps' folders), so nothing reads a command's text to see
  where it looks. Lamp's own builds run under the same profile, a game's or a screen's with Lamp's player opened for
  reading only (`Store.runBuild`), since its build copies the player rather than compile. Codex's commands run in Codex's own sandbox instead, which its reviewer works with and which can't
  start inside Lamp's: a permission profile (`Sandbox.codexPermissions`, `-c permissions.lamp=…`, a Beta feature of
  Codex's) that closes everything and opens what Lamp's opens, by name: the app's folder (its `.git` kept read-only by
  Codex), the runtime, the developer tools, Homebrew's and the applications for reading, caches and temporary folders,
  Lamp's shims, and the network. The app's folder is named by `LampProject.realDir`, never as Codex's workspace, which
  Codex makes of wherever the folder it starts in leads; a writable folder that is a link, or leads through one, Codex
  refuses at its start and before each command. Codex itself (its state, its
  hooks, Lamp's MCP endpoint) runs unconfined, and a command its reviewer lets out of the sandbox runs under the
  controls Codex gives it, not Lamp's. SwiftPM's own sandbox can't start inside Lamp's or Codex's, so a `swift` shim first on the path
  (`Sandbox.bin`) gives `swift build`/`test`/`run`/`package` `--disable-sandbox`; the compiler's helper for macros is
  the same, so Lamp's Xcode projects pass it `-disable-sandbox` too. Xcode's interface and asset compilers hand their
  work to helpers that stay running and are found through shared memory named `ib…`, whoever started them, so the
  profile closes that memory (and no other): a command starts helpers of its own, confined as it is. Nothing reads a command's text
  for paths any more; don't bring that back.
  A command may write at the app's folder's own name, so it can swap the folder for a link to anywhere, Lamp's
  folder included. The profile, the file checks (`Privacy.verdict`, pi's `checkFile` and `delete_file`, which take
  the folder from `LAMP_DIR`) and Lamp's own writes for the agent (`Store.deleteFile`, `artDestination`,
  `Previews.destination`) all take the app's folder as `LampProject.realDir`: the folders above it worked out, the
  folder itself by its name, never where it leads. Don't resolve `project.dir` itself to decide what's the app's.
  What Lamp reads there outside the sandbox and passes on goes through `AppFile`: each step of the path opened from
  the one before it, none of them a link, and only a plain file read. That's what reaches the agent (what the app
  printed, its screen as text, its answers to Lamp, its pictures and their copies, the app's notes and what was taken
  back from them, the note after a restore), what Lamp writes into the app's code or hands an engine (its secrets,
  `Template.ownSecret`, and the conversation ids), and what Lamp rewrites in place (the migration, a rename, the
  live layout), which would otherwise bring what a link leads to into the folder. A new such read belongs there. Lamp's own
  writes there around a build go through `AppFolder` on the same terms (see "Generated apps").
  Lamp's adb server and Android emulators (the phone and the TV) run on ports of each Lamp's own (`Edition.androidPorts`), never adb's usual
  5037 and 5554–5585, and the profile refuses every Lamp's at any address, and running adb or the emulator from the
  tools Lamp downloaded: through them a command could install, remove or drive apps on the emulator and the
  person's phone. Codex's sandbox can't refuse a port, so there only the ports being Lamp's own keeps `adb` away.
  The profile also closes Homebrew's folders (`/opt/homebrew`, `/usr/local`) for writing (reading and running
  what's there stays open): they're on the path of everything Lamp runs as itself, so a command could otherwise
  leave a program there for Lamp to run unconfined. The agent can't `brew install`. `/Applications` and the developer folder in use
  (`Sandbox.developerFolders`: `DEVELOPER_DIR` and xcode-select's choice, the whole Xcode wherever it is) are closed
  for writing the same way: an Xcode dragged there is the person's to write, and Lamp runs its tools as itself. A program Lamp runs outside
  the sandbox (in a `Shell.run` command, `signing-identity.sh`, Claude Code's hook) is named by its full path
  (`/usr/bin/codesign`), never found on the path. Apple's developer tools are the exception to `/usr/bin`: `xcrun`, `xcodebuild`,
  `git`, `swift` and the rest there are wrappers that find the real program through a cache in the temporary
  folder, which the sandbox leaves writable. So what Lamp runs of them as itself (`simctl`, `devicectl`, the phone's
  `xcodebuild`, the look at the person's git settings) is the real program in the developer folder in use
  (`DeveloperTools.path`), never the wrapper. Inside the sandbox the wrappers are fine.
  Lamp's own git (saving a version, Undo, restore, version names, the look for unsaved work) runs under the
  same sandbox, through `Versions.git` (`gitBlocking` where it can't await): the app's folder is the agent's
  to write, its `.git` included, and git runs the programs a repository names (hooks, filters, a signing
  program), so unconfined it would run whatever the agent left there. A new git call on an app's folder
  belongs in that helper, never in `Shell.run` directly. Lamp looks at an app while a turn saves it, so its git
  runs with `GIT_OPTIONAL_LOCKS=0` (a look never takes the index's lock), and a save goes through
  `Versions.commitAll`, which tries again when it is shut out and tells a save that failed from one with
  nothing to save; a turn whose save failed says so in the chat. The one exception is the helper's own look at the
  person's Mac-wide git settings (`Versions.personalFiles`), which the sandbox closes: it reads files the agent
  can't write, runs no program, and opens to Lamp's git only the files those settings name, never a folder
  and never anything in Lamp's own folders. Nothing in an app's history is checked, cleaned or
  refused, and the agent may use git on it as it likes. On Lamp's own runs signing, hooks and the
  file-watcher command are off (`Versions.environment`): the sandbox closes the person's keys, and a hook
  could only stall a save.
  Undo puts back code, never data. Data is copied, though: before a change goes into a Mac app, by reopening it
  or live, Lamp copies its LampStore database into its Backups folder, named after the version that wrote it
  (`DataSnapshots`, beside the app's own once-a-launch copies). A page's preview on this Mac starts from a copy of what
  the page in its Mac copy saved (`PageLive.saved`, asked of the open copy with its own token): held in Lamp's memory
  only, written nowhere but the preview's own store, and never sent back, so the agent's tries there leave the person's
  data alone (the devices guide, "The preview holds the person's data, one way").
- **Files Lamp fetches for an app** (`assets`, "3D scenes and games"): Lamp itself downloads them, unconfined, but only
  from the addresses in its own index, checks each against the hash the index pins, and writes it into the app's folder
  with `AppFolder` (never through a link). They're data: a model, a picture, an atlas's XML; nothing is run, opened or
  made executable, and an archive is read by Lamp for the files the index names, never unpacked. No command runs, so
  there's nothing to approve; what the agent fetches with its own commands is still judged as fetching (#830).
- **The person's devices**: the agent may read a device on the network freely, but changes one (a key press, opening
  an app, volume, input, power, a setting) only once the person has said yes on Lamp's own card (`device_permission`,
  `DevicePermissions`): "Try it on your <device>?" ("Try it on <device>?" for one Lamp only found, which may not be the person's), answered Allow once (until the person next writes), Always for the
  device (the wish's life) or Not now, with no "Decide for me" (`TalkCard.Question.personOnly`). Lamp keeps the answer
  from the click once it's delivered as the person's message (an answer taken back while it waited in line allows
  nothing), in its own folder by the wish's instance, never in the app's folder, which the agent can write.
  `use_app` on an app that reaches devices (`DevicePermissions.reachesDevices`: LampRoku or LampNetwork in its code, or a
  local network reason or Bonjour types in capabilities.json) is refused unless its `device` names one the person allowed.
  Each engine's command check carries the same rule (`DevicePermissions.commandRule`): pi's `CommandRisk` counts such a
  command as reaching beyond the app, so it gets Lamp's card; Claude Code's auto mode gets it as a `soft_deny` rule after
  its own (`$defaults`, `Engines.swift`); Codex's reviewer is told to refuse it (`CodexReview`), but sees only what needs
  more than Codex's sandbox, which leaves the network open, so under "Only when risky" Codex also gets Lamp's hook asking
  only this (`format=codex-devices`, `DevicePermissions.mayChangeADevice`: a command naming a private address or a
  `.local` name that isn't a plain `curl` read is refused unless that address is an allowed device's, as the card noted it; a device asked about again at another
  address gets the card again, since Lamp can't tell it's the same device).
  Never leaves every engine's commands unchecked, this rule included. What this can't see: a command that keeps the
  device's address in a script or file it runs, and which device a `use_app` click really reaches (the agent names it).
  Holding those too would take filtering the network itself, per address, in the sandbox and in the app.
- **The home network** (`HomeNetwork`, the "Devices as data" guide): only where the person is looking at what's on it
  (Your Devices, Add a New Device, `network_devices`), Lamp sends one datagram to each address of this Mac's own private
  subnet (a /24 at most), reads the Mac's neighbor table, the maker of each hardware address from the list it ships,
  and every Bonjour service's name, host and model keys; nothing more is sent to a device, and nothing needs admin.
  Bonjour names are often people's ("…'s iPhone"). They're kept in memory only, shown on this Mac, and told to the
  agent the person already uses (`network_devices`, a device's setup note, each saying to keep them out of an app and
  an integration); never written to disk, into an app or its files, or sent anywhere else. A device found only that way
  is named by maker and model in its setup conversation, whose name is written into its folder (`Device.plainName`).
  Help's "Your home network" says this in plain words.
