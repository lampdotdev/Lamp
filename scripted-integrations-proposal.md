# Taking on new devices: scripted integrations

A design proposal for the Lamp team. It answers the question "how could Lamp take on devices it doesn't support by
having its agent write the support, rather than us hand-shipping each device?", and it disagrees with the framing in a
few places. Everything here is grounded in the code as of the `roku-integration-fixes` branch; where a claim is an
inference rather than a reading, it says so.

## Summary

- The lever is not "the agent writes a driver". It is a pipeline: the model writes an integration, Lamp proves it on
  the person's real device, and a human reviews what gets shipped to everyone. Lamp already has the first stage of this
  (`device_integration`, `IntegrationCheck`, the marks); it lacks the proving stage entirely, and that is where the Roku
  days went.
- Most devices should stay data. The format already expresses more than the input assumes, and what each new device
  has needed so far is not a different kind of code but a handful of small quirks, each of which became a Swift pull
  request and a format extension. Scripting earns its place by absorbing those quirks inside the integration, so a
  device quirk stops being a Lamp release.
- Where scripting is needed, it should be JavaScript on JavaScriptCore, run in a helper process Lamp ships, against a
  capability API in which secrets and blobs are handles the script can name but never read, and in which every call
  lands on the same guarded functions the data actions use today. Safety comes from that API; the process boundary is
  depth, not the wall.
- New transports (adb, WebSocket, TLS sockets) go only into the script library, never into the declarative action
  list, which should stop growing. Setup cards, consent, marks, discovery scans and the checker stay Lamp's and stay
  declarative.
- First experiment: the Android TV family (Fire TV sticks, Chromecast with Google TV, Nvidia Shield, Google TVs from
  Sony, TCL and Hisense) over adb on the network. It is the largest uncovered device class in people's homes, Lamp
  already owns the toolchain and the app kit, the proving loop is strong (real screenshots, real logs), and it needs
  exactly one new capability family.
- Not built: in-process plugins, model-written Swift, scripts that draw cards or talk to the person, scripts for
  control-only blocks like `LampRoku`, peer-to-peer sharing of scripts, WebAssembly, USB.

## The problem, and what the evidence says

### What happened with the Roku

Lamp's integration format (`Integration`, Sources/Lamp/Integration.swift) was designed so that a device is data the
model hands Lamp with `device_integration`, acted on by Lamp's primitives (`IntegrationAction`), checked by
`IntegrationCheck.problems` and run by `IntegrationRunner` (Sources/Lamp/Integrations.swift). The Roku integration was
written that way, by the model, in a device-setup conversation. Then, in use, it came up short, and the shortfalls sort
into four kinds that deserve different answers:

1. **Lifecycle gaps**: no icons or splash screens in the manifest, no `remove`, a `stop` that pressed Home, no `type`.
   These are omissions the checker could have refused. `IntegrationCheck.problems` requires `bridge.install` when `app`
   is declared, requires a picture in `look` and keys for `use`, and requires `{text}` in `type` when `type` exists; it
   requires nothing else of the lifecycle. A model that reads the skill writes what the skill shows and stops.
2. **Wrong advice to the builder**: the declared `rules` told the builder to use `roRegistrySection` while Lamp ships
   `LampStore`, and gave a wrong storage limit. No plugin system fixes this. Rules are prose for another model; the only
   defences are lint (the rules must name the support libraries the integration declares, which they didn't) and a real
   app built and run on the device.
3. **Facts no documentation has**: `ecp-setting-mode` in device-info, which Roku's ECP page doesn't list, and the
   install that times out over a running developer channel. These can only be learnt on a real device, and today the
   only way the model learns them is a person relaying what the device did. That is the human-guided session.
4. **Mechanics that became Lamp's**: a `type` bridge with its placeholder rule, a per-device lock between installs and
   removals (`DeviceApps.take`), ownership of a device's one developer slot (`lastOnDevice`), stopping the running copy
   before an install (`DeviceApps.install`). Every one of these is generic. Sources/Lamp/DeviceApps.swift says of
   itself "Nothing here knows any one device", and a search of Sources/Lamp for "roku" finds the word only in comments,
   gallery fixtures and the builder's rules: there is no Roku-specific Swift in Lamp. What was needed in Swift was
   framework, not driver.

So the Roku evidence doesn't say "the model should have written code". It says the checker was lax, the proving step
was missing, and Lamp's device framework had holes that only a second device shows up. A plugin system would have fixed
none of (1) to (3) and would have spread (4) across integrations instead of fixing it once.

### What the Xbox shows

The Xbox integration (Resources/Devices/xbox-one.json) is the more telling case for scripting. Count the features of
`Request` that exist because of it: `poll` (Device Portal answers 204 while installing), `expect` (the install's state
must say `Success`), `restore` (the console's "treat apps as games" setting), `{cookie:CSRF-Token}`, `{base64:…}` in a
query, `{isGame}`, `https` with `DeviceTLS.Pins`, and `certificateRoot` (the portal makes itself a new certificate at
each start). Each is a small, reasonable declarative feature. Each was a Swift change, a checker change, a skill change
and a release. That is the pattern to expect from every device: not a new kind of code, but five quirks, each one line
of logic, each today a format extension that only the team can make. A script of thirty lines inside the integration
would have expressed all of them, and the format would have stayed where it was.

### What the format already covers

The format can declare HTTP requests with digest or basic auth, forms with the package, polling, expectations, cookies,
restores, SSDP, Bonjour and HTTP probes, TCP log streams, SSH with pinned host keys and approved templates, listed and
downloaded tools, vendor sign-ins, typed fields and values read in steps. A device whose developer interface is HTTP
request and response with a fixed install sequence is covered, and covered better than a script could cover it: the
checker can read it, the marks attach to its text, the cards derive from it, and the approvals name exact commands.

It is worth saying plainly that one primitive already runs model-chosen code with wider reach than anything proposed
here. `DeviceTools.run` (Sources/Lamp/DeviceRemote.swift) downloads any https program the integration names, checks its
SHA-256, and runs it under `sandbox-exec` with `(allow network*)` after one approval card. That is a program the model
picked, with the whole network. The script host below is strictly tighter than that, and the tool's profile should be
narrowed to the device's address at the same time (inference: `sandbox-exec` profiles take `(remote ip "addr:port")`
filters; Sources/Lamp/Sandbox.swift already uses `(remote tcp "*:port")`).

### Where the format genuinely stops

Reading the shipped integrations, the skill and the runner, the format can't express:

- A value passed from one action to the next inside a sequence. `{read:<step>}` carries a value between steps; nothing
  carries one between the actions of a bridge (a process id from `pidof` into `logcat --pid`; a job id into a status
  poll that isn't 204; a token out of an HTML page into the next form).
- A condition. "If the device answers X do Y", "if the copy there is running, end it first", "try again with the other
  activity name". The Roku's install-over-running became a generic Swift rule because the format had nowhere to put a
  condition.
- A session. Anything with a handshake and state: a WebSocket register that mints a client key, a TLS socket with
  length-prefixed frames and a heartbeat, a REPL. There is no WebSocket or TCP conversation primitive (only `probe` and
  the read-only `stream`).
- Transports Lamp owns but doesn't open. `IntegrationAction.bridge` reserves `devicectl`, `adb` and `sdb`, and the
  runner refuses them: "isn't open to integrations yet".
- Parsing beyond one JSON or XML path, and anything computed (a digest of the package in a header, a timestamp).

Those five are the residue. They are real, and each new device will have one or two. They are not most of any device.

## Recommendation

Build three things, in this order, and treat them as one pipeline:

1. **A stricter contract**, so an integration that is accepted is complete.
2. **A proving run** on the person's real device, whose report goes back to the model, so the facts no documentation
   has are learnt by Lamp and not by a person at the keyboard.
3. **A scripted escape hatch**, confined to bridge sequences, step checks and identification, for the residue above,
   with new transports exposed only there.

And keep the declarative format as the normal case. The guidance to the model should be "write it as data; reach for a
script only for what data can't say", and the checker should refuse a script that only does what actions could do (a
heuristic lint: a script that makes nothing but a fixed list of `http` calls with no branch, loop or carried value is
turned away with "write this as actions").

The reason to put the contract and the proving run first is that they are what the Roku needed, they pay off for data
and scripts alike, and the proving run is what makes scripts safe to accept at all: nobody can review a script, but a
device can run it.

### Why this and not the alternatives

- **Hand-ship each device.** The Roku took one guided session and two pull requests; the Xbox took more. There are
  perhaps ten device classes worth having and a long tail nobody will ever ship. Hand-shipping stays the right way to
  *own* the head of that list (someone has to update an integration when the vendor changes the OS), but it should be
  done through the same pipeline: the model writes, the device proves, a person reviews. The tail becomes the person's
  own, like the apps they build.
- **A richer declarative language** (conditions, loops, variables in JSON). This is how the format would grow if left
  alone, and it would end up a worse JavaScript with a checker that has to understand it. Once logic is needed, a real
  language with a locked API is simpler to check, simpler to write for the model, and simpler to read.
- **Plugins with the developer's rights** (as pi's and Claude Code's extensions have). The input is right that this is
  out: Lamp's users can't review code and Lamp holds provider keys, device passwords, signing certificates, gateway
  tokens and apps that read mail. Nothing model-written should run with Lamp's rights, in Lamp's process, or with a
  file system.
- **WebAssembly.** The model writes JavaScript far more reliably than anything that compiles to Wasm, there is no
  toolchain on the person's Mac to compile with, and JavaScriptCore is in the OS and already in use in Lamp's own
  support library (`LampScript` in Sources/Lamp/Template.swift, with `JSContextGroupSetExecutionTimeLimit`). Wasm's
  advantages (determinism, language choice) don't buy anything here; its one real advantage (a tiny engine surface)
  is had more cheaply by running JavaScriptCore with its JIT off in a helper with no network.

## Architecture

### What stays declarative

Everything the person sees, everything the checker reasons about, and everything that scans the network:

- `id`, `name`, `maker`, `kind`, `sources`.
- `find`: the scan kinds (SSDP, Bonjour, an HTTP probe of what answered), plus one addition worth making regardless of
  scripts: `{"typed": true}`, a device that announces nothing and whose address the person types on the first step's
  card (many boards, kiosks and older devices). Scans stay Lamp's; a script never searches the network.
- `identity`: the reads, as today. A script may offer `identify(address)` for a device whose identity needs a session
  to read, but Lamp still decides which addresses are candidates.
- `steps`: the card (`title`, `lines`, `show`, `qr`, `field`, `link`, `accepts`, `known`, `wait`, `model`). A step's
  `run` and `check` may be a script call instead of an action list; its card never is.
- `bridge`: which sequences exist and the `keys` map. Each sequence may be actions or a script call.
- `app`: `files`, `rules`, `package`, `output`, `wrap`, `start`, `host`, `support`, `icons`, `preview`, `purpose`.
- `commands`: new, an allow-list of SSH command templates and tools by name, each with its `explanation`, approved by
  the person per device exactly as `DeviceApprovals` approves them today. A script runs one by name with values; it
  never composes a command string.
- `needs`: new, the capability families the script uses (`http`, `tcp`, `ws`, `ssh`, `tool`, `adb`). A call outside
  the manifest fails at runtime, and the manifest is what the person's card is written from (below).

A sequence or check is a script call when it reads `{"call": "install"}` and the integration carries
`"code": "export async function install({ device, app, lamp }) { … }"`. One module per integration, at most 64 KB,
no `import`, no top-level code beyond declarations; every `call` must name an exported function, and the checker says
so by name when it doesn't.

### The capability API

What a script can touch, as the model sees it. Every function is asynchronous; every call crosses to Lamp and lands on
a function that exists today.

```
device.address, device.id, device.name, device.model, device.osVersion
device.http({ method, port, path, headers, body, form, auth, https, timeout })
    → { status, headers, text, json(), xml(path), body }         // body is a handle, see below
device.probe("tcp:8060" | "ssdp:…" | "bonjour:…")               → boolean
device.tcp(port, { tls })  → session { write(bytes), read({ until, max, timeout }), close() }
device.ws(port, path, { tls })  → session { send(text|bytes), receive({ timeout }), close() }
device.ssh.run("start-app", { values })                          // a template from `commands`, by name
device.tool.run("pixlet", { values })                            // a tool from `commands`, by name
device.adb(["shell", "am", "start", …])                           // this device's serial only, see the experiment
device.fields.password                                           // a handle, never a string
device.memory.get(key), device.memory.set(key, value)            // ≤ 16 KB per device, for pairing tokens
app.id, app.name, app.isGame, app.package, app.certificate       // the package and certificate are handles
app.packageFullName, app.appUserModelID                          // for a wrapped package
lamp.log(line)                                                   // into the app's log or the step's card
lamp.wait(seconds)                                               // 1 to 30, as `wait`
return { picture: body, log: text, answer: text, read: value }   // what the sequence hands back
```

Three rules make this safe without reading the script:

**Secrets are handles.** `device.fields.password` is `{"$field": "password"}`, an opaque value the script places into
`auth`, a header, a form value or a body, where Lamp fills it under the same rules `Placeholders.problem` applies
today: never in a path, never in a command, never shown. A script can't read the password, concatenate it, or log it.
This is stricter than the input's "that device's typed fields" and costs nothing, because no bridge ever needs the
password as text; it needs to send it. `signIn` is the same. The package and certificate are handles for the same
reason: `DeviceHTTP.send` already takes files by name (`@{package}`), so the script passes `app.package` where a form
value goes and Lamp streams the file.

**Blobs stay on Lamp's side.** An answer's `text` is cut (64 KB, as `Outcome.answers` is cut today); its `body` is a
handle the script can only hand back as `picture` or `log`, which Lamp keeps under the same `DeviceHTTP.limit`. A
screenshot never crosses the pipe to the script and back.

**Every call is an action.** `device.http` builds a `Request` from the script's object and runs it through the same
checks an action gets (`IntegrationCheck.requestProblems`, applied at runtime: port, method, path, headers, `auth`
only with a field handle, form files only the package and certificate) and then `DeviceHTTP.send`, with its address
guard (`DeviceAddress.isPrivate`, the device's own address, no redirect, the password only for the device's own
challenge, `DeviceTLS.Pins`). `device.ssh.run` is `DeviceSSH.run` with `DeviceApprovals`; `device.tool.run` is
`DeviceTools.run`; `device.probe` is `DeviceProbe`. A script chooses which guarded thing to do and when; it can't do a
new kind of thing.

The two genuinely new capability families are `tcp`/`ws` sessions and `adb`. A session is to the device's address
only, over `NWConnection` as `DeviceStream` is, with TLS pinned the way `DeviceTLS` pins HTTPS, with byte and time
limits and closed when the run ends (a bridge that must keep a session open while the app is "on", as a Cast session
would, is a later question; see open questions). `adb` is covered under the experiment.

### Process and sandbox

The script runs in `LampScriptHost`, a small executable target like `LampRelay` (Package.swift, copied to
`Contents/Helpers` and signed by build.sh). It links JavaScriptCore, is started with `JSC_useJIT=0` (the scripts are
tiny; the JIT is the engine's largest attack surface), reads one job on standard input (the code, the entry point,
the context values, the limits) and talks to Lamp in JSON lines: each capability call is a request line on standard
output, awaited as a promise, answered by a line on standard input. The host has no other I/O. Lamp runs it under
`sandbox-exec` with a `(deny default)` profile modelled on `DeviceTools.confinement` with the network and the tool's
folder taken out: read the system to load, `/dev/null`, nothing else. A runaway slice is stopped by
`JSContextGroupSetExecutionTimeLimit` as `LampScript` does, and Lamp kills the host at the run's budget.

Why a helper and not a `JSContext` in Lamp's process, which would be simpler: a context with nothing injected is
already an I/O-free island, so the helper adds nothing to *what a script can reach*; it adds that an engine bug, a
hang or a memory blow-up can't take Lamp's main actor with it, and that the profile denies even what an engine escape
would try. That is the right order of importance. Spend the effort on the API; the helper is a day's work once the
API is asynchronous, which it must be from the first line (so moving in or out of process never changes a script).

Lamp's side is `IntegrationRunner.run(call:)`: it spawns the host, serves its requests on the same code path as
actions, enforces the manifest, counts calls (at most 200 a run), times the run (120 s; 600 s for `install`, matching
`poll`'s ceiling), and turns what the script returned into an `Outcome`. One run per device at a time, under the lock
`DeviceApps.take` already holds across installs and removals; a step's check, which `DeviceSetupPage` runs every few
seconds, is skipped while a bridge run holds the device.

### What a script knows and can't know

A script gets the device's record, the app's names and the values `IntegrationRunner.values` fills today (minus the
secrets, which are handles). It has `device.memory` for what a pairing mints. It doesn't have the clock beyond
`lamp.wait`, the file system, any address but the device's, any other device, the person, or the chat. It can't draw a
card, change a step, or ask a question: anything it would ask for is a declared `field`.

## Security model

### Threats and where each stops

- *A script reaches the Mac, the LAN or the internet.* Every outbound call names the device's address from Lamp's
  record, checked by `DeviceAddress.isPrivate`; the helper itself has no network. A neighbour's device that answered
  a scan is a device the person hasn't set up, and `Integrations.Kept` keeps only devices a step has passed on.
- *A script reads Lamp's secrets or files.* There is no file API and the profile denies files. Fields are handles.
- *A script leaks the device's password.* Its only sink is the device that owns the password.
- *A script damages the device.* Bounded by what the person accepted: the step's `accepts` sentences (Lamp's words,
  `IntegrationWords.accepts`) and the capability card below. Commands on the device are only the declared templates
  the person approved, by exact text, per device (`DeviceApprovals.subject`).
- *A script drives another device.* `device.adb` pins `-s` to this device's serial inside Lamp (`Adb.run` already
  takes a serial); the person's phone on the same adb server is unreachable. The agent's own shell commands remain
  barred from Lamp's adb ports by the sandbox profile, as now.
- *Resource exhaustion.* Per-slice time limit, run budget, call count, byte limits, one run per device, 16 KB memory.
- *Prompt injection through the device's answers.* A hijacked or malicious device can feed text to the script and,
  through `answer`/`log`, to the model. The capability wall bounds what a misled script can do to the device the
  person already handed over, and nothing else. What reaches the chat stays what it is today: the device's words,
  stripped and cut by `DeviceApps.plain`, labelled as the device's.
- *Prompt injection through vendor documentation at authoring time.* Every engine can read the web (pi's `web_fetch`
  in Resources/lamp-tools.ts; Claude Code's and Codex's own). A page that tells the model to post the password
  elsewhere produces a script that can't: there is no such function, the manifest refuses the family, and the
  password is a handle. The residual risk is a script that does something unwanted *to the device*, which the
  proving run shows and the `accepts` card bounds.
- *An engine bug.* The helper's profile leaves nothing to gain; the JIT is off.
- *Supply chain.* Written integrations are the person's own, like the apps they build. Shipped ones are reviewed by a
  person and win over a written one with the same id (`Integrations.all`). Before any sharing exists there should be
  a revocation list served with updates (`updates/api`, where `engines.js` already holds engine versions back): an
  integration whose code hash is listed refuses to run its bridge and its setup window says why.

### What the person accepts, and when

The person can't read a script, so the card can't be about the script. It is about the manifest. At the end of setup,
and again in Settings → Your Devices, Lamp writes one sentence per family in `needs`, in its own words: "Lamp will
talk to your Fire TV over your network the way Android's developer tools do: install, open, picture and remove apps on
it, press its keys and type on it. It reaches nothing else." The sentence is Lamp's (`IntegrationWords.needs`), as the
`accepts` sentences are, so no integration can play a capability down. The step cards stay as they are. Command
approvals stay as they are. The proving run (below) is started by the person's press, never silently.

One hardening noticed while reading, unrelated to scripts and worth doing first: `DeviceAddress.isPrivate` refuses
loopback but not this Mac's own LAN address, and `Integrations.addresses(for:)` doesn't take `TVs.macAddresses()` out
as `Integrations.unknown` does. An integration's `find.http` probe could therefore "find" this Mac at its LAN address
and point a bridge at the gateway, which listens on the network while a TV app is set to open. Exclude the Mac's own
addresses from any integration's candidates. (Inference from the two functions; not tried.)

## The proving run

This is the piece the Roku lacked and the piece that makes scripts acceptable. `IntegrationProbe`, new:

**What it installs.** Not an app Lamp writes for a kind it doesn't know: the integration's own scaffold
(`app.declared.files`, `{{NAME}}` filled as "Lamp Probe"), with Lamp's support libraries and icons written as for any
build (`DeviceSupport.write`), packaged by the declared `package` step in a sandbox (`Sandbox.run`, under a throwaway
project folder in Lamp's own folder, which the profile opens by path), and wrapped if `wrap` says so. If the scaffold
can't be built and installed, the kind is wrong and that is the finding.

**What it does**, each stage with a budget, stopping at the first failure:
`install` → `launch` → `look` (the picture must decode and differ from a picture taken before the launch) → each
key in `keys` once through `use` → `type` "lamp" when declared → `logs`/`log` when declared (a line must arrive, or
the log must read) → `stop` → `install` again with the copy still running (the Roku's timeout) → `launch` → `remove`
→ `launch` must now fail or `look` must show the home screen again. When `support` declares the web library, the
page's claim arriving at `/app/claim` (`DeviceSupport.Claims`) is a second, stronger signal that the app's page ran.

**Where the report goes.** Three places. The setup window shows the stages ticking and the device's words at a
failure. The device's setup conversation gets the report appended to its next request, the way `Agent.deviceSetupNote`
already appends what the device said of itself, for every engine alike: "The last try on Living Room Fire TV failed at
'install again over the running copy': the device answered 500 to /plugin_install: …". And the bridge gets a mark:
`bridge.known` with model and version, shown in Try On and the setup window as "Worked on Fire TV Stick 4K, Fire OS
8.1". `Integrations.mark` keys a step's mark on unchanged text; a bridge's keys on the hash of the bridge and the code,
so a changed script is "Not tried yet" again.

**Consent and the loop.** The run installs something on the person's device, so it starts from their press on the
last step's card ("Try it on your Fire TV"). The card offers "Keep trying while it's fixed": with that checked, a
resubmitted integration (`Integrations.submit` from `device_integration`) runs the probe again by itself and the model
sees the next report with its next request. That one checkbox turns the human-guided session into a loop the model
drives, with the person watching their device's screen and able to stop it.

**When the device isn't there.** The probe can't run and nothing pretends it did: the integration stays "Not tried
yet", which the person sees on every card and the model is told. For shipped integrations there is a cheaper
companion: `IntegrationRunner.send` is already injectable and `Tests/Fixtures/lg-webos-tv` holds recorded answers;
the probe can record every request and answer of a passing run, and a later edit can be replayed against the
recording in the regression suite. That's for the team, not for the person.

## How it fits the three engines

Nothing here is engine-specific, which is the point of putting it behind one tool:

- The script is a field of the JSON object `device_integration` already takes (Resources/lamp-tools.json), served
  through `Store.mcp` to Claude Code and Codex and through `spec("device_integration")` in pi's extension. The
  checker's refusals come back as the tool's error text in every engine, as now (`Store.agentIntegration`).
- The probe's report rides with the setup conversation's requests (`Agent.deviceSetupNote`, appended in `Agent.run`
  before each engine's `case`, Sources/Lamp/Engines.swift), so no engine needs a new tool to learn it. No tool runs
  the probe: the person's press does, or the consented loop.
- The guidance (when to script, the API, the handle rules, the lint) goes into the `device-integrations` skill
  (Resources/skills/device-integrations/SKILL.md), which every engine opens with `read_skill`; the system prompt keeps
  its one rule (`Agent.deviceRules`). The skill's revision hash (`Skills.revision`) makes conversations that read the
  old one open it again.
- The setup conversation's refusal list (`Store.deviceSetupRefusal`) already allows `device_integration`, `read_skill`,
  `ask`, `progress` and the notes; nothing is added.
- Reading vendor docs is each engine's own web tool; the integration's `sources` records what was read.

The pull request that lands scripts should say which engines wrote an integration end to end, as CLAUDE.md asks of
anything touching the tools.

## The first experiment: the Android TV family over adb

**The device class.** Fire TV sticks and cubes, Chromecast with Google TV, Nvidia Shield, and the Google TVs built
into Sony, TCL and Hisense sets. Together they are the other half of the living room the Roku integration opened, and
Lamp has nothing for any of them.

**Why this one and not something exotic.** Three reasons. Value: it is the largest uncovered class, in the same homes
and for the same wishes as the Roku. Readiness: Lamp already downloads the Android toolchain (`AndroidTools`), wraps
adb by serial (`Adb.run(_:on:)`, `Adb.install`, Sources/Lamp/Android.swift), builds Android apps (`AndroidTemplate`),
and its sandbox already keeps the agent's commands away from Lamp's adb server and the person's phone (the port and
`process-exec` rules in `Sandbox.profile`). So the experiment isolates the two things being tested, the proving loop
and the script hatch, from any new app kind: the app kind is Lamp's Android kit with TV rules (a leanback launcher
intent, no touch; inference, I didn't read AndroidTemplate in depth). And a strong loop: adb gives real screenshots
(`exec-out screencap -p`), real logs (`logcat`), keys (`input keyevent`), typing (`input text`), stop (`am
force-stop`), removal (`uninstall`) and install over a running copy, so every probe stage has a real signal.

**Why it needs the script hatch rather than a declarative `adb` action.** Most of the bridge is a fixed sequence and
could be data. The parts that aren't are exactly the residue: the setup check must read `adb connect`'s words and tell
"unauthorized" (the person hasn't accepted the dialog on the TV yet) from "offline" from "device"; a sleeping TV must be
woken before a launch (`input keyevent KEYCODE_WAKEUP`, only when `dumpsys power` says it's asleep); logs filtered by
the app need its process id from one command carried into the next; and the family's members differ in small ways
(which developer settings exist, whether the TV listens on 5555 as soon as debugging is on or needs a pairing code
first on newer Android TV builds) that a script absorbs with a branch and data would need a format extension for. These
are claims from public documentation and memory of the devices, not from the code; the first thing the experiment
confirms is which of them hold on the two devices in hand.

**`device.adb` as a capability.** One function, in Swift, in `Adb`: arguments as a list (no shell), the serial pinned
to this device's `address:5555` (or the port the pairing step read), Lamp's own adb server on `Edition.androidPorts`,
a timeout, output cut. Nothing in it is Fire TV's. The person's acceptance sentence for `adb` is the one quoted above.
If the experiment ends with Fire-TV-specific Swift anywhere in Lamp, the thesis failed; if it ends with ~100 lines of
guard in `Adb` and a 60-line script in the integration, it held.

**Discovery.** Fire TV answers SSDP for the DIAL service; Google TV devices advertise `_androidtvremote2._tcp` and
`_googlecast._tcp` over Bonjour and a DIAL description on their HTTP port. (From public documentation; to be confirmed
on the devices.) Identity before pairing comes from the DIAL device description; after pairing a scripted `identify`
can read `getprop` for the exact model and OS build, which is what the Try On menu and the agent's device line want.

**Setup steps**, as data: turn on developer options (tap the build number seven times; the card's lines, with `wait`
and a check that `adb connect` reaches the port), accept the debugging dialog on the TV (a scripted check that polls
the connection state and reports "waiting for you to accept on the TV" until it reads "device"), and nothing else.
`accepts` carries `softwareRisk` for the first step. No password, no account.

**What the experiment measures.** With two devices in hand and the stricter checker and the probe in place: can the
model write the integration in a setup conversation with no help beyond the person pressing cards and reading the
screen? How many probe rounds does it take? Where did each quirk land: script, data, or Swift? How long is the script,
and is any of it something another device will want in the library? And the user-facing one: is a wish for the Fire
TV, from the desk, built and on the screen in one sitting?

**Second and third candidates**, in the order they'd teach something new: a Linux board or a Steam Deck over SSH
(tests composing declared command templates with a file transfer, which needs `device.ssh.put` in the library; a
kiosk page from the TV kit as the app), and screens on Chromecasts and Nest Hubs through the Cast protocol (tests TLS
sessions with framing and a heartbeat, and a bridge that keeps a session open while the app is on; a big class, but
with no picture to prove by and a dependency on a third-party receiver, so not first). A Windows PC in developer mode is
worth noting as a nearly free data-only addition: its Device Portal is the Xbox's API, which the Xbox integration keeps
out only with `contains: "Xbox"`.

## A staged plan

**Stage 0: the contract** (one pull request, no scripts). `IntegrationCheck.problems` demands a complete lifecycle
when `app` is declared, with explicit absences so the checker can tell "forgot" from "doesn't exist": `remove`
required; `stop` required or `"stop": "home"` declared; `type` required when `use` exists or `"type": "none"`
declared ("the device has no on-screen keyboard"); `icons` required when any scaffold file's text names a picture
(`[\w/.-]+\.(png|jpg)` over `files`' contents) that `icons` doesn't list; `rules` must name each library `support`
declares (would have caught `roRegistrySection`). Add the Mac's-own-address exclusion. Update the skill. Gallery
entries for any new card state.

**Stage 1: the proving run** (two or three pull requests). `IntegrationProbe`; the Try card and the "keep trying"
consent on the last step; the report into the setup window and the setup conversation; `bridge.known` and its words in
`IntegrationWords.mark`; recordings for the regression suite. Run it on the Roku and the Xbox first: both should pass,
and anything that doesn't is a finding about the probe or about them.

**Stage 2: scripted sequences** (three or four pull requests). The format (`code`, `call`, `needs`, `commands`,
`find.typed`); the checker's additions (parse in the helper, exports, size, no import, manifest, the "write this as
actions" lint); `LampScriptHost` and its profile; `IntegrationRunner.run(call:)` with handles and limits; the
capability card and its sentences; the skill's new section; the chat's and gallery's new states. Land it with `http`,
`probe`, `ssh`, `tool` and `fields` only, and re-express one shipped bridge as a script in the test suite (the Xbox's
install, with its restore, poll and expect) to prove the API is complete for what data already does.

**Stage 3: the adb family and the experiment** (one or two pull requests, then the sessions). `device.adb` with its
guard and sentence; the Android TV kind; then the experiment above, run as described, written up by what landed where.

**Stage 4: later families, as a device asks for them.** `tcp`/`ws` sessions with pinning; `device.ssh.put`;
long-lived sessions for bridges; the revocation list before any sharing; promotion of a proven integration to a
shipped one, which is a pull request with the probe's report and the recording attached, reviewed by a person. The
person's consent is for sending their integration and report to the team (the bug-report delivery path looks like the
right carrier; inference), never for shipping: a shipped integration runs on everyone's device and wins over theirs.

## What I would not build

- **In-process plugins or model-written Swift loaded into Lamp.** Agreed with the input, and for the reason it gives.
- **Scripts that draw cards, ask questions, or touch the chat.** Cards are how the person is kept honest about what
  happens to their device; keep them derived from data Lamp writes the sentences for.
- **More declarative action kinds.** The action list is complete for request-and-response devices; new transports go
  to the script library only, or the format becomes the worse language.
- **Scripts that compose commands.** Only declared templates, approved by exact text per device, as today.
- **Scripts in generated apps for control-only devices.** `LampRoku` (Sources/Lamp/Template.swift) is code that runs
  in the person's app, written by a person, and it exists because finding a Roku from an iPhone without SSDP is hard
  to get right. The agent already writes Swift, Kotlin and JavaScript in apps and can reach any device on the network
  from them (Mac apps carry the network client entitlement). A "plugin" there is just the agent writing app code,
  which it does. What may be worth adding for such devices is a skill with the protocol facts (Hue, Sonos, ECP, WLED),
  reviewable prose that costs Lamp nothing, and a hand-written block only when one proves hard, as the Roku's did.
- **Sharing scripts between people.** A shared script is a stranger's code with the person's device as its reach. The
  capability wall makes that survivable, not advisable. Shipped integrations are the sharing mechanism until there is
  a reason for another, and a revocation list comes before it.
- **WebAssembly, and a `JSContext` in Lamp's process.** Covered above.
- **USB.** `Find.usb` is refused today because Lamp has no way to reach such a device; a USB story is a helper with
  IOKit and its own threat model, not a side effect of scripting. Same for Bluetooth.
- **Automatic promotion to shipped.** Proven on one device of one model is not proven for everyone; a person reviews.

## Open questions

- **Long-lived sessions.** A Cast bridge, or a REPL, needs a session kept open from `launch` to `stop`. The runner
  today runs a sequence and ends; `DeviceApps.Run` keeps only `DeviceStream`s. Either the host stays alive for the
  app's life (a per-run process the lock already models), or sessions are Lamp-held objects the script names across
  runs through `device.memory`. The second is cleaner; it isn't needed until the Cast candidate.
- **A script's check in the setup loop.** `DeviceSetupPage` checks a waiting step every few seconds; a scripted check
  spawns the host each time. Fine for a few seconds of work; a check that opens a session each time (a pairing that
  prompts the TV) needs rate-limiting so the TV isn't prompted every few seconds. Probably: a scripted check runs at
  most every 15 seconds, and says so in its "Waiting…" line.
- **How much the probe can prove without a picture.** For a device whose bridge has no `look` the probe can only prove
  install, keys and removal didn't fail. The claim signal helps when the web library is declared. Is "it installed and
  the device didn't complain" enough for a "Worked" mark, or should the mark say what it proved?
- **The model's reach into the device's answers while writing.** The authoring loop sends the device's words to the
  model as the tool's error and as the probe's report. Should Lamp also offer the model a one-shot "ask the device"
  during setup (a guarded `device.http` GET from the chat, read-only, to the found device), so it can read `device-info`
  itself rather than guess field names? It would have found `ecp-setting-mode` in one call. The runner has every guard
  needed; the question is whether a read-only probe of a device the person hasn't finished setting up is something the
  person should be asked about first (it reads nothing secret and sends nothing, so my view is no).
- **Limits.** 64 KB of code, 200 calls, 120 s and 600 s budgets, 16 KB of memory are guesses; the experiment should
  set them.
- **The adb family's pairing variants.** Which members need `adb pair` with a code shown on the TV (a `field` on the
  step, carried into the script as a value, not a handle, since it isn't secret) and which connect directly; and
  whether a TV that is "unauthorized" keeps the dialog up long enough for the person to find it.
- **Where the probe's throwaway project lives and how it is cleaned.** It must be a `LampProject` for `Sandbox.run`
  and `DeviceSupport.write`; it must never appear on the desk (`makesNoApp`, as a device-setup conversation is). Likely
  a folder under `Device Builds` with a fixed id per integration, removed after each run.
- **Whether the team wants a Fire TV and a Google TV device for the experiment**, since the proving run needs both to
  say anything about variance within the family.
