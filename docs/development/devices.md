# Devices as data, games and screens

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

## Devices as data

A device Lamp has no kit for is taken on as an **integration** (`Integration`, Integration.swift): JSON the builder
writes and hands Lamp with `device_integration`, the way an app declares an unlisted service with `LampAPI.own`. Its
format is the `device-integrations` skill, which `Agent.deviceRules` names in every prompt (it isn't in the skills'
list). It says how the device is found (`find`: SSDP, Bonjour, or an HTTP probe of what answered Lamp's scan; USB is refused until Lamp can reach such a device),
where each field of its record is read (`identity`: a request and a JSON or XML path; the model says where, Lamp
reads), its setup `steps`, the `bridge` (install, launch, look, use, logs) and the `app` kind. Nothing in it is code
Lamp runs: every step and bridge is a list of Lamp's primitives (`IntegrationAction`), and `IntegrationCheck.problems`
(with `unknownKeys`) turns anything else away with plain reasons, which the tool answers as an error for the model to
fix. Values in a request or command are placeholders Lamp fills (`Placeholders`: `{address}`, `{mac}`, `{package}`,
`{field:<key>}`…), each checked to a safe alphabet; what the person typed goes only into a sign-in, a form, a header or
a body, never a path or a command, and a command's values are quoted for the shell. Kept integrations are in Lamp's
folder (`Integrations.folder`), beside those Lamp ships in `Resources/Devices` (the Xbox's and the Roku's), which win over a written one with the same id, and whose id `device_integration` refuses.
The model can only say a step was read (`known.how` "read", with its source); Lamp marks it Checked by Lamp or Worked
before (`Integrations.mark`: done by hand or not, by whether it needed hands on the device) once its check passes on a device, with that
device's model (as its model step read it, once that's passed, which is then the kept device's model too) and version, and keeps the
mark while the step's text is unchanged. A shipped integration's marks are written in the repository, never by Lamp: a copy in
Lamp's folder would be shadowed, and those an earlier Lamp wrote are taken away at launch (`dropShippedCopies`). An integration the builder sends with an
`app` is held to a whole lifecycle (`IntegrationCheck.lifecycle`): `stop`, `remove` and `type` each there or named in
`bridge.lacks`, every picture its scaffold names written or drawn (`icons`), and each `support` library named in its
rules; one kept before this was asked is still read, and Lamp's shipped ones pass it (their test). Once a device is set
up, its setup window offers a test run (`IntegrationProbe`, `DeviceTrialCard`): the integration's own scaffold made in
Lamp's `Probes/` folder and taken through Lamp's own ways with an app (`DeviceApps.install`, `picture`, `press` on the
arrows and select only, `type`, `stop`, an install over the open copy, each install of a new build as a change is, since an Xbox won't open the same
version put on again, and `DeviceApps.remove`), holding the device as
an install does, stopping at the first stage that fails and taking the app off again. Its report goes with the next
request of the device's setup conversation (`Agent.deviceSetupNote`), whatever the engine, and a run that passes marks
the bridge (`bridge.known`, Lamp's alone: refused from the builder, kept while the bridge is unchanged, never written
to a shipped integration).

The primitives and their guards (DevicePrimitives.swift, DeviceRemote.swift), which every place goes through:
`DeviceHTTP` (only the address the device was found at, which must be private or link-local and never this Mac, by loopback or by its own addresses (`DeviceAddress.thisMac`), so
nothing reaches Lamp's gateway; a path that stays a path; no redirect; the answer cut off at `limit`; a password only
for the device's own challenge, in the scheme declared, once: `Guardian`; over HTTPS, with `https: true`, the device's
own certificate is kept the first time per port and a different one refused, as SSH host keys are, `DeviceTLS`;
for a device that makes itself a new certificate from a root of its own (Xbox's Device Portal does, whenever it
restarts), the integration names where it serves that root (`certificateRoot`), which Lamp reads once over the
connection the first certificate was kept on and keeps beside it, and a later certificate is taken only when that
root signed it, and
nothing secret goes to a device whose certificate isn't kept, so a read while finding it sends no password), `DeviceProbe` (TCP, SSDP, Bonjour;
read only), `DeviceStream` (a TCP log read line by line), `DeviceFields` (what the person typed, kept per device the
way `AppSecrets` keeps an app's), `DeviceQR`, `VendorSignIn` (the vendor's https page, answered on a loopback listener
at a port of its own; the card names the page's domain), `DeviceSSH` (the device's address only, its host key pinned
in a file of its own the first time, none of the person's SSH settings, no agent, no forwarding, Lamp's key or one the
device gave, both in Lamp's folder) and `DeviceTools` (Lamp's list, run as Lamp by full path with its own arguments and
secrets on standard input; anything else downloaded over https, checked against the integration's SHA-256 and run under
`sandbox-exec` with a profile of its own: its folder, the system, the network). An SSH command template or a tool runs
only after the person approves its exact text on that device (`DeviceApprovals`, `DeviceCommandCard`, with the model's
explanation and Lamp's sentence of what they accept); a changed template asks again.

Setup is one window for every such device (`DeviceSetupWindow`, `DeviceSetupPage`) and one card for a step
(`DeviceStepCard`, drawn from the step: numbered lines, Lamp's values shown large, a QR code, the field, a link, "What
you accept" from `Integration.Acceptance` in Lamp's words, `IntegrationWords.accepts`, so no integration can play a
risk down, the mark, one button and the check's line). A device has one `DeviceSetupModel`, which the window and the
chat's card (`.deviceStep`, `DeviceStepLine`; in the sidebar a line that opens the window) share. A step that needs
hands on the device (`wait`) is checked again every few seconds while it's shown. A step can also have Do It for Me, from a skill that
says it does that step for the integration (`setup-for` its id), with no Swift for that device: "Do It for Me" in the
TV guide. `IntegrationRunner` runs steps and
sequences and keeps a device (`Integrations.Kept`, in Lamp's folder) only once a step has passed on it: a device found
is shown for the moment, never kept. A device whose certificate isn't the one kept (reset, or its developer mode turned
on again) is refused until the person reconnects it: the step's check or the install that met it puts a reconnect card
where its setup card goes (`DeviceReconnectCard`, `DeviceSetupModel.certificateChanged`), and Reconnect lets the kept
certificate go and starts its setup over from the first step (`reconnect`, `Integrations.startOver`), so the sign-in goes
only to the device whose new certificate the first request keeps; an app waiting on it goes on once that setup is done.
Only the person's click trusts a new certificate. Settings → Your Devices has Reconnect… and Forget… for every device
Lamp set up itself (an integration's, a TV; not a phone, whose pairing is the Mac's), Forget taking its record, its
certificates and keys, what was typed for it and its approvals (`Integrations.forget`, `TVs.forget`, `AndroidTVs.forget`).

**Set up or possible** (`Device.isSetUp`). A device set up with Lamp is the person's; one Lamp only found on the network
is a possible device, which may be a neighbor's on a shared network. Set up isn't ready: a device part-way through
its setup, away from the network, or needing new credentials is still set up. This Mac, every Android device adb lists
(plugged in or connected over Wi‑Fi from this Mac), an Android TV Lamp keeps (`AndroidTVs`, while adb can't see it
too) and the emulator are; an iPhone or iPad once it's paired with this
Mac or plugged in, before Developer Mode; a watch once Xcode lists it paired; a TV or an integration's device once it's
kept (`Device.kept`, read from `TVs.kept` and `Integrations.kept` each time the devices are read, so setup, Forget and
finding it again move it). Nothing is migrated: the kept records already say it. A possible device is never called the
person's (the device line, `Places.known`, `network_devices`, the naming call's `AppName.seen`, the device card's
question), but what Lamp can do with one like it is still said, and an app can still control one (a Roku) without
setting it up; allowing it on the device card lets the agent use it and doesn't set it up. Try On offers it as Set
Up… (`TryOnMenu.item`), whose setup chooses it once done (`setTVDevice`, `setDeviceAppDevice`), and a device app with
no device chosen goes only on the one set up (`DeviceApps.device`).

An integration whose `app` is declared makes its device a kind of app (`Platform.device`, with the integration's id in
`LampProject.integration` and meta.json; DeviceApps.swift), with no Swift of its own for that device: Roku, the first,
is all data. Each such integration is a row of the table of devices, which the naming call names devices by, and
`make_app_for` takes its id alone. The scaffold is the declared `files` (`DeviceApps.fill`, `{{NAME}}` filled, and
`.lamp/device-app` marking it made), the builder's rules are the declared `rules` inside the usual ones
(`Agent.devicePrompt`), and the build is the declared `package` command run in the app's sandbox like every build, its
`output` then copied through `AppFile` into Lamp's own folder (`Device Builds`), which is all that's ever sent. Its icon
is the one Lamp draws for every app: the kind names where the device's manifest looks for it and at what size
(`app.declared.icons`, `"images/icon_focus_hd.png": "290x218"`, and a Roku's splash screens), and Lamp draws it there
before every turn and build (`DeviceSupport.write`, the icon on a dark tile, as the Xbox's logos are, and the tile alone
until the app has an icon, since the manifest names the files), Lamp's own like the building blocks; the agent never
draws one. Every other kind already carries it: the Mac's and iPhone's, a watch app's catalog, Android's launcher
icon, a Samsung TV's `icon.png`, an LG TV's two, and the Xbox's logos. Play,
Open and every look put it on the device chosen under Try On (`Store.setDeviceAppDevice`, the integration's devices;
one not set up opens its setup window, and with no choice the only one found is used) with the bridge's `install` and
`launch` (`Store.installOnDeviceApp`), reading `logs` into the app's log; a device not set up gets its next step in the
chat instead. `look_at_app` is the bridge's `look` picture with what the device answered the install
(`IntegrationRunner.Outcome.answers`, as plain text) and the log, and, where the bridge has `screen`, the screen as text
(`keep: "screen"`, `Store.deviceAppScreen`: a Roku's ECP `/query/app-ui`, SceneGraph's tree of the app's nodes with their
text and focus, its indentation taken out and cut at 12,000 characters), shared with the agent as pictures are; `use_app` takes only `key` (Lamp's names in
`bridge.keys`, each pressed with `use`), `type` (the bridge's `type`, once per character as `{text}`, which in a path
Lamp encodes down to letters and digits; a Roku's `Lit_`) and `wait`, then the picture and the screen as text again. Stop runs the bridge's `stop` (a Roku's
`/exit-app/dev`), and presses `home` when there's none or the device refuses it. Lamp can't tell whether the
app is still open on the device, so Play always puts it there again. Such an app can be one of a wish's apps, in a
folder named for its device (Roku/, the "Wishes" guide), where all of this works in its folder as it does at a wish's
root. Such apps aren't shared yet. Lamp ships the Roku's
integration (`Resources/Devices/roku.json`): a channel in BrightScript with Lamp's building blocks, its icon and splash
screens, and a bridge whose `remove` is the developer installer's Delete, so deleting a wish takes the channel off the
Roku (a package that isn't wrapped has no names, so `DeviceApps.removeEverywhere` removes the device's one copy, and only
while it's still this wish's: `lastOnDevice` notes which app each device took last). Its
mobile-control step reads `ecp-setting-mode` from device-info, which Roku's ECP page doesn't list but Rokus report, and
asks only for Enabled, never Permissive. Its developer-mode step's button presses the remote's secret keys over ECP (`run`), which that
setting allows; the license and the password stay the person's, on the Roku. Its Do It for Me is the `roku-developer-mode` skill, all data: the same keys
(pressed only while `developer-enabled` isn't true, and never again after a failure part way), then the person's
installer, license and password while Lamp waits for the Roku's restart, then what the step itself checks.

**Lamp's building blocks on devices** (`DeviceSupport`, DeviceSupport.swift): TVs and declared app kinds get `LampAI`,
`LampStore` and `LampAssets` as Mac, iPhone and Android apps do, under the same names and with the same advice in their
comments, so a change to one of those is made to all of them. A declared kind asks for them by library in
`app.declared.support` (`"web": "Web/lamp.js"`, `"brightscript": "components/Lamp"`); the TV kit always has the web one
in its `Web/lamp.js`, the Xbox's integration asks for it too. The web library is plain ES5 with Promises
(`DeviceSupport.webJS`, LampStore on localStorage), and ends with `LampQR` (`DeviceSupport.qrJS`), which draws the QR
code a page shows phones: Kazuhiko Arase's QR Code Generator (`Resources/WebLibraries/qrcode`, MIT, put there by
`scripts/update-qrcode.sh` from one npm release, checked against its SHA-512), inside lamp.js with its license, since a
join link with its credential is longer than the encoders the agent writes for itself tend to hold; the BrightScript one runs each LampAI call in a Task node
(`LampAITask`), since a Roku refuses network calls on its render thread, and keeps LampStore in the registry. Lamp writes
them before every turn and build (`DeviceSupport.write`, from `Template.writeOwnedFiles` and `writeSupport`), the agent
can't delete them, and versions leave them out of their names and diffs. How an app reaches the gateway comes in two
halves, since none of these devices can be written to after an install the way `Adb.tellApp` writes an Android app's
storage. Where Lamp is (`DeviceSupport.installValues`: this Mac's Bonjour name, then its addresses, and the port) isn't
secret and goes into Lamp's own file in the package as it's made (`DeviceSupport.fill`: the TV's staged copy as it's
packaged, the Xbox's MSIX payload, a Roku's zip made again), never into the app's folder. The token is never in the
package: Lamp opens a claim for the app just before it puts it on a device (`DeviceSupport.Claims`, from that device's
address, for half an hour), and the app, finding no token kept, asks `/app/claim` for it and keeps it on the device. The
TV preview needs neither: LampAI's calls reach Lamp through the web view (`TVPreview`'s `lampGateway` handler), as the
app. The gateway listens on the network while a TV app is set to open on a TV, or a device app that takes the building
blocks is being put on a device or has been (`Store.syncLocalNetwork`, `DeviceApps.wentOnADevice`): listening is what
has macOS ask about the local network, so an app made for a device and never put on one doesn't; from the network it answers a browser's preflight and lets the device's page read the answer
(only there: nothing on this Mac is answered across origins), and admits this Mac's own addresses as Host beside its
name (`Store.isMacHost`), since a web page can't choose its Host and these devices don't resolve `.local` names.

**When Lamp looks.** A look (`Store.refreshDevices`) runs devicectl for the phones, adb for Android's and one search
of the local network for the TVs and devices, and each of these can have macOS ask whether Lamp may use the local network:
devicectl finds phones over Wi‑Fi too, and macOS counts the tools Lamp runs as Lamp. So Lamp looks only once the person
is doing something with a device: Settings → Your Devices, Add a New Device and Look Again, Try On opening (Lamp's and the
chat's, `SidebarCommand.tryOnOpened`), pairing, a device's setup, Play on a phone, a TV or a device, a game given the
Xbox, `device_integration`; a wish named for a phone, a TV or a device (`AppName.Suggestion.forPhone`, `forDevice`, then
`Store.lookForWish`, which names the wish again when the look found a TV or device Lamp didn't know); and the first
request to a wish that opens on a TV or a device, or has a part that does, whose device line says whether Lamp finds it.
A turn's note on the person's phone asks devicectl only when the app is set to open on one. The first look Lamp makes hears nothing while macOS's question is up, so a wish's look that
was the first to ask waits up to half a minute for the answer and, given Allow, looks again before the agent starts
(`lookAgainOnceAllowed`, `localNetworkAsked`); a refusal after that is the person's Don't Allow, not waited on. The desk's
shelf of devices (`DeskDevices`, the desk guide) is the one place that looks unasked: until Lamp has looked once it
invites the person to (Find My Devices, the look macOS asks about), and from then on the desk looks each time it's
shown or Lamp comes to the front, at most once a minute, since macOS has already asked. Never as a
wish starts, nor as Lamp opens before that first look: those show what Lamp knows without looking (`showKnownDevices`: the last look's devices, and the kept TVs
and devices as not found). A look macOS refused (`DeviceProbe.search`: nothing
answered, and Network.framework says the path is local network prohibited, `localNetworkDenied`; a refused send itself
succeeds) sets `Store.localNetworkRefused`, and where a look was asked for (Your
Devices, Add a New Device, Try On) a line says so with the way to Privacy & Security, and that Local Network is chosen there (System Settings has no
link to that page itself).

A look for devices (`Store.refreshDevices`) is one at a time: one asked for while another runs is made once it ends
(`lookAgain`). It makes one SSDP search for everything (`Integrations.Scan.now`, `ssdp:all`), which the TVs and every
integration share: an integration's `find.ssdp` target and the description its identity reads are taken from those
answers (`Scan.answers(for:)`, `describedAt`), never a search of their own, the integrations look at once, and a
device's answers are waited for a few seconds (`Integrations.lookTimeout`), not an install's thirty. A recheck of the
phones alone (`refreshAppleDevices`) replaces only Apple's part of the list.
**The whole network** (`HomeNetwork`, HomeNetwork.swift). Where the person is looking at what's there (Your Devices,
Add a New Device and its Look Again, `network_devices`: `refreshDevices(everything: true)`), the look also finds what
SSDP and the integrations don't, and every other look leaves the last of it as it was. Never at launch or on a timer.
It sends one datagram (a byte to the discard port, 9) to each address of this Mac's own subnet, sixteen at a time,
paced, so the Mac asks who has each one and its neighbor table fills (`Sweep`); no nmap, raw socket or admin. The
subnet is the default route's interface's (`Subnet.current`): the whole of a /24 or smaller, and on a bigger network
only the 256 addresses around this Mac's (`Subnet.widest`), which the agent is told. Then it reads the neighbor table
and the default route from the kernel's routing table by sysctl (`Neighbors`, what `arp -a` reads; macOS hides the
table from a process without Local Network access, `swift test`'s helper included, so check it in Lamp or with
`xctest` from a shell), marks a locally administered hardware address as randomized (`Vendors.isRandomised`: a phone's,
tablet's or computer's private Wi‑Fi address), and looks up each other one's maker by its prefix (`Vendors`, the
longest of nine, seven and six hex digits) in `Resources/vendors.xz`, made from the IEEE's MA-L, MA-M and MA-S
registries by `scripts/update-vendors.sh` (names with their legal endings taken off, xz-compressed, about 375 KB; not
nmap's list, which is under nmap's license). Meanwhile it browses every Bonjour type (`_services._dns-sd._udp`), then
each type's services, resolving each with `dns_sd` to its host, IPv4 address and the record's model keys only
(`Bonjour`, `BonjourService.modelKeys`; AirPlay's `md` isn't a model, a Cast device's is), with no connection to the
device. Each address is one `NetworkHost`: hardware address and maker, randomized or not, this Mac, the gateway, its
Bonjour services and the names they go by, its SSDP server and the UPnP description Lamp read (`HomeNetwork.merge`).
Hosts are kept in memory only (`Store.hosts`).

Settings → Your Devices lists, in this order (`HomeNetwork.List`): the person's devices, set up with Lamp (away ones
too); then, under "Found on your network, not set up", what Lamp makes apps for or controls that's only found (the kits'
devices, what integrations find, `Integrations.devices`, and what a starter controls, `HomeNetwork.controlled`, a Sonos
so far); then the devices Lamp could learn:
those that answered the SSDP scan that nothing knows, read from their UPnP description (routers left out), and hosts
that offer a Bonjour service that isn't plumbing (`HomeNetwork.couldLearn`, `device(for:)`, named by maker and model,
never by the names they go by); then everything else, folded under Everything Else on Your Network: the router, this
Mac's other addresses, printers, Apple's devices (by the model their records give, `NetworkHost.apple`: an app can't
reach them the way it reaches others), appliances and hosts that said nothing but their maker, each with the names it
goes by on this Mac only and Set Up… (but the router and this Mac; a device found this way is known by
`found:<address>#<hardware address>`, read from the neighbor table as Set Up… is pressed, so a conversation is reopened,
linked to an integration's device and given a host's facts only for the same hardware, and one that began without a
hardware address never is), whose setup note asks the agent to work out what it
is and to say so plainly when nothing on the home network can reach it; and the hosts with randomized addresses that
said nothing, counted and never named, since nothing tells one such phone from another. Bonjour also browses a few types
whether the meta-query names them or not (`Bonjour.alwaysBrowse`: Cast, printers, a gadget's web page), since a
sleeping device often misses that one answer. What each host is isn't worked out by a list of rules: `network_devices`
gives the agent every host's facts (`HomeNetwork.facts`), with a few anchors (the gateway is the router, this Mac, a
randomized address is a phone, tablet or computer, counted), and the agent labels them when the person asks, or when
Set Up… asks it to learn one (`deviceSetupNote` adds that host's facts). Set Up… on one
Lamp knows opens its window; on one it doesn't, it opens the device's setup conversation (`Store.setUpDevice`), one
per device, whose first request is `Agent.deviceSetupRequest` (what the device said of itself). That conversation is
no wish (`LampProject.deviceSetup`, `makesNoApp`): it's never on the desk, never named, scaffolded, built or saved, and
every request in it carries `Agent.deviceSetupNote` in place of the app's notes, so a follow-up ("it still says
waiting") stays about the device. Lamp refuses the app tools there (`Store.deviceSetupRefusal`: looks, use, versions,
art, kinds, connectors, `write_wish`), leaving the integration, skills, notes and the chat's cards. When
`device_integration` keeps an integration it looks for the device at once, puts each found one's next step in that
chat, and moves the conversation to the device's new id, so the setup window's Ask About Setup… leads back to it. Each kind of card has its gallery entries ("Device setup"). Every device in that group shows only Set Up… (Pair… for a phone), never its first setup step ("Turn on developer mode
on it"): that step is for the setup window Set Up… opens (`DevicesSection.end`). A device set up with Lamp shows its
next step beside it.

**Windows packages.** A declared app kind may say `wrap: "msix"`: the package step leaves a zip of the app's files and
Lamp makes the package itself (`MSIX`, MSIX.swift), with nothing outside Lamp: the zip read as plain files only (no
link, nothing above its top), a manifest Lamp writes (the identity is Lamp's: `Lamp.<folder>`, publisher `CN=Lamp`, a
version from the time so each build replaces the last), logos drawn from the app's icon, the block map and content
types, laid out as Zip64 with every file stored and the signature the one plain deflated record (Windows opens nothing
else), and an Authenticode signature (the APPX digest blob in an SpcIndirectDataContent) with a key and self-made
certificate kept in Lamp's folder (`MSIX.Signer`), which the device installs beside the package (`{certificate}`). The
bridge launches it by its names (`{packageFullName}`, `{appUserModelID}`, and `{base64:…}` of either). For Xbox's Device
Portal a request also carries cookies the device set earlier in its sequence (`{cookie:CSRF-Token}`), polls an install
that answers 204 until it's done (`poll`) and fails with the device's words unless the answer says what `expect` asks,
or asks again until it does (`until`), where a JSON path's `*` is any element of a list and the value may be one of
Lamp's (`IntegrationRunner.meets`): the Xbox's install ends by waiting until the console lists `{packageFullName}`
among its packages, since its install state says it's done before the app can be opened.
Lamp ships the Xbox's integration (`Resources/Devices/xbox-one.json`): Developer Mode, Device Portal's password, and a
controller-driven web app (arrow focus) wrapped as MSIX and shown in Lamp's own WebView2 host (`"host": "webview2"`, below). Its identity is
read from wherever the console's SSDP answer points (`Read.description`), since that moves between retail and
Developer Mode, and `contains: "Xbox"` keeps a Windows PC sharing media out. Its apps may be 3D games: three.js ships
with Lamp (`Resources/WebLibraries/three`, MIT: its WebGL build, its WebGPU renderer with node materials (`three/webgpu`,
`three/tsl`, drawing with WebGL 2 where there's no WebGPU) and the light addons, put there by `scripts/update-three.sh`
from one commit of three.js's repository, each file checked against the git hash the commit lists; a commit rather
than a release while the New York starter needs a fix made since the last one; the node renderer and the addons built
on it, `DeviceSupport.threeNodeFiles`, go only into an app whose page imports `three/webgpu` or `three/tsl`) as a library a kind asks for like the building blocks
(`DeviceSupport.Library.three`, `"three": "Web/three"`, a folder the page loads through an import map), so nothing loads
from the network. It replaced Babylon.js, which was chosen for EdgeHTML; under WebView2 the agent writes three.js more
reliably, its efficient path (`InstancedMesh`) is the obvious one, and it's about half the size. The rules
keep scenes within the budget of the console the game goes to (below) and have a game read the controller with the Gamepad API while it's
played, the keyboard too. A kind that declares `preview` (a web app's folder) is looked at and used in the preview on the
Mac, the TV preview's window under the device's name (`Store.openDevicePreview`, `TVPreview.show(device:)`, where Back
is Escape, letters reach the page and a key can be held), since a device's screen can only be pictured; Play still puts
it on the device. The chat is Lamp's panel beside that preview while it's open, and on its own while the app is on
the device, an Xbox with no Xbox to put it on included (`ChatPanel`), with Play, Stop and Try On in its bar.

**The Xbox's web host** (`WebHost`, `Resources/WebHost`): an Xbox web app runs in Chromium, the console's WebView2,
not in the EdgeHTML that Windows gives a package naming a start page (WebGL 1, Edge 18's JavaScript, about a third of
the frame rate). The host is one small C++ program (`lamp_web_host.cpp`) that never changes between apps, so Lamp
ships it built (`App.exe`, made by `scripts/build-web-host.sh` with the game tools, its downloads checked) with
Microsoft's redistributable `Microsoft.Web.WebView2.Core.dll` beside it, and `DeviceApps` puts the app's files under
`Web/` in an x64 package whose manifest registers that library's classes (`MSIX.Start.webHost`): nothing is built on
the person's Mac, and the browser is the console's own. It hosts WebView2 through composition on its CoreWindow,
as WinUI's control does (a controller given the CoreWindow itself ends the app on the Xbox), and keeps the
`CoreWebView2` and its DevTools receivers for the app's life (WebView2 drops the handlers of objects let go). The
console's web view lays a page out at 1280x720 and scales it up, so the host zooms it to 1920x1080 CSS pixels before the
app's page opens (`fit_page`), as the preview and the rules have it. Only the app's own page may use the host: a link
to another site opens in the console's browser, and an answer goes only to the page that asked. Its sound plays as the app opens, as a console app's title music does: the host
turns off Chromium's rule that holds a page's sound back until the first button press (`--autoplay-policy`), which
left an Xbox web app silent until then. The page
is https at `https://lamp.example/`, so lamp.js reaches Lamp's plain-http gateway through the host (`http` web
messages, only to Lamp's own paths), and a claim tries the Mac's IPv4 addresses first: the console reaches the
`.local` name over IPv6, which the claim, opened for the device's IPv4 address, refuses. A game's or a screen's page of
a wish talks to the wish's other apps through the host too: it opens the page's `ws://` links to the home network
and passes their frames (`ws` web messages), while the page keeps the wish's handshake and seals (the "Wishes" guide). The page's console, uncaught
errors and the host's own lines go to `LocalState\log.txt`, which the bridge's `log` reads, so `look_at_app` with
`on_device` (which a web kind with a preview now honours) shows how the app really runs. A controller in WebView2
sends its buttons as key presses named "Unidentified" with Edge's old key codes; lamp.js renames them before the page
hears them (`padKeys`: the d-pad and left stick are the arrows, A is Enter and presses what has focus, B is Escape,
the rest Edge's `Gamepad…` names). A key a page makes can't carry a key code, so the remote's arrows in a TV app or a screen (`Lamp.onKey`, `Lamp.key`) read a key by its name too (`nameOf`), or the controller would move nothing. `navigator.getGamepads()` gives the standard mapping. Its web view never shakes the controller, so lamp.js puts its own `vibrationActuator` on every gamepad in the host, whose `playEffect` and `reset` go to the host as `rumble` messages, played with Windows.Gaming.Input as a native game's `lamp_rumble` is. The web view numbers controllers in another order than the host, so each effect carries what the page sees on its gamepad (buttons, sticks) and the host shakes the controller whose reading matches, remembering the pair for effects asked while nothing tells them apart. A package Lamp put on a
console before installs over the earlier EdgeHTML one (same family, newer version), so nothing moves an app across.

**What's on the network, for an app** (`LampNetwork`, in LampSupport.swift): a wish's Mac or iPhone app finds the
person's devices itself, for the ones Lamp has no block for. `requestAccess()` is the system's Local Network question,
asked when the app chooses (after saying why, never at launch): a datagram to a neighbor has the system ask, and the
connection's path says whether it's allowed (`unsatisfiedReason == .localNetworkDenied`); the first time it waits for
the person's answer, after that it says how things stand at once (`access` keeps the last). `find()` asks SSDP twice
over, to the multicast group (a Mac) and to each address of the /24 (no multicast, so an iPhone app without Apple's
multicast entitlement gets answers too; most players and TVs answer, a Sonos doesn't), reads each SSDP device's UPnP
description for its name (a speaker's room before its friendly name, which a Sonos fills with its serial number), maker
and model, and browses Bonjour for the types in the app's `NSBonjourServices` (an
iPhone app may browse no others; a Mac copy is given them by `Capabilities.macInfo`), plus common media and home types on a Mac; each Bonjour service is resolved to its
address by a connection opened and closed at once. This device's own addresses are left out. The app's own reason for
the question is `localNetwork` in capabilities.json (`Capabilities.localNetworkReason`: one line, 150 characters at
most, words and plain punctuation only, since it goes into Info.plist as it is), written in place of Lamp's general one wherever the reasons are (build.sh, the phone's project, the simulator's
bundle, `apply(to:)` for a Mac copy).

**Controlling a Roku from another app** (`LampRoku`, in LampSupport.swift): a wish's Mac or iPhone app drives the
person's Roku over ECP (port 8060) with nothing installed on it: find (SSDP, then the Rokus found before, then a sweep of
the device's own /24, since an iPhone app can't send multicast without an entitlement Apple grants on request),
device-info, the active app, the media player, the apps, launch with a deep link, keys, `Lit_` typing, and a Roku TV's
power, volume and input. Its only setup is the Roku's Control by mobile apps set to Enabled (Limited, the default for
newer Rokus, refuses key presses and launches); the block's errors and the building-blocks skill say so, and never
suggest Permissive. A request for such an app names the Roku, so the naming call is told that a device's own kind is
only for what runs on the device (`Suggestions.deviceKinds`, `seen`). The iPhone's local-network reason says it reaches
devices as well as Lamp.

**What's on the network, for the agent** (`network_devices`, NetworkDevices.swift): a wish that controls, plays to or
reads the person's devices starts from what's there, not from a question about what they own. The tool waits for a
fresh look (`Store.devicesNow`: the same look as Settings → Your Devices, with the wait for macOS's question on the first; a look still going after 45 s is said to be, never answered with the last one's list) and
answers with each device on the network: its name, maker, model and address, what it said to the SSDP search, and what
Lamp already has for it (`LampRoku` for a Roku, a way to put apps on a TV or an integration's device, or nothing), the
devices set up with Lamp apart from the possible ones (above), which it says may not be the person's. Phones,
the Mac and anything plugged in are left out, since they're where apps run. The look is SSDP, the TV kits, the
integrations and the whole network (above): after the devices come every other host's facts, how much of the subnet
was swept, how to tell what each is, and that the names a network holds are often people's, to be said to the person
and never written into an app, its files or an integration. Kept devices not on the network
now are listed apart. When macOS keeps Lamp off the local network (`Store.localNetworkRefused`), the
answer says where the person turns it on rather than that nothing answered. A rule in `deviceRules` names the tool, the
`device-control` skill (also named with the request once an app's code reaches devices, `Skills.applying`) and
`device_permission`, which the agent asks with before changing a real device ("Approvals and privacy"); it's every engine's (pi's extension, the MCP endpoint, `/agent/network`).

## Pages and their hosts

A web game and a screen are both pages, and a page goes wherever Lamp has a host for a web engine (`PageHost`, in
`Places`): WebKit in an app of Lamp's on the Mac, iPhone and iPad (Lamp's common host for a page, `LampPage.swift`:
`LampPageFiles` serves `Web/` at the app's own address and `LampPageView` shows it, at the window's size or zoomed from a
fixed canvas of its own; `LampWebGame.swift` is a game's app around it, `LampWebApp.swift` any other page's; on the Mac
both are one prebuilt app, Lamp's player, copied for each: "Lamp's player", under Games); Android's WebView in one app of Lamp's for phones, tablets, photo frames and Google TV, Android TV
and Fire TV (`GameAndroid`, in the page's `Lamp/Android`); the TV's own browser on a Samsung or LG (`TVs`); and the
integration's own host on the Xbox (WebView2, `WebHost`). A row of the table of devices names its host in its `web`;
the kinds' places are `Places.pagePlaces`, the destinations of every row with one, named by the rows' own words, so a
host added to a row is a place for every page at once, with no list per kind to keep. Several integrations' rows share
`.device`; a page made for several devices goes onto one only where Lamp packages pages for its host
(`GameKit.pageIntegrations`, the Xbox's), and another integration's web app is asked for with its device alone. The
Android host is one APK for every Android place: its manifest has the phone's launcher and the TV's (the leanback
launcher, a banner Lamp draws from the icon, no touch screen required), Android TV is its own `Destination`
(`.androidTV`, opened in Lamp's TV emulator: `Destination.emulator`), and the remote reaches the page as a TV's does: the
d-pad, OK and play/pause are a game's controller (`lampNativePad`), and for a screen Back, the media, color and channel
keys are sent as the key codes Web/lamp.js reads on a TV, with Back on the first view leaving the app
(`lampAndroid.exit`). The page's LampAI is answered by the Android app as the Mac's app answers it: Web/lamp.js
finds `lampGatewayHost` (an AndroidX WebKit message listener for the page's own origin in its main frame,
`LampPageGateway.kt`), and the app sends LampAI's routes to Lamp with the token Lamp wrote into its storage at install
(`Adb.tellApp`), so the page never holds it. On a Samsung or LG, `lamp-game.js` reads the remote's numbered keys as the keyboard's. A row
with no web host (the Apple Watch, the Apple TV, Vision Pro, a Roku) is refused a page with its own reason
(`AppKinds.target`, `Places.refusal`), and Try On lists it under the places, whether or not one is left to add (`Places.noPage`: every built-in row
with no host, an integration's once the person has its device) as "Needs a Native Version", or "Native Only for Now"
where the gap is Lamp's own (`noHostYet`: Vision Pro shows pages, Lamp has no host there yet); `make_app_for`'s table
says the same (`Places.forAgent`).

## Games

A game is a kind of wish of its own (`Platform.game`, Targets/GameTarget.swift, `GameKit`), never a device's: the naming
call gives "game" for a game played in real time, 2D or 3D, or one played with a controller or on an Xbox (a game played
by clicking or tapping through turns stays a Mac or iPhone app, and so does one the person wants only on Apple's devices
with Game Center, a widget or inside an app of theirs: SpriteKit, the `2d-game` skill), with the devices it's played on beside the Mac in its `places`. Its home is the Mac, and the places it's
played are given one at a time (`LampProject.places`, kept in meta.json; `Target.startsAt`, `Platform.addsPlaces`,
`LampProject.openPlaces`, which `destination` goes by): the Mac always, an iPhone and iPad (`.ios`, the simulator or
the person's own, whose Xcode project carries `Web/`), a Samsung or LG TV (`.tv`, staged and installed as a TV app's page
is), Android and Android TV (`.android`, `.androidTV`: Lamp's Android app in the game's
`Lamp/Android` (never `Android/`, which `Parts.folders` reads as a wish's Android app), `GameAndroid`, built and installed
like any Android app of Lamp's: a WebView serving `Web/` from the app's assets, the controllers read natively and handed
to the page's `lampNativePad`; in a wish of several apps it also carries Lamp's Kotlin blocks and answers the page's
`Lamp.wish` with `LampWish`, the "Wishes" guide) and the Xbox (`.device`, with `LampProject.integration` "xbox-one", the integration's web
app, installed as a game). `make_app_for` on
a game sets its places (`Store.change`, `setPlaces`: every place listed, the Mac kept) and never changes its kind,
given as `make_app_for`'s `devices` with `made` "web", and only `remove_app` takes it away (the "Wishes" guide; a game
can also be added beside a wish's other apps, in Game/);
Try On's "Play on … Too" for each place it hasn't got does the same (`addPlace`), and a place given is where it
opens next. What each place needs (Xcode and a simulator, the console's tools and the Xbox) is asked for when the game
first goes there, never up front: the kind's `setup` is `.none`. The places and the budget of the slowest (a Samsung or
LG TV's, a Google TV streamer's, an Xbox One's, a mid-range Android phone's, an iPhone's, an Xbox Series S's, an Xbox Series X's, this Mac's) ride with the request in
the device line (`DeviceNote`, `Rules.gamePlaces`), not in the prompt, since a place may be given at any time. The Xbox's is
the console chosen under Try On, else the slowest of the person's (`GameKit.xboxModel`), as Device Portal names it: the
integration's description says Xbox One on every console, so its `device-portal` step is the model step (`"model": true`,
`Integrations.model(of:)`), which also gives the device its model in the list and the agent's line. An Xbox whose setup
hasn't reached Device Portal is budgeted as an Xbox One. Places on the project are general: games and screens take them,
and an app kind that takes places one at a time (an Apple TV or a TV beside a SwiftUI app) is a `startsAt` away.

A game is drawn with three.js, or with Phaser when it's 2D (`GameKit.Engine.web`, written in its `.lamp-game` mark): the
model writes both best and every place has a web view, and on the Xbox a game installed as a game gets enough of the
console. Which of the two is the agent's choice as it writes the game, from what the person asked for: `Rules.gameWebKit`
has it choose 2D or 3D and read the `game` and `game-ui` skills with the `2d-game` or `3d-game` skill, which are the only guidance that
names the library and its recipe (entry point, renderer, frame callback, where setup goes). The kind and the scaffold are
the same, and the placeholder card is three.js's either way. A web game is a page in `Web/`, as an Xbox web app's is: `index.html` and the agent's modules,
with Lamp's `Web/lamp-game.js` (the game runtime: `game({ renderer, init, frame, touch })`, the same pads, buttons,
seeded `random()`, `save`/`load`, `log`, `rumble` and `sound` the kit has, the canvas fitted at 1920x1080, touch
controls on a touch screen, and the frame rate measured wherever it's played: logged every ten seconds, and the canvas
drawn at 3/4 and then 1/2 of 1920x1080 while frames come slower than 45 a second, a step undone when it didn't make them
faster; a page laid out at the window's size whose HUD is its own HTML passes `fill: true` instead, sizes its canvas
itself, and the runtime only measures and logs its frame rate) and three.js in `Web/three` beside it. A 2D game is Phaser 3's scenes run through `Web/lamp-phaser.js`
(`phaser({ scenes, pixelArt, physics })`, Lamp's like lamp-game.js and written into every game so the agent can read it
first), with Phaser itself in `Web/phaser` only while the page's own files import it (`DeviceSupport.usesPhaser`; pinned
and checked by `scripts/update-phaser.sh`). The runtime stays the one frame loop: Phaser's loop is put to sleep once it has
booted and each of the runtime's frames calls `Game.step` with the runtime's time, rather than the runtime's pads being
read inside Phaser's own loop, so the preview's fixed 1/60 s frames, its clock and its seed (Phaser's `RND` is seeded from
`random()`) hold for Phaser as for three.js, with no second clock to agree with. Phaser's keyboard, gamepad and sound are
off (the pad is the runtime's, `pad()`, and sound its `sound`), its pointer input stays, and it fits its canvas inside the
1920x1080 stage the runtime fits to the screen (Phaser's FIT, so clicks land where they're drawn). A Phaser game is
always `sharp`: Phaser draws at the game's size, so the runtime's smaller drawing doesn't apply. In the preview a scene
that starts loading is waited for before the next frame (the frame function's promise, which `runPreview` awaits), and
the stats count WebGL draws and their triangles. Physics is Rapier (`Resources/WebLibraries/rapier`, Apache-2.0, put
there by `scripts/update-rapier.sh` from one npm release of `@dimforge/rapier3d-compat`, checked against the SHA-512
npm lists): one ES module of about 4 MB with its WebAssembly inside it, so it loads from the page's folder like any
module in every host (the Mac's and iOS's web view, Android's WebView, the Xbox's WebView2, the preview), with no
.wasm file for a host to serve. It goes into `Web/rapier` only while the page's own files name it
(`GameKit.usesRapier`: the import map's `@dimforge/rapier3d-compat` entry, which the agent adds), and is taken out when
they stop. `fixedStep` in lamp-game.js steps it, or any physics, at 1/60 s however fast frames come, so the preview's
frames (each exactly one step) replay a play exactly; Rapier gives the same results run to run on one machine, which
is all the preview needs. Starting it takes about 20 ms in WebKit and 200 ms in Chromium on a Mac, and its memory
starts at about 1 MB and grows with the bodies (about 7 MB for 500). What the player holds is `input()` (a controller and
its family, from the Gamepad API's id or the vendor Lamp's Android app sends with the pad, the keyboard, or touch; a
device that comes with a controller starts on it, a touch screen on touch, anything else and the preview on the
keyboard, and it follows the last one used, with `onInput` to redraw), and `label`/`glyph` name and draw a button, stick
or trigger for it. The page never works out which device it's on: what it needs of one comes from the device's row in
the table of devices (`Place.input`: its keyboard's names for keys, the controller that comes with it, the one controller
layout its host supports, where it supports one), in the `lamp-device.js` Lamp writes into each copy of the page (`GamePage`, see
[kinds of app](kinds-of-app.md)), and the controllers' layouts (how each is recognized, what's printed on its buttons)
from Lamp's one list of them, `Controllers`, as `Web/lamp-controllers.js`. The keys a prompt names come from the same
table `keyboardPad` reads, and the touch controls' from the one they're drawn
with, so neither can drift. On a Switch controller a prompt names the letter printed on the button, which isn't the
Xbox's in that place: BUTTON.A is the bottom button, marked B there. The game's rules say to write the controls once as
actions and build every prompt and help screen from them (`Rules.gameWebKit`); New York is the worked example. On the Mac and iOS the Swift around it is
`LampWebGame.swift` (a web view serving the bundle's Web/ at `lamp-game://app/`, its log into the app's log, sound with
no tap first), built by `GameKit.webBuildSh`; on the Xbox it goes as the integration's web app ("xbox-one", the package
its declared step makes, `Web/lamp.js` written then), installed as a game. The agent's preview of it is
`WebGamePreview`: a copy of the page (`GameKit.stageWeb`, under the sandbox) in a web view nobody sees, given the same
script as the C++ kit's preview (`window.lampPreview`), which `lamp-game.js` plays itself at exactly 1/60 s a frame with its
clock and random numbers fixed, pausing at each `shot` while Lamp pictures the whole page, HTML over the canvas
included; the same script gives the same pixels. After a play that ends cleanly the preview is kept open for ten
minutes, one a game: the next look hands it its script and the files changed since the last (by hash, the build's own
name aside), and the game's code runs again in place there from a fresh start, with the clock, seed, saves and log
reset (`__lampPreviewAgain`), so only the first look of a while waits for the whole game to be built and its shaders
compiled. Lamp's own files changing, a page that can't run its code again, a failed play or one that runs past two
minutes closes it, and that look starts a new preview. Its stats count draws and triangles (three.js's `renderer.info`, or the
WebGL calls lamp-phaser.js counts).

A game may be written in TypeScript, its source in `src/` with `src/main.ts` its entry as a Vite project keeps it, so a
game brought in from one stays as its authors wrote it. Before every build and every look (`Store.build`,
`GameKit.stageWeb`) Lamp bundles it into `Web/app/` (`GameKit.compileSource`) with the Bun inside its own pi, run as Bun
itself (`BUN_BE_BUN=1`), in the game's sandbox, from a copy of `src/` in a scratch folder (Bun reads every folder above
the one it builds in, which the sandbox closes in the person's own folders): nothing installed, nothing fetched, types stripped and not checked, bare
imports left for the page's import map. Two of Vite's conventions hold so a Vite game needs few changes: `import.meta.env`
reads as a published build's (`DEV` false, `BASE_URL` "./"), and each `src/**/*.worker.ts` is bundled as an entry of its
own, every file flat in `Web/app/`, so a worker started at `./<name>.worker.js` beside `import.meta.url` is found. It must
be a module worker (`{ type: "module" }`, which Vite doesn't require): code it shares with the page is a chunk it imports. Every place then plays plain JavaScript, and a change of `src/` is a change of
the page like any other. `src/` is shared with the game, and so is `Web/app/`, which a Lamp from before `src/` plays as it is and a newer one
builds again (`GameFiles`).

A game made before three.js games is C++ on Lamp's kit (a device app of "xbox-one:game" then). It reads as a game whose
engine is `native` and whose one place is the Xbox (`GameKit.migrated`, in `Store.readWish`; its folder's old
`.lamp-device` marker still reads as a game's, `GameKit.isMade`, the kind `refines` the device kind, until its next build
writes `.lamp-game`), and is built and played as it was: for the Xbox, and in the kit's preview on the Mac. It can't be
given another place (`setPlaces`, `Store.placesToAdd`), and no new game is made in C++ (the naming call has no word for
it, and `make_app_for` takes no C++ kind).

A game made as the Xbox's web app before games were a kind of their own (a device app of "xbox-one" whose folder has a page
in Web/ and the agent's own line that it's a game: capabilities.json's or icon.json's `game`, never three.js alone) is a
three.js game now (`GameKit.migratedWebGame`, in `Store.readWish`, once, with a line in its chat): at home on the Mac,
where Try On points, with the Xbox one of its places and its console still the one chosen there, so it's installed there
as a game and updated as before. Only meta.json changes, and its folder reads as a game in every version
(`GameKit.isXboxWebGame`, in `isMade`), so a restore keeps it one. An Xbox app of menus and pages says nothing of a game
and stays the Xbox's, as does a wish whose Xbox app is one of several. Its page runs its own loop, not Lamp's game runtime,
so until it's moved onto `game()` (`GameKit.ownsLoop`: none of its own files load lamp-game.js) it's looked at and used as a
screen is: in its window on this Mac while that's open or Try On points at the Mac, else in the page preview it had as the
Xbox's web app ("Where the agent looks at it", under "Screens"), and its rules say so (`Rules.gameOwnLoop`, `gameOwnLoopTry`).

On the Mac and on iOS a web game is an app like any other Lamp makes, of Lamp's own (`GameKit.webPackageSwift`,
`GameKit.webBuildSh`, `Sources/LampGame.swift`, `LampPage.swift` and LampSupport.swift, none the agent's), so its Mac copy
is installed, opened, quit and shown on the desk as a Mac app is, with the wand floating over its full-bleed window and
the chat beside it. A three.js or Phaser game isn't built live as a Mac app is (`LiveReload.eligible`, `Target.hostedByLamp`):
a change of its page goes into the open game instead (`PageLive`, below), and any other change (its Swift, Package.swift,
capabilities.json) reopens it, held for Reload while the person has it open. On the Mac it's made
from Lamp's player (below) unless it has Swift of its own.

A change to a game while it's played. While the agent works, each change it saves goes into the game open on this Mac
once it compiles, the saving has paused a few seconds and the agent has said the state is whole: in a progress line of
what's now in it, or by looking at it (`Store.stepPage`, from the `autoApply` loop that does the same for a Mac app; the
`progress` and `look_at_app` tools' descriptions say so, for every engine). Only the agent can tell an edit the person
would see from one they wouldn't (a refactor, half a piece of work), so a save in between waits; a progress line is
the chat's word for the step ("Put into New York: The car is rainbow now"), and a look's step is said in the words of
the agent's steps that made it ("Put into New York: Adding a sports car"). A look at a game plays it in the hidden copy
(`playGame`), which can take minutes, so the sources it plays (`Turn.lookedSources`) go into the open game as it plays
(or, for a play over before the loop took them, before the look returns: `stepLooked`) rather than when the agent's
checking is done, and a fix it looks at later goes in the same way (the look's result says
when its sources are in the open game, so the agent never asks for a Reload the person doesn't need); a save that leaves the
page's files as the last step put them in (`pageSignature`) puts nothing in. What the page does with it is what it does
with any change (below): a swap goes in at once, busy or not; code run again in place waits for a pause while `busy()`;
and a change that opens the page again is held for Reload, never opened under the player (`PageLive.put` puts one change
into a copy at a time). The step of a look or use played in the hidden copy ends in " · in a hidden copy"
(`Store.markHiddenCopy`), Lamp's words whatever the agent's `doing` said, so "Seeing the new car in the city" never
reads as the person's own game while it still shows the old one. The game's own modules are first parsed as modules by the Bun inside Lamp's pi
(`GameKit.codeProblem`: its transpiler, in the game's sandbox, running nothing); a game bundled from TypeScript is
checked by its bundling. Then the Mac's copy is built and put in as a turn's end puts it in (`pageInPlace`). A step
that doesn't parse waits for the next save; one that parses but fails as it runs opens the page again from the
snapshot, as it would at the turn's end. The app around the page on the Mac and in the simulator (`LampPageLive` in
`LampPage.swift`) asks Lamp what has changed (`/app/page/live`, held up to 25 s, asked again at once; never on a phone,
whose copy takes a change through the wish's room, as every copy on another device does: "A page's change in every open
copy" in the kinds-of-app guide). When a build's page differs from what that copy was installed with
(`PageLive.installed`, the page's files by hash with a hash of the rest of the app, kept in `.lamp/page-live`) and the rest
is the same, `Store.pageInPlace` answers with every file that differs from the install, copied out of the build; the app
fetches each (`/app/page/file`), serves it in place of its bundle's (`LampPageFiles`) and keeps it for the next launch of
the same bundle, then tells the page (`window.__lampLive`). lamp-game.js decides, and says which to Lamp
(`/app/page/state`), which waits for that word: files the runtime loaded (`asset`, `texture`, `model`, `sound.load`) go into the
running game, with the game's `assetChanged(path)` for what it made of them, and so does code where it can ("swapped"):
a stylesheet the page links is replaced, and a changed module is imported again under a new query and put into what
the running game holds. A module that takes its changes calls `hot(import.meta).accept()` (lamp-game.js, "Swapping code
in"); the runtime reads the game's modules from the page for what imports what, and a changed module that doesn't take
its changes runs again for those above it that do (loaded from its source, with their imports pointed at the new
versions and `import.meta` written out), up to each module that does, as Vite's hot updates go. There each exported
class gets the new version's methods on its prototype (every version's, so objects made by any version run the new
code with their fields kept; `Symbol.hasInstance` makes one an instance of every version), and each exported plain
object the values the change changed, told from what the game changed as it ran by the values each version made. Native
modules can't rebind an importer's bindings, so a change a swap can't take (a class whose constructor or fields changed,
read off its source without its methods, or that has private members, whose brand is the old class's; an exported
function or value that changed; code outside the classes of a module exporting functions; the HTML; a module nothing
takes changes for, the one that starts the game as a rule) runs the game's code again in place instead ("rerun", with
the swap's reason as `why`, which the agent's look is told: `pageRanAgain`). That's a reload without the reload, chosen
over carving out the swap's refusals one by one (rebinding exports by rewriting modules as they load, rebuilding a
class's objects with their fields carried across), since most changes a person asks for change what a game's start
built, which no swap of code puts in: the old code's frame loop stops, its `dispose` (a game() option) and the modules'
disposers run, and what it left running is taken away (lamp-game.js watches the page's listeners, timers, sound
contexts and workers from the start, the runtime's own going through the browser's functions it kept first); the
page's head (all but its scripts) and body are put back as the HTML now has them, Lamp's elements kept; every module
of the game runs again in order, loaded from its source with its imports pointed at the new versions; and the module
that starts the game calls game() again, whose init starts from what it registered and the snapshot taken before
(`pendingRestore()`, as after a reload). What stays is what a reload loses: the WebGL or WebGPU context and its compiled shaders, the files the
runtime loaded, the sound, the controllers, and the parts the game kept with `hot(import.meta).keep(key, build, {
inputs })`. A kept part is built again when the module that kept it or one it imports changed, its build function's
code changed, or one of its `inputs` isn't the same object (a part built again builds again the parts made from it);
for the module that starts the game, which imports everything, it goes by the modules whose imports the build function
names, and a game bundled from TypeScript, one file, builds again everything it kept. New York keeps its renderer, the
ground's heights and each part of the city, so a change to its HUD runs again in about 2 s instead of a 16 s start,
and a change to its trees builds only the street details, traffic and road paint again. What a game registers lasts
beyond that (lamp-game.js, "What the game registers"; the scaffold and the game skill start every new game with it):
`live.renderer(build)` is one entry of `keep` outside any module (`lasting`, so no change of a module marks it stale,
only its build's own code), `live.camera` keeps the object and its pose, lens and target, and `live.state` a plain
object filled in place, so whoever holds it keeps holding it. All of it is `heldNow()`, plain JSON beside the game's own
snapshot in what `takeSnapshot` gives (`held`), so it goes wherever a snapshot goes: taken again as the old code stops
for a run in place, kept in sessionStorage for a page that opens again, and in localStorage for a newer install. It's
put back after `claim()` and before init, since what's registered at a module's top level runs before the page knows
where it starts, and the cameras again after init, so what a start sets on one doesn't win. A swap keeps what's
registered as it is, so a new version that declares any of it differently refuses the swap (`redeclare`) and the code
runs again, from what was held before that swap, which a swap gone wrong may have changed. This is a promise about
what's registered only: `game({ renderer })` gets a renderer after it's built, so one the game makes for itself can't
be reused, and three.js code the runtime never sees can't be kept. While the code runs again, the last frame and
the old HUD stay on screen, still, and fade once the new code has drawn; the page then says `shown`, which is when
Lamp's light crosses the window (`Store.pageShown`): the smoke built over the window stays through the run, rather than
going as the page first answers. A swap gets the light at once; a page that opens again says `shown` at its first frame;
one that never says lets the smoke go after 20 s. Where running again can't be done (the import map or a script
that isn't a module changed, a circle of imports, Lamp's own files) the change waits for the person's Reload
(`reopenOrHold`, "held"), never opening the page under them; Reload opens it again from the snapshot. New code that
fails before init is done or in its first second opens the page again at once (`swapGuard`). The game's
`accept((next, { changed }) => …)` may build again what a changed method built once, or return false to run the code
again. A file nothing put in opens the page again with the game's `snapshot()` kept in sessionStorage ("reloading",
with the page's reason as `why`: `PageLive.reason`). The new copy takes
it before init (`claim`), and the game reads it with `pendingRestore()` as it starts, in init or its first Phaser scene,
so it builds the place the player was in and never shows its title first; a game that doesn't read it is given it in
`restore(state)` after init, before the first frame. Either way it's taken from storage as it's read, so it's restored
once, and an error while starting from it (init, a scene's create, restore, the first frame) opens the page once more,
fresh, and the log says so; while `busy()` is true it waits
for the next moment it isn't ("held"; a swap goes in at once, busy or not), which the chat shows as its Reload line and the Mac's title bar as its Reload
(`awaitReload`); Reload puts it in at once (`PageLive.putInNow`), and the page shows "Reload to apply" itself where the
app has no Reload of Lamp's (the simulator). No word within 20 s, or a copy Lamp hasn't heard from, and the app is
installed as before. On the Mac the build is installed when the app closes (`LiveReload.awaitInstall`). The input the
player was using is kept too; a controller read through the Gamepad API reappears at its next press. Every copy of the
page names its build (`lamp-build.js`, beside `lamp-device.js`: build.sh's `stage_page` and `GamePage.stage`), and the
runtime keeps the latest snapshot every five seconds and as the page hides; a newer build opened within a quarter of an
hour restores it once. That's how a change installed on a phone, Android, a TV or the Xbox (Reload or Play) brings the
player back where they were; a copy open there in the wish's room takes the page's change as it's made, opening again
from the new files (`PageCopies`).

**Phones as players.** A game takes phones on the Wi‑Fi as a TV app's page does (`Target.takesPhones`): its lamp.js
has `Lamp.controllers` (`GameKit.lampJS`, `TVTemplate.controllersJS`) and its phone page is `Phone/` beside `Web/`,
shared with the game (`GameFiles`) and copied with a starter. On this Mac the game runs its own phones, so they go on
playing, and new ones join, whether Lamp is open or not: the phone page is staged at each build (`TVs.stagePhone`) and
put in the game's bundle as it's installed (`GamePhones`, in `Contents/Resources/Phone`, with lamp-controller.js), and
the copy answers `/app/controller` itself (`LampControllers` in LampPage.swift) from `ControllerRuntime`, LampRelayKit's
Swift built into the player and every compiled game as one file (`GameKit.controllerKit`, which build.sh writes). As
`Lamp.controllers` starts, it serves the page (`PhonePageServer`) and runs a `Relay` in the game's process, each on a
port the system gives it, with a key made for that session and kept only in its memory; `Lamp.controllers.stop()` and
the game quitting close both. A shared game's page is held to its sites by rules fixed as its document loads, so its
relay comes first: a port on 127.0.0.1 alone is taken before the document is served and named in its rules for
connecting only (`ControllerRuntime.pageSites`), phones join at a port of their own that opens with the session, and
the held port stays the game's through every stop until it quits, so nothing else can take a port a live page may
reach. One lost anyway is asked for back, and if it's gone the pages open again under the new one
(`onPagePortMoved`, `LampPageGuard.retirePages`). The session is the page's, so it outlives a run of the game's code: lamp.js's service
takes its timers from the browser as the page loads, before `watch` wraps them, so `takeAwayLeft` never reaches its
beat, its renewal or its link. A run's own callbacks are the run's (`watchPhones`, as `watch` follows its listeners; a
kept part's stay with the part): the old run's end as it stops (`holdPhones`), a `stop()` from its `dispose` is
ignored, the new run's hear nothing of players until it's about to draw (`bringPhones`, in `ranAgain`), which calls
its `onLeave` and `onJoin` with the difference and the present roster, and held buttons stay in `isHeld` while old
presses and messages are dropped. The game's snapshot keeps which player has which slot. What a frame reads of phones'
buttons is `f.phones` (`readPhones`, sampled in `step` beside the pads): the runtime hears `onButton` under what `watchPhones`
wraps, so it belongs to no run, and keeps each phone's held buttons and what they did since the last frame, so a press and
release between two frames is both. Those edges go with a phone that leaves and with a run that ends (`holdPhones`), and what
arrives while the code runs again changes what's held without becoming a press. While the agent works, a change of the phone page goes out as it's saved through `Store.autoApply`: with a game's page
for a game open on this Mac (`stepPage`), and after the same pause for phones on a page Lamp serves with no Mac copy open
(`stepPhones`). Its scripts, inline ones included, are parsed first (`GameKit.codeProblem`), and what's published is held to
what was checked (`TVs.stagePhone`'s `expecting`). A change of the phone page goes into the open game with its page (`PageLive.put`): the copy
on the Mac or in the simulator says it can take one (`phone` in its `/app/page/live` ask), Lamp hands it the whole page by
hash, and `LampPageLive` writes it to a folder of its own and only then swaps it in (`ControllerRuntime.use`), under the
session that's open; a change of the game's page held for Reload stays held, and the phone page goes on stepping meanwhile. A copy built by an earlier Lamp has the game installed again instead (`pageInPlace`,
`GamePhones.changed`). A page already open on a phone takes the newer one itself: every page Lamp or the game serves
starts with its version (`PhonePageServer.marked`, an HTML comment, which also says the host publishes versions), and
lamp-controller.js reads `lamp-phone.json` every three seconds while it's visible and as it comes back. Once the version
differs it opens again, keeping the credential, so it's the same player, at a moment nothing is lost: no button or stick
held, no file on its way, nothing being typed, and the page's own `busy()` says false. A page with `onUpdate` is told
instead and opens when the person says. It does this once for each version. The socket does go down and come back, so
the game hears that phone leave and return, unlike a run of its code again in place. An LG TV's and an Xbox's own hosts
don't mark their pages, so their phones stay on the page they opened until the game is installed there. A copy built by an earlier Lamp that asks Lamp is
told to update. On an iPhone or iPad the game does the same while it's in front: the page goes in its bundle as
`Phone/` at the top (`GamePhones.write`: the simulator's bundle in `finishSimulatorBundle`, and the copy Xcode builds
from in `Devices.stage`, with `Template.withPhoneFolder` in the project), the controller kit is built in with
LampPage.swift (its one Mac-only call, the Mac's Bonjour name, is guarded in `ControllerAddresses`), and the game ends
its session as it goes into the background, opening a new one at the page's next ask once it's back in front; no
background mode keeps it alive. `ControllerAddresses` gives a phone only an address on the device's Wi‑Fi or wired
network, never a loopback one: a device on no network says so (503). `scripts/check-controller-kit.sh` type-checks
the kit and LampPage.swift for the Mac, the simulator and a device. Lamp serves the page itself in the TV preview, a
window of Lamp's own, and on a Samsung or LG TV (staged with the rest, `TVs.stage`).

**The phone page in the game's preview.** The agent sees and presses a web game's real phone page with `phone` on
`use_app`'s actions (`PhonePreview`, the `phone-pages` skill): `GameKit.stageWeb` copies `Phone/` beside the page, never
over the published one, with Lamp's real lamp-controller.js, and the page opens at 844x390 in a second hidden web view
at the play's first `phone` line, held to its own files. Its socket is a stand-in with no network behind it: what either
side says waits for the next `phone` or `shot` line (`phoneStep` in lamp-game.js), which hands it across between two
frames, the page's timers and clocks moved on by the frames played since the last one, and to `Lamp.controllers` the phone
is a player that came another way (`_attach`), so a play with a phone is one
script like any other, played from the start, and never in a warm preview. In the preview `Lamp.controllers` asks no host
for a session and draws its join card from a made-up address. This shows the page, its layout and what it sends; the join,
the relay, files, rotation lock, notches, the keyboard and tilt are still only a real phone's to show.

**Which host.** The game chooses who hosts its phones as it starts them: `Lamp.controllers.start({ host: 'game' })`
(the game itself: the Mac's and iPhone's `ControllerRuntime` above, and the LG service and the Xbox's host below) or `start({ host: 'lamp' })`
(Lamp's relay and Lamp-served page). `start()` with no host keeps where each device ran before (the game itself on the
Mac, iPhone and iPad, Lamp elsewhere). The host asked for goes with each `/app/controller` ask, and whoever answers
refuses the one it isn't (LampPage.swift refuses `'lamp'`, Lamp's gateway `'game'`, `Store.controllerSession`; on an LG TV and the Xbox
`'game'` is asked of the game's own service or host instead), so a
host that isn't there, or fails, is said in `onError` and tried again, never replaced by the other; an answer to an
earlier start (`run` in lamp.js) is never taken. `stop()` ends the chosen host's session. The skills give the agent
both as options with what each needs, not an order.

On an LG TV the game can run its own phones there, with the Mac asleep or gone: Lamp packages a JS service of LG's kind with it (`LGPhones`, from
`Resources/LGPhones`: `service.js` on the TV's service bus, `relay.js` serving the phone page Lamp published at the
build and running the relay, the same protocol, credentials and limits as LampRelayKit's, with ws, put there by
`scripts/update-lg-ws.sh`, for WebSocket framing), and names it in that package's lamp.js only
(`TVTemplate.lgServiceMarker`). `start({ host: 'game' })` then subscribes to the service's `start`: the
subscription is the session, its answers are where the relay is and the page's host credential (again whenever the
relay starts afresh or the TV's address moves), and the page cancelling it (`stop()`, or the game closing) ends the
session, its sockets and its key, after which LG's service manager ends the service by its own idle rule. Only the game
the service was packaged with may start it or be given a host credential (the caller's app id, `message.sender`). The
key is made from Node's crypto for each session and kept only in the service's memory. Whether the service goes in is
a fact of the package, decided as it's made: a game that takes phones, has a phone page and an app id LG takes as
the start of a service's name (no minus sign, no period before a digit), on a TV whose webOS release is 5 or later
(`LGPhones.runs`: webOS TV 5.0's Node, 8.12, is the oldest ws runs on). Any other LG TV, one whose version Lamp hasn't
read among them, gets no service: its lamp.js names none, and `start({ host: 'game' })` there is refused by Lamp, which
answers the page's asks.
`Tests/LGPhones/relay-test.js` runs the service on real sockets under each Node an LG TV has, with LG's
`webos-service` stood in for.
On the Xbox a game that chose its own runs its phones in Lamp's WebView2 host (`lamp_web_host.cpp`, with the protocol in
`Resources/WebHost/lamp_controllers.h`, plain C++ that keeps to LampRelayKit's wire message for message): the page is
in the package as `Phone/`, beside `Web/` (`GamePhones.xboxPage`, `WebHost.payload`), and the page asks the host for its
session (`controllers` messages over the host's pipe, not Lamp's `/app/controller`), which opens the page server and
the relay on ports the system gives (`StreamSocketListener`), with a key made for that session from the system's
randomness and kept only in the host's memory. The page is https and may not open a plain link itself, so its link to
the relay goes over the pipe (`TVTemplate.linksJS`, shared with `Lamp.wish`) and the host carries it straight into the
relay (`ws://lamp-controllers.invalid/`, never dialed): only that link may be the game's host, and a host's credential
from the network is turned away. Stopping, the console setting the app aside, the page going away and 45 s with no ask from
the page end the session; coming back, the page's next ask opens a new one, with a new code. `scripts/check-web-host-controllers.sh` runs the
protocol on the Mac against a real WebSocket client; the host itself only runs on a console. A game on the Xbox that chose
Lamp (or no host), and a package made by an earlier Lamp, ask Lamp, which serves their phones while the game is set to
open on the Xbox (`Store.onDevice`).
On Android the game has no host's side of phones yet: Lamp turns
down `/app/controller` from anywhere on the network but a TV or an Xbox the game is set to open on, so
`Lamp.controllers` reports an error and the game plays with controllers and touch. A game's second screen is a phone joined from `onLink`'s address: `Lamp.phonePage`
is a TV app's page's only.

### Lamp's player

Every game and screen on the Mac is its own Mac app (its own name, bundle id, icon, Dock and ⌘-Tab entry, opening
without Lamp), but none is compiled for itself: each is a copy of **Lamp's player**, one Mac app around a page compiled
when Lamp is built and shipped in its bundle as `Contents/Resources/LampPlayer.bundle` (not an .app, so the system never
lists it as an app of its own). build.sh writes its Swift with `Lamp --player-sources` (`GameKit.playerSources`: the
same `LampWebGame.swift`, `LampWebApp.swift`, `LampPage.swift`, the default `Native.swift` and LampSupport.swift a
compiled page app has, with `apple/LampPlayer.swift` as its main.swift), compiles it with the same `__RESTRICT` segment
every app Lamp builds has, and keeps it in `.build/player` under a key of its sources and the compiler (a release builds
it afresh); it's signed with the rest of Lamp. Its version is a hash of those sources (`LampPlayerVersion` in its
Info.plist, `GameKit.playerVersion`).

Nothing of one game is compiled in. What `Template.write` fills in for a compiled app is read by the copy from its own
bundle: its name (`CFBundleDisplayName`), what kind of page it is, where the page is served and the fixed canvas a screen
made at 1920x1080 has (`LampPlayer` in Info.plist, `GameKit.playerPlist`, read by `LampPlayer` in main.swift, which opens
`LampGameApp` or `LampWebApp`); what it's told about itself and Lamp (`LampInstall`), its permission reasons, its
capabilities.json, its icon and the chat beside it are what `stageSigned` gives every Mac app. It always carries
`LampWish` and `LampPageWish`, as every app on its own does (`Template.carriesWish`), and looks for its other copies only
once Lamp's room shows one, so it asks for nothing it doesn't use.

To make one, the game's own build.sh copies the player in place of `swift build` (`LAMP_PLAYER`, handed over by
`GameKit.playerEnvironment` only for the Mac): it renames the binary to the game's program name, writes the game's
Info.plist as before, puts `Web/` in Contents/Resources/Web and signs it ad hoc; it runs in the app's sandbox as every
build does, with the player opened for reading. Lamp then installs and signs it as any Mac app (`stageSigned`: the
identity and entitlements Mac apps get). That takes about a second, and needs neither the Command Line Tools nor Xcode
(`Pretend.buildEnvironment` runs builds with no developer folder while `LAMP_PRETEND_MISSING` has `tools`, so a build
that would compile fails as on a bare Mac). The copy is stamped with the player's version (`BuildStamp.player`): one
made by another player, compiled where the player would do, or copied where it's compiled now reads as out of date and
is made again when it's opened from Lamp (`BuildStamp.playerOutdated`), and the version is in the build's inputs
(`GameKit.playerInput`), so a new player also makes it again at the next look.

**When it's still compiled.** A page with Swift of its own in `Sources/` (`GameKit.hasOwnSwift`: a `Native.swift` that's
no longer Lamp's, which is how a page reads the person's things, or any other file; Home HQ's reads calendars and photos)
is compiled as before. The rule is decided at every build (`GameKit.usesPlayer`), so adding or taking away Swift moves it
between the two, and `Rules.pageNative` tells the agent that Swift of its own makes builds slow and needs Apple's tools.
iPhone, iPad and Android copies are always built as before. Since bundle ids stay per game, camera, microphone and
photos permissions stay per game too; macOS's **Local Network** answer goes by the executable's build ID (see "Two
Lamps on one Mac"), and every copy of one player has the same executable, so it's asked once and that answer is shared
by every game and screen made from that player, until a new player comes with a Lamp update.

**Without Apple's tools.** A wish's requests wait for the Command Line Tools only when something in it is compiled
(`Store.needsAppleTools`, `readyFor`: a wish not yet named goes ahead, and its turn waits once the naming call names
something compiled). Lamp asks for the tools only then, and the desk's and the chat's banners show only while they
install or something waits for them. git is one of Apple's tools, so on a Mac without them a game has no versions (and
no Undo) until they come; Lamp never runs `/usr/bin/git` then (`Versions.hasGit`), which would open Apple's installer.

A C++ game is written against Lamp's game kit (`Resources/GameKit`): `lamp_game.h` (`game_init`, `game_frame` with the
controller in `LampPad`, `lamp_asset`, `lamp_save`/`lamp_load`, `lamp_log`, `lamp_random`, `lamp_rumble`, and sound: `lamp_sound_load`,
`lamp_sound_tone`, `lamp_play`, `lamp_music`, `lamp_volume`), drawn with sokol_gfx, with sokol's shapes, text and GL,
HandmadeMath, cgltf and stb_image, all compiled in `lamp_kit.cpp`. Sound is the kit's own mix (`lamp_sound.cpp`: effects
decoded whole, music read as it plays, with stb_vorbis, dr_wav and dr_mp3, 32 voices at 48 kHz), which the console's
host plays through XAudio2 on a thread of its own and the preview mixes after each frame without playing it, so the
game's timing never depends on it: the preview reports what played and how loud the mix came out (`lamp_preview`'s
"Lamp sound:" line), and a fifth argument writes the mix as a WAV file to listen to. Lamp
writes the kit flat into the game's `Lamp/` before every turn and build (`GameKit.write`, only what changed, and
`kit.stamp` so the build compiles Lamp's code again only then); the agent writes `Game/` (.cpp and .glsl) and `Assets/`.
The kit has two hosts, Lamp's too: `lamp_xbox.cpp`, a CoreWindow app with a Direct3D 11 swap chain at 1920x1080,
Windows.Gaming.Input, the log and saves in the app's LocalState, B kept from leaving the game, and Present with vsync
(without it the console ends the app after one frame), which logs its frame times every ten seconds; and
`lamp_preview.mm`, the same game drawn with Metal out of sight at 60 frames of game time a second, from a script of
the controller's moves (`hold <frames> <sticks> <triggers> <buttons>`, `shot <name>`), the same seed every play, with
sokol's draws and vertices counted. `build.sh xbox` compiles with clang-cl for x86_64-pc-windows-msvc against the
Windows SDK and links with lld-link as an app-container exe with a static C++ runtime (so the console needs no package
of Microsoft's beside it), and zips App.exe with Assets/; `build.sh preview` compiles with the Mac's clang. Shaders are
annotated GLSL compiled by sokol-shdc into one header with HLSL and Metal; the console compiles the HLSL at launch with
its own d3dcompiler. Both builds, and every play of the preview, run in the app's sandbox (`Sandbox.run`).

`look_at_app` on a game builds the preview and plays two seconds from the start (`Store.lookAtGame`); `use_app` takes
`stick`, `button` and `wait`, adds them to that play and plays the whole of it again from the start (`GameKit.plays`,
`Store.useOnGame`), so after a change to the code the same moves show what changed, wherever the game is played.
`look_at_app` with `on_device` opens it where Try On points and looks there: its window on this Mac, the simulator, or the
Xbox. On the Xbox, `on_device`, Play and the end of a turn build for the console and put it there through the
integration's bridge: `stop` ends
the copy there first (installing over a running copy can leave the next launch failing with 0x800700BF), then
`install` and `launch` through `IntegrationRunner.open`: a console only just done installing refuses the launch for a
while (0x8D160120, 0x80073D00 or 0x80070002, longer when the copy it replaced was open) or takes it and shows its own
"not ready yet", so a refused launch is asked again with growing pauses, and one the bridge's `running` (Device Portal's
processes listing `{packageFullName}`) doesn't see running within a few seconds is launched again. One that never opens
is said plainly in the chat ("still finishing installing"), never claimed open, and the activity line says "Finishing
installing on Xbox…" while Lamp waits (`DeviceApps.install`'s `waiting`); `look` is Device Portal's screenshot and `log` reads the game's log from its LocalState. Deleting a wish
takes its app off every device Lamp put it on (the bridge's `remove`, `DeviceApps.removeEverywhere`), web apps too. The
package is Lamp's (`MSIX.package` with `.program("App.exe")`, an x64 identity, `MSIX.Identity.architecture`).

An Xbox gives a package installed as a game far more than one installed as an app (5 GB of memory rather than 1 GB, and
much more of the GPU and CPU, about twice the frame rate for a scene that fills an app's share). Device Portal can't change one package's type; the console decides it at each install from its "treat UWP apps as
games" setting, `DefaultUWPContentTypeToGame`, and an update installed with it off is an app again. So the install sets that
setting to `{isGame}` and puts the person's back once the app has been launched (`restore`, `IntegrationRunner.putBack`,
held by `DeviceApps.install` across install and launch, one at a time per device): the console settles the type after the
install's last step, and put back sooner, a person's "on" made a non-game a game. The type stays with the package after. `{isGame}` is `DeviceApps.isGame`: a native
game always, and a web app when its capabilities.json says `{"game": true}` (`Template.Capabilities.game`), which the
rules ask of anything played, or its icon.json does (`IconSpec.game`, which the agent has written for every game, so one
made before capabilities.json asked is a game too). That's an explicit line the agent writes, not a guess from the code: three.js draws scenes
that aren't games and a game may not use it. The native host logs the memory the console gave it, which says which it got.

The tools are a download (`WindowsTools`), in `Edition.sharedDeveloperFolder`/Windows like Android's, in two parts.
sokol-shdc at a pinned commit (for Apple silicon and Intel), which every build of a game needs, is fetched by itself the
first time a game is built (`installPreview`), with nothing to accept. The console's part, asked for only when a game
first goes on an Xbox (the setup window `WindowsSetup`): clang and lld (with clang's own headers) out of LLVM's release
for Apple silicon, against its published SHA-256, and Microsoft's Windows SDK and C runtime fetched by xwin, which Lamp
ships (built by build.sh with cargo, pinned and locked; a release needs it) and which checks Microsoft's packages
against Microsoft's manifest. Microsoft's license is the person's to accept, in the setup window, before xwin runs:
nothing of Microsoft's is passed on. Intel Macs make and play games, but can't put them on an Xbox (LLVM publishes no
such build).

A request for a wish's game to be more fun as a whole ("Make it a lot more fun", one of New York's first changes, or the
person's own words for it; not one that scopes or refuses it) carries a note naming what it asks for (a better loop and
difficulty curve, juice, surprises, playtesting in the preview), sent with it to every engine, whether it starts a turn
or is handed to one with Send Now (`GameFun`, `Store.turn`, `Store.handOver`); what makes a game fun is said once, in the
game skill's "Fun" and "Playtesting".

## Web apps

A web app (`Platform.webApp`, `Targets/WebAppTarget.swift`) is what `make_app_for` makes of an app made with web: the
screen's recipe (`ScreenKit`, with `ScreenKit.webAppPage`: its own mark `.lamp-web-app`, its own page address
lamp-web-app://app/ and so its own saved data, `Sources/LampWebApp.swift`, its page laid out at the window's size with
no fixed canvas, and Web Apps/ to install in), going wherever a page goes and looked at as a screen is (below). A screen is
never made into a web app or back: each keeps its own address and saves.

## Screens

A screen (`Platform.screen`, `ScreenKit`, `Targets/ScreenTarget.swift`) is a web app as Lamp once made them: the TV
app's page in `Web/`, with the same `Web/lamp.js` (`TVTemplate`), taking places as a game does (`addsPlaces`, the Mac
always first, then any place a page goes). No new app is made one by the agent: it has no device words, and
`AppKinds.target` only keeps a wish's own screen; a starter may still be one (Home HQ). What's kept is everything a
screen already made relies on: its folder and mark (`.lamp-screen`, refining the TV's recipe), its identity and install
in Screens/, and its page's address, lamp-screen://app/, where what it saved is.

**The page fills whatever it's shown on**, as a web page fills a browser: a TV, a Mac window of any size, a photo
frame, an iPad either way up, a phone. It's laid out as a responsive page (`Rules.screenDesign`: grid and flexbox, sizes
from the screen, media queries for its shape; the scaffold, `ScreenKit.indexHTML` and `styleCSS`, sizes everything from
`--u`, a hundredth of the screen's shorter side), and every place hands it the real viewport. On the Mac, the iPhone and
the iPad it's Lamp's common app around a page (`LampWebApp.swift` filled in by `GameKit.webApp` with the screen's
address, written as `Sources/LampScreen.swift`), whose web view takes the window's size; on Android and Android TV it's
Lamp's Android app around the page, as a game's is, kept awake and not a game to the system
(`GameAndroid.screenActivity`, `screenManifest`); on a Samsung or LG TV it goes as a TV app does, and on the Xbox as the
integration's web app. A screen made before screens filled any shape says `width=1920` in its viewport meta
(`ScreenKit.isFixed`): the app around it is then given a 1920x1080 canvas it zooms whole, and the rule tells the agent
to change its viewport first when it's to go somewhere tall. On the person's own iPhone or iPad the phone's Xcode
project carries `Web/` as a folder beside Assets (`Template.withWebFolder`, `Devices.stage`), as it does for a web
game.

**Where the agent looks at it.** The agent looks at it and uses it where the person sees it: its Mac copy, when the page
has one (`hasMac`) and it's open or Try On points at the Mac, where a look opens it (`Store.pageOnMac`, the same for a
web app and a game with a loop of its own, `GameKit.ownsLoop`). That copy is looked at as a Mac app is: built (a change
of the page alone goes into the open window, `PageLive`, which a screen's and a web app's host take as a game's does,
the page opening again with what it saved), pictured by LampSupport, and used through `LampDriver`. The accessibility
tree LampSupport reads stops at a web view's edge, so the page lists its own things for the screen as text
(`LampPageReader` in LampPage.swift, behind LampSupport's `LampPageItems`): the same script the preview reads a page
with (`PageScreen`, written in by `GameKit.page`), each box turned into pixels of the window's picture, read again
before each picture and after each action; clicks, keys and typing reach the page at those points as the person's do,
and a remote's back, OK and enter are sent as Escape and Return. No preview opens then.

The preview on the Mac (`TVPreview`, `openDevicePreview`) is for the rest: a page that nothing on this Mac shows (only on
a TV or the Xbox, with no Mac place, or one whose Mac copy is closed while Try On points elsewhere), and any other shape.
`look_at_app`'s `shape` (a width and height in CSS pixels, "390x844") is always the preview's: it turns the preview's
window to it and lays the page out at that size (`TVPreview.reshape`), the picture drawn with its long side 960 pixels
and `use_app`'s points measured in it (`TVPreview.scale`); the preview keeps that shape for later looks, and starts at a
TV's 1920x1080. Turning the person's own window to a phone's or a TV's shape was ruled out: a Mac window has a minimum
size and the screen's, it's the window the person is using, and putting it back would fight their own resizing. A
preview opened beside a Mac copy (`asidePreviews`) is where `use_app` acts until the next look without `shape`, which
closes it, as the turn's end does. Pointed at a TV with no Mac copy it's staged and looked at as a TV app is.

**The preview holds the person's data, one way.** It's a web view with a store of its own (`TVPreview.store(for:)`), so
it never sees what the Mac copy saved. When a page with a Mac copy opens there, Lamp asks the open copy for its page's
localStorage (where LampStore keeps everything: `PageLive.saved`, answered over the copy's own `/app/page/live` poll with
`/app/page/saved`; what it said last is kept in memory while Lamp runs, for a copy since closed) and the preview's store
is emptied and filled with it before the page's scripts run (`TVPreview.show`'s `seed`). Nothing goes back: a seeded
preview never joins the wish's room (`TVPreview.isSeeded`, refused at `/app/wish`), so what the agent's `use_app` does
there never reaches the family's data on any screen. Joining the wish as a copy was ruled out for that reason: the
preview would push every click of the agent's into the shared collections. A preview with nothing to start from (the
Mac copy hasn't been open while Lamp ran) keeps what it had from its last opening and says so to the agent; a TV app's preview, which no Mac copy has, keeps its own
store and joins its wish as before.

`make_app_for` with the places it's to be on sets them (`Store.setPlaces`), and the request's device line says where
it's shown (`Rules.screenPlaces`) and where looks go (`DeviceNote.macWindow`). The preview stands in for a TV only while
Try On points at one; elsewhere it's just "the preview", its window titled "<name> Preview" (`Store.previewDevice`), so a
web app at home on the Mac is never told it's on a TV; the name follows Try On while the preview stays open
(`TVPreview.follow`). Before finishing, the agent looks at it in the places it's shown and no others
(`Rules.screenDesign`, `screenShapes`): the Mac in its window, without `shape`, and every other place at its shapes. An app made into one is given its kind before `make_app_for` sets its places,
so its change rules read the shapes off the request's device line, and `make_app_for`'s answer names those of the
places set (`Rules.screenPlaced`).

Designing for a TV seen from across the room is the `tv-design` skill, offered by the rows of the table that are TVs
(`Place.skills`, an integration's `skills` in its JSON: the Apple TV, Android TV, Samsung and LG, the Roku) to any app on
one, game or app, web or native, in its prompt (`Skills.forDevices`) and in `make_app_for`'s answer when it goes on one
(`Skills.forNewDevices`). The TV prompts keep only what their host does (the page's 1920x1080, the remote's keys).

A kind that takes places has what its places give it, not what its kind could (`LampProject.hasMac`, `hasIOS`, `hasTV`,
`hasDevice`, read where an app is at hand): a game played on the Mac alone is asked for no Xcode or team. A game's or a screen's Mac copy is installed in Games/ or Screens/ of the apps folder (`Target.installFolder`), apart from a Mac app of its wish, which has the wish's name.

**What a page can reach.** A web game's page and a screen's have Lamp's web building blocks in `Web/lamp.js`
(`DeviceSupport.webJS`, written for a game on the Mac too, not only on the Xbox), and on the Mac, iPhone and iPad the
app around the page answers for them (`Sources/LampPage.swift`, `LampPage.attach`, Lamp's common host, shared by
`LampWebGame.swift` and `LampWebApp.swift`): LampAI's calls go through the app to Lamp with the app's own token (`lampGateway`, only the AI
routes, `/ai`, `/ai/status`, `/ai/image`, `/ai/decide`, `/ai/act` and `/ai/hear`, the same list as Android's `LampPageGateway.kt` and the TV preview's,
only from the app's own page; the page's voice, `LampVoice` in lamp.js, is answered there too: `LampPageVoice` in LampPage.swift records with
AVAudioEngine and `LampPageVoice` in LampPageGateway.kt with AudioRecord's voice-recognition source, which on an Android TV box takes a
remote's microphone, both as 16 kHz mono 16-bit WAV, a screen's Android manifest asking for RECORD_AUDIO; asking what's possible never prompts,
and a recording ends with the page's session, its reload or the app leaving the screen; each recording has its own stop,
its limits run on the clock rather than on audio arriving (`LampVoiceEnd`, the same rule in both hosts), and its answer
goes only to the page that asked), and `LampNative.call(name, args)` reaches Swift the agent writes in
`Sources/Native.swift` (`Native.register()`, each call `LampNative.on(name) { args in … }` returning anything Encodable),
which has every building block in LampSupport.swift: the person's mail, calendar, reminders, contacts, photos, location.
Registering a call makes the Mac copy compiled rather than copied from Lamp's player.
So a game made of the person's unanswered emails, or a family calendar on the kitchen iPad, is a game or a screen and not
a Mac app. `Native.swift` is the app's own: Lamp writes it only when it isn't there and takes it away with the kind only
while it's still Lamp's scaffold, and the two Package.swift files compile all of `Sources/`. Everywhere else (a TV, the
Xbox, Android, Lamp's preview of either; LampAI still answers on Android and the Xbox) `LampNative.available` is false and its calls reject, so the rule
(`Rules.pageNative`) has the page show example content then, which also keeps the game preview's replay exact; a C++
game has no such bridge. In a wish of several apps the same app answers the page's `Lamp.wish` with its own `LampWish`
(`LampPageWish`, written only for such an app, as `LampWish` is), so a game or a screen on the Mac, the iPhone or the
iPad is one of the wish's peers (the "Wishes" guide).

