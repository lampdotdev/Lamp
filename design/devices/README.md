# Lamp on every device

2026-10-21 · Matt Rubens

Lamp should know every device you own, exactly, and walk you through setting each one up, so a wish can land on whichever of them fits: the Mac, the iPhone, the Frame TV, the Kindle, even the dishwasher.

## Why now

At the Oct 21 sync, a Samsung Frame TV was showing a family calendar, the weather and Buzzer Beater. Getting there took a model walking a person through Tizen developer mode, the Samsung certificate manager and `sdb`, step by step. Claude and Codex refused to help scan the network or change a router; GLM did it. The reaction at home went from skeptical to "oh, that's kind of cool" once the calendar was on the TV.

Two things follow:

- **The setup is the product.** Each device needs a handful of steps before software can go on it. A model can talk someone through them, but Lamp can check each step and do most of them itself, the way it already does for the iPhone (Xcode, a team, pairing, Developer Mode).
- **The software is ordinary.** Once a device is set up, a TV app or a frame app is a small app like any other, and Lamp already builds, installs, looks at and changes those. What changes is the substrate: web code instead of Swift, so everything LampSupport gives an app (a store, notifications, AI, connectors) is written again for the web. The first kit's real cost is that second ecosystem, not the device.

## The model

Two ideas carry the whole plan:

1. **You have a set of devices.** Mac, iPhone, iPad, Apple Watch, Kindle, Frame TV, LG TV, an Android tablet, a photo frame, the dishwasher, the washer. Lamp finds them (on the network, over USB, through accounts) and keeps each that proves to be the person's as a record that names the exact device, not just its kind.
2. **Each device needs setup before software can go on it, and Lamp guides you through it.** Developer mode, a certificate, pairing, an account. Lamp checks every step itself, shows the next one as a card with its fix, and remembers where each device stands. Nothing is set up in advance: a device is set up the first time a wish needs it, or when the person picks it from the list.

Lamp shows a list of the devices it knows about, each with its exact model and whether it's ready, needs setup, or can only be talked to. A wish then names, or Lamp infers, the devices it's for. A device that isn't ready makes its next setup step the first card, before any question about the app.

Found is not owned. A scan sees the housemate's laptop and maybe the neighbour's; the setup steps are the ownership proof, since developer mode's menus, the Trust prompt and pairing all need hands on the device itself. A device joins the kept list only once one has succeeded, and what a scan found is shown for the moment, not remembered: device names carry people's names.

The Apple half already exists: Mac, iPhone and iPad apps, watch apps through the iPhone, the phone list in Try On, and the iPhone's setup check. The plan generalises those into one shape every device follows. The workshop stays the Mac: "every device you own" names where the software runs, not where the person sits.

## The device record

Each device is identified exactly, read by Lamp from the device itself and never guessed by the model. The record holds:

- **Who and what:** maker and model ("Samsung The Frame 55" (2022), "iPhone 16 Pro Max", "Kindle Paperwhite 11th gen"), its model id, and a name the person knows it by ("living room TV").
- **Software:** OS and version (Tizen 6.5, iOS 27, Android 13).
- **Screen:** size, resolution, points or pixels, LCD or e-ink, always-on.
- **Input:** touch, remote with a d-pad, Digital Crown, keyboard.
- **Features that change what's built:** Dynamic Island, Art Mode, NFC, HealthKit, camera.
- **How Lamp reaches it** and **where its setup stands** (Guided setup, below).

Where each comes from:

| Device | Lamp reads it from |
| --- | --- |
| Mac | `sysctl hw.model` and the display list |
| iPhone, iPad, Apple Watch | `devicectl`: marketing name, product type, OS version (watches are in its list; Lamp drops them today) |
| Samsung TV | The TV's own local API at `http://<ip>:8001/api/v2/`: model, resolution, Tizen version, whether it's a Frame |
| LG TV | webOS device info over the developer connection |
| Android, Fire, photo frames | `adb shell getprop`: model, Android version, screen |
| Anything else on the network | What it announces over Bonjour and UPnP |
| Appliances | The vendor account (SmartThings, LG ThinQ) or Home Assistant |

The exact device is what the agent is told ("Frame TV: Samsung The Frame 55", 3840×2160, remote, Tizen 6.5) and what picks the simulator for Apple devices (Try On can already choose a simulator by name); a shared wish says the kinds of device it needs, with the exact model it was made on as information.

## Three kinds of device

What "write, deploy, share" means depends on what the device can do:

| Kind | Examples | Write and deploy | Setup is mostly |
| --- | --- | --- | --- |
| Runs software | Mac, iPhone, iPad, Watch, Samsung and LG TVs, Android, Fire, Roku | Lamp builds for it, installs it, looks at it and uses it: a device kit (next section) | Developer mode, signing, pairing |
| Shows things | Photo frames, Kindle, Kobo | A kit when it exposes a standard install path (a frame that runs Android apps); otherwise a display fed by a device that runs software | Whatever lets it install, or the browser it has |
| Is talked to | Dishwasher, washer, router, lights | Nothing runs on it: the software runs on another device you have ("tell me on my phone when the laundry's done", a TV tile with the dishwasher's time left) | Connecting its account or local API |

Apps for devices that run software **stand alone**: once installed they fetch their own data and need nothing from the Mac. Lamp is the builder and installer, not a server. AI inside a standalone app (a TV app asking a model) needs keys on the device, as iPhone apps already carry away from the Mac; leave it out of TV apps at first.

**Sharing** works as it does now: a shared wish says which kinds of device it needs, and the person who opens it sets those up through the same guided steps.

**Rooting is the user's own step.** Lamp builds for any device that exposes a standard install path (a vendor developer mode, or `adb` on a device that already allows it), however the device got there. Some cheap devices ship with no path at all: the smaller photo frames, some tablets and e-readers, and they reach one only after the owner unlocks them. Unlocking the bootloader, rooting, jailbreaking: whatever the platform calls it, it's one step, taken on hardware the person owns, and theirs to take. It defeats the device's own protections, and what that costs is what the choice turns on, so the card says it before anything starts: a wrong step can brick the device, the warranty may be void, banking apps refuse rooted Android, streaming falls back to SD, and the vendor's own updates often stop installing on an unlocked one.

The step also shifts with every firmware release, and a stale guide costs hardware, so it stays where it's kept current. Lamp doesn't perform it and doesn't walk anyone through it: the device's card points to its community (XDA, LineageOS's install pages, the jailbreak project's own guide), the one step there that isn't Lamp's to check. Once the person has taken it and the device speaks a standard bridge (`adb`, usually), Lamp's kit treats it like any other target: the same find, scaffold, build, install, look, use and logs. Nothing about the software changes, only how the device became installable, and that was never the agent's business.

## Device kits

Each kind of device that runs software gets a kit with the same seven parts the iPhone path already has. The agent writes code; Lamp does everything that touches the device.

1. **Find:** list the devices of this kind and identify each exactly.
2. **Set up:** check each step and offer its fix (next section).
3. **Scaffold:** the project the agent writes into, plus Lamp's own support file, rules for the agent and a skill with the platform's APIs.
4. **Build and package:** in the app's sandbox, as every build is now; signing happens as Lamp, on a copy.
5. **Install and launch:** through the device's bridge, run as Lamp (as `devicectl` is for the phone), on the device chosen in Try On.
6. **Look and use:** the app's own driver in a dev build (below), else the bridge's screenshot or the vendor's emulator, for `look_at_app`; the remote's keys for `use_app`.
7. **Logs:** the device's log into the app's log, so a crash reaches the agent.

A wish can span devices the way it spans the Mac's parts today: `Widget/`, `Watch/` and `Share/` already set the pattern, a target as a folder of its own with its support file and rules, and `make_app_for` gains the new kind. "Put this on the TV" adds `TV/` to the project, and a wish with a Mac app and a TV tile is one project holding both.

The loop has to stay fast, or the passes the person watches go away: a bridge's package, install and launch is seconds each, and a turn is many passes. So where a device's dev mode reloads from an address it points at, the Mac serves the app over HTTP while the agent works and the package is made only at the end; and the dev build carries its own driver, as a Mac app's does (`LampDriver`): a debug endpoint on the network that reports the app's screen as text and performs its own actions, rather than a screenshot through the bridge and a remote pressed a key at a time. Its requests are signed with the app's token, as a Mac app's are, since a sideloaded personal app's dev build is the app itself and the network is shared. Both are for building only, so Lamp stays the builder and installer, not a server; the installed app fetches its own data as ever.

The bridges, from what's known so far (to confirm on each device):

| Device | Bridge | App | Install |
| --- | --- | --- | --- |
| Samsung TV (Tizen) | `sdb` + `tizen` CLI | Web app, packaged as `.wgt` | `sdb connect` → `tizen package` → `tizen install` |
| LG TV (webOS) | `ares-*` CLI | Web app, packaged as `.ipk` | `ares-setup-device` → `ares-package` → `ares-install` |
| Android, Google TV, Fire, frames | `adb` | APK | `adb install`, `adb shell am start` |
| Roku | HTTP to the device | BrightScript zip | Upload to its developer page |
| Apple TV | `devicectl`, Xcode | Swift app | As the iPhone |

Lamp downloads each bridge itself when it's first needed, checked as it checks Claude Code and Codex. "Make it work on my iPhone too" becomes "put this on the TV": the same tool, given a new kind.

Tizen and webOS apps are both web apps, so one web kit covers both TVs and LG after Samsung is nearly free; Roku's BrightScript is the exception.

## Guided setup

Every device moves through the same states: **found → each setup step → ready**. Lamp checks each step itself, never the model, shows the next one as a card with its fix, and keeps where the device stands in its notes ("Frame TV: developer mode on, certificate made").

Ready is perishable. A dev-mode install is designed to rot: LG's session lapses (below), Samsung's certificates expire, debugging toggles itself off, an accepted key is forgotten. Lamp re-checks a ready device when it's reachable, warns of what's about to lapse where the device says so, and renews what it can by running the same steps again. A kit's job is not only to get software onto a device but to keep it there.

The iPhone is the one device this already exists on, and the clearest example of Lamp renewing rather than the person: a free Apple ID signs an app onto the person's own phone with no paid account, and iOS stops launching it after seven days. Refreshing is re-signing and reinstalling from a paired Mac, the app's data kept (the scheme AltServer runs for AltStore), and Lamp sits in exactly that spot: always on the Mac, already paired with the phone, borrowing a signing session from Xcode rather than holding the person's Apple ID. The catches: Apple caps free accounts (unpublished; the sideloading world reports about ten app ids a week and three apps installed at once), and the wish exists only while Lamp keeps refreshing it, which cuts against apps standing alone. It's the free tier; the paid account stays the good path.

The Frame TV, as the first example to make real:

1. **Found:** the TV answers on its local API; Lamp reads its model and Tizen version.
2. **Developer mode:** the card shows the steps on the TV's own remote (Apps, then 1-2-3-4-5, then Developer mode on, with this Mac's address filled in for the person to type).
3. **Certificate:** Lamp makes the author certificate with the Tizen CLI, then opens Samsung's sign-in for the distributor certificate (the step a model walked a person through by hand; whether it can be done without Tizen Studio's window is the first thing to confirm).
4. **Connected:** `sdb connect` succeeds and the TV is listed.
5. **Ready:** a test app installs and opens; the card goes away.

Other devices, in the same shape:

| Device | Steps after "found" |
| --- | --- |
| iPhone, iPad | Xcode, a team, pairing (the Trust prompt), Developer Mode (exists today) |
| Apple Watch | Its iPhone set up, the watch paired with it |
| LG TV | LG account, the Developer Mode app, its session extended (it lapses after about 50 hours, so Lamp reminds) |
| Android, Fire, frames | Developer options, wireless or USB debugging, accepting this Mac's key |
| Dishwasher, washer | Connecting the account (SmartThings, ThinQ, Home Assistant) |

## Integrations: devices as data

The kits so far are written by hand: Apple's (Devices.swift, PhoneSetup.swift), Android's (Android.swift, AndroidSetup.swift) and the TVs' (TVs.swift, Sdb.swift, TizenSigning.swift, TVSetup.swift). Each finds its devices, reads their identity, walks the person through setup in a window of its own, and installs through its own bridge. Writing one per device doesn't reach "every device you own". The way out is the one connectors already took: a service that isn't listed is declared by the app's own code (`LampAPI.own`: its address, the page where the key is made, the steps, how the key is sent), and Lamp draws the Connect sheet and does the sending. A device Lamp doesn't know is declared the same way, by the model, as an **integration**: data that says how to find the device, read it, set it up, put software on it and look at it. Lamp checks the data, acts on it with a small set of primitives it owns, and draws every step's interface itself.

### What an integration holds

An integration is a JSON document, checked against a schema Lamp ships; nothing in it is code Lamp runs.

- **Find.** How the device announces itself: an SSDP search target, a Bonjour service type, a USB vendor and product id, or an HTTP probe (a port, a path, what the answer must contain). A match is a found device, shown for the moment, never kept until a setup step has worked.
- **Identity.** Where each field of the device record is read from the device's own answers ("model is `model-name` in the XML from `:8060/query/device-info`"). The model says where; Lamp reads the value. The record stays read from the device, never guessed.
- **Setup steps.** Each has what the person does (short numbered lines, held to word limits as the chat's cards are), what's shown to them (this Mac's address, a code, a QR code), what they type (a passphrase or a PIN), what they accept (below), and a **check** Lamp runs with the primitives: a port that answers, a value in the device's answer, the bridge listing the device. A step is done when its check passes, never because the model or the person said so.
- **Bridge.** Install, launch, look, use and logs, each a short sequence of primitives with placeholders Lamp fills (`{package}`, `{appID}`, `{address}`, a field the person typed), checked to a safe alphabet. The model never fills a placeholder.
- **App kind.** What's built for it: one Lamp owns (Swift for Apple, Kotlin for Android, the TVs' web app), or one the integration declares: the scaffold's files, the rules the builder is given, and the package step, which runs in the app's sandbox like every build, so it may be any command. A kind with a preview on this Mac (the TVs' web app) is looked at there; one without is looked at through the bridge.
- **Provenance.** How each part is known (below), and the device software version it was known on.

### What Lamp acts with

Every step and bridge is made of these and nothing else. Anything else fails the schema and goes back to the model with the reason.

| Primitive | What it does | Held to |
| --- | --- | --- |
| `http` | A request to the device: GET, POST, a file uploaded as a form, digest or basic sign-in with a field the person typed; a value read from the answer by a JSON or XML path | Only the address the device was found at, in a private range; no redirects; answers cut off at a size |
| `probe` | A TCP connect, an SSDP search, a Bonjour browse | Read only |
| `stream` | A TCP connection read line by line, for a device's log | The device's address; read only, into the app's log |
| `field` | A passphrase, PIN or password the person types | Kept in the Keychain under that device, sent only to it |
| `show`, `qr` | A value or a QR code for the person | Lamp's own values (this Mac's address, a pairing code) |
| `wait` | Hands on the device; Lamp runs the step's check until it passes | Polls only the step's own check |
| `vendorSignIn` | The vendor's page in the browser, answered on a listener on this Mac's loopback | The card shows the page's domain before it opens |
| `ssh` | A command on the device | Below |
| `tool` | A program on this Mac | Below |
| `link` | A page for the person to read | The only form a rooting step ever takes |
| `bridge` | A bridge Lamp ships: `devicectl`, `adb`, `sdb`, Tizen signing, LG's key exchange | Code Lamp ships, reviewed like any other |

**SSH**: the integration may compose commands for the device, because the device is the person's and so is the call. Each command template comes with the model's explanation in plain words, and before it first runs on a device the person approves it on a card like the shell approval card: the command, what it's for, and what they accept ("Runs on your TV. It can change or break the TV's software."). The approval is for that template's exact text on that device, so Play doesn't ask each time and a changed template asks again. Lamp's side stays fixed: only the device's address, its host key pinned the first time, no forwarding of ports or of an agent, and a key Lamp keeps in its own folder, which the agent's sandbox closes.

**Tools on this Mac**: Lamp ships a list of tools it downloads and checks (a checksum and a signature, as it checks Claude Code and Codex, and as `updates/api/engines.js` holds them), and runs those as itself with the argument templates the list gives them. An integration may name a tool that isn't on the list; it's downloaded the same way but runs in a sandbox of its own (`sandbox-exec`: its folder, the network, temp, nothing of Lamp's or the person's), approved by the person as an SSH command is. What runs unconfined is only ever what Lamp shipped.

### One setup window, drawn from the data

The hand-written setup windows (Android Setup, TV Setup, and the iPhone's) become one window drawn from the integration's steps: the list of steps with done, next and not yet; the next step as a card with its numbered lines, the values shown large, its field or QR code, one button that runs its primitive, and a check line that goes from "Waiting for the TV…" to done by itself. The same card is what the chat shows when a wish needs a step, and what Settings → Your Devices opens. Each kind of card gets its entries in the gallery.

**What you accept** is chosen, not written: an account, a risk to the device's software (it may stop working; the warranty), data wiped, updates that stop, protections turned off, a command run on the device. Lamp writes each sentence itself, so no integration can play a risk down. Each step also says how it's known: **Checked by Lamp** (its check passed on a device of this model and version), **Done by people** (it passed after hands on the device), or **Not tried yet** (written from what was read). A step not tried yet says so on its card.

### Where an integration comes from

A device with no integration is set up in either of two ways, and the person can start both:

- **From the list.** A found device Lamp doesn't know shows in Settings → Your Devices with Set Up…, which starts the work.
- **From a wish.** A wish that names a device Lamp doesn't know ("put this on my Roku") starts it before anything is built, as a device that isn't ready makes its setup the first card.

Who writes it: by default the builder, in its own turn, through a new tool that hands Lamp the JSON; Lamp checks it and answers with what's wrong, as `ask` is turned away when it's too long. Optionally a **Research model**, chosen in Settings like the decision and image models: an open model with the web and the community's guides, which answers what the builder refuses and keeps the builder to writing apps. The researcher only writes data; it never touches the device.

Once a step's check has passed it's kept with the integration, on this Mac, in Lamp's folder, beside the ones Lamp ships (`Resources/Devices/`, the kits' steps as data). Pooling what people's Lamps learn comes later; the format already carries what it needs (model, software version, how each step is known), so it can be added without changing it.

### What the kits become

| Kit | Becomes data | Stays code |
| --- | --- | --- |
| Apple | The steps: pairing, Developer Mode, a team | `devicectl`, Xcode, team signing, simulators, LampSupport |
| Android | Finding (adb's list), identity (`getprop` paths), the steps (developer options, debugging, the Mac's key) | adb as a bridge, the tools' download, the emulator, the Android scaffold |
| Samsung TV | SSDP, identity from `:8001/api/v2/`, developer mode, the connection | sdb's protocol, Tizen signing and Samsung's certificate sign-in, `config.xml` |
| LG TV | SSDP, identity, Developer Mode, the passphrase | the key exchange and the session's renewal, or its commands as approved SSH once integrations can |

The shipped ones are marked Checked by Lamp, and go through the same window and cards as any other.

### Roku, the first one built this way

Roku is the device to prove it on: everything it needs is HTTP and TCP on the local network, so its integration is data from end to end, with nothing new in code but the primitives. From Roku's developer documentation (each to confirm on a Roku):

- **Find**: SSDP with the search target `roku:ecp`; the answer's location is its control API on port 8060.
- **Identity**: `GET :8060/query/device-info`, XML: `model-name`, `model-number`, `software-version`, `ui-resolution`, `developer-enabled`.
- **Setup**: developer mode, on the remote (Home three times, Up twice, Right, Left, Right, Left, Right), where the person sets a password for the developer installer; checked by `developer-enabled` being true and the installer on port 80 answering. The password is a `field`.
- **Install and launch**: the package (a zip with a `manifest`, BrightScript and SceneGraph XML) uploaded to `:80/plugin_install` as a form, with digest sign-in as `rokudev`; it opens by itself, and `POST :8060/launch/dev` opens it again.
- **Look**: `:80/plugin_inspect` asked for a screenshot, then the picture fetched; a real picture of the TV, which neither TV kit has.
- **Use**: `POST :8060/keypress/<key>` with Roku's key names (Home, Up, Select, Back, …).
- **Logs**: the debug console on port 8085, as a `stream`.
- **App kind**: BrightScript, declared by the integration: a scaffold, the rules, and the package step (a zip, made in the app's sandbox). No preview on this Mac: Roku has none, so looks go to the TV.

Roku's whole integration is written once by the model as a test of the schema, checked on a Roku, and shipped as the first entry that wasn't a kit.

## Wishes, Device Control and refusals

**Wishes.** "Put our calendar on the Frame TV" names a device; "remind me when the laundry's done" names two (the washer, talked to; the phone, where the reminder runs). Lamp works out which devices from the list, as it picks Mac or iPhone today, and passes the exact devices to the agent with the request. A device not yet ready makes its next setup step the first card.

**Device Control as a starter.** Bruno's idea from the sync, made the first thing a person sees of this: one starter wish that asks for macOS's local network permission, finds what's on the network, shows each device with where its setup stands, and offers a wish for each ("A family calendar on the Frame TV", "A photo frame for the hallway tablet"). A click makes that wish with the device chosen. Other starters become surface-curious: Buzzer Beater and Today each offer a TV version.

**Refusals.** Claude and Codex balk at what looks like hacking a device. When Lamp does the finding, setup and installing itself, the model is only asked to write an app for a known device, which none of them refuse. GLM through OpenRouter stays the choice for open questions such as "what can I do with my router".

## Order of work

1. **The device record and list, for what Lamp already supports.** Exact identity for Mac, iPhone, iPad and Watch (watches stop being dropped), shown in one list. Done.
2. **Hand-written kits for Android, Samsung and LG**, to learn what a kit needs before generalising it. Android is merged; the TVs are on their way (Samsung tried on a Frame TV, LG written from LG's tools and untried).
3. **The integration schema and its primitives**, with the one setup window and its cards drawn from data, and the approval card for SSH and tools.
4. **Roku as the first integration that isn't a kit**: written by the model through the new tool, checked on a Roku, shipped.
5. **The kits' steps as data**, Android's and the TVs' first, then Apple's, so every device's setup is the same window and cards.
6. **The Research model** as an optional route in Settings.
7. **Device Control as a starter**, once there is something set up to show.
8. **Talked-to devices** through accounts (SmartThings, ThinQ, Home Assistant), as connectors.
9. **Pooling** what people's Lamps learn, later.

Meanwhile, as agreed at the sync, everyone tries a cheap device and notes how its setup went; those notes become each kit's setup steps.

## Figuring out what isn't known

A kit encodes a device's steps once someone has walked them. The first person to bring a device, or a firmware that moved its menus, meets steps nobody has written for Lamp yet; the sync's TV got there by a model reading the docs and walking a person through by hand. That hand-walking is the thing to build: the open questions below matter less as exact shapes to fill in than as tests of the framework that turns any unknown step into a walked-through one.

That makes two model jobs, kept apart: the builder, only ever asked to write an app for a known device (Refusals), and the researcher, which reads and proposes but is never asked to touch the device. When a check fails and Lamp holds no step for it, the step goes to research and comes back as candidate steps in the same shape a kit's are written in. The research is an open model with the web and the community's guides (XDA threads, the vendor's docs, a jailbreak project's own pages), the models that already answer "what can I do with my router" (see Refusals), plus local evidence of the kind [rea](https://github.com/morluto/rea) gathers with agents: what a device's app says on the network, an APK's decompiled methods, a firmware's contents. The same evidence answers the bridges and the record's "how Lamp reaches it": an undocumented local API is reverse-engineered, not documented. Lamp verifies what it can itself (run the command, read the device's answer), the person does what needs hands on the device with the candidate's words, and once a path has worked it's kept with the device's record, so the next person gets checked steps instead of a fresh research pass. What the kits ship is what the framework once worked out, and the cheap-device notes above are its first inputs.

Research proposes; Lamp's checks and the person's hands decide. A discovered step is held to the same lines as a written one: what defeats a device's protections stays the owner's own step, and analysis runs only on the person's own devices.

Kept once is one person's; the point, later, is to pool it. What Lamp learns should accumulate in one place, keyed by what the record already holds (maker, model, the exact software version: a firmware release moves menus and breaks bridges, and a step verified on Tizen 6.5 is a guess on 7.0), and shipped with Lamp the way skills are: bundled, versioned, read from the app's own copy, so a person's first run of a device finds steps someone else already walked. A device that drifted from the version a step was verified on gets research, not a quiet failure. What a person's Lamp learns would flow back the same way, with their say-so: model, version, step and outcome, never a device's name, never the network it sat on. For now integrations are kept on each Mac (Integrations, above), in the format pooling will need.

Every entry carries how it's known: Lamp checked it, a person's hands completed it, or it was read somewhere and never tried. The mark travels with the step, so what a person is shown says what it is, and a step that fails for a few people in a row goes back to research rather than staying on the list. What's possible is the same base as how to set up: whether `sdb` takes a screenshot on this Tizen version, which remote keys webOS forwards, whether Art Mode accepts writes: the open questions below are its first entries.

## Open questions

- [x] What the research pass runs on: the builder by default, or an optional Research model chosen in Settings (Integrations, above).
- [x] How a researched step is shown: Checked by Lamp, Done by people or Not tried yet, on its card; kept on this Mac for now.
- [ ] What a person's Lamp reports back so others get its steps (model, version and outcome only), and with what say-so? Later, with pooling.
- [ ] How much of setup lives in evidence at all: many steps are remote-menu presses and account flows found in forum posts, not in binaries?
- [ ] Can the Samsung distributor certificate be made without Tizen Studio's window, from the CLI and a browser sign-in?
- [ ] Does `sdb` take a screenshot, or does looking at a Samsung app need the emulator?
- [ ] Which remote keys can the bridges press on Tizen and webOS, for `use_app`?
- [ ] Where Lamp keeps the device list: in its notes about the person, or a record of its own that the notes point to?
- [ ] How a standalone TV app gets AI, if it should: keys on the TV, or no AI on TVs?
- [ ] Does a typical cheap frame or tablet, once unlocked, speak `adb`, or only the vendor's own shell?
- [ ] Can a dev-mode TV app load from an address the Mac serves, so passes don't wait on packaging, or only from an installed package?
- [ ] Does the Tizen SDK write to Art Mode at all, or is putting a person's art on the Frame only Samsung's own path?
- [ ] Where the device list lives in the interface: a tab of its own, part of Building, or only inside wishes?
- [ ] Which Roku models still allow the control API's key presses from the network by default, and what the setup step says when one doesn't?
- [ ] Does the integration's own app kind (scaffold, rules, package step) stay data, or does a kind that proves itself (BrightScript) become code Lamp owns, as the web TV kit is?
- [ ] How an approved SSH command is shown again later, so the person can see and take back what they allowed on each device?
