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
device's model and version, and keeps the mark while the step's text is unchanged.

The primitives and their guards (DevicePrimitives.swift, DeviceRemote.swift), which every place goes through:
`DeviceHTTP` (only the address the device was found at, which must be private or link-local and never loopback, so
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
hands on the device (`wait`) is checked again every few seconds while it's shown. `IntegrationRunner` runs steps and
sequences and keeps a device (`Integrations.Kept`, in Lamp's folder) only once a step has passed on it: a device found
is shown for the moment, never kept. A device whose certificate isn't the one kept (reset, or its developer mode turned
on again) is refused until the person reconnects it: the step's check or the install that met it puts a reconnect card
where its setup card goes (`DeviceReconnectCard`, `DeviceSetupModel.certificateChanged`), and Reconnect lets the kept
certificate go and starts its setup over from the first step (`reconnect`, `Integrations.startOver`), so the sign-in goes
only to the device whose new certificate the first request keeps; an app waiting on it goes on once that setup is done.
Only the person's click trusts a new certificate. Settings → Your Devices has Reconnect… and Forget… for every device
Lamp set up itself (an integration's, a TV; not a phone, whose pairing is the Mac's), Forget taking its record, its
certificates and keys, what was typed for it and its approvals (`Integrations.forget`, `TVs.forget`).

An integration whose `app` is declared makes its device a kind of app (`Platform.device`, with the integration's id in
`LampProject.integration` and meta.json; DeviceApps.swift), with no Swift of its own for that device: Roku, the first,
is all data. The naming call is told each such integration as a device a wish may name (`AppName.deviceKinds`), and
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
(`IntegrationRunner.Outcome.answers`, as plain text) and the log; `use_app` takes only `key` (Lamp's names in
`bridge.keys`, each pressed with `use`), `type` (the bridge's `type`, once per character as `{text}`, which in a path
Lamp encodes down to letters and digits; a Roku's `Lit_`) and `wait`. Stop runs the bridge's `stop` (a Roku's
`/exit-app/dev`), and presses `home` when there's none or the device refuses it. Lamp can't tell whether the
app is still open on the device, so Play always puts it there again. Such apps aren't shared yet. Lamp ships the Roku's
integration (`Resources/Devices/roku.json`): a channel in BrightScript with Lamp's building blocks, its icon and splash
screens, and a bridge whose `remove` is the developer installer's Delete, so deleting a wish takes the channel off the
Roku (a package that isn't wrapped has no names, so `DeviceApps.removeEverywhere` removes the device's one copy, and only
while it's still this wish's: `lastOnDevice` notes which app each device took last). Its
mobile-control step reads `ecp-setting-mode` from device-info, which Roku's ECP page doesn't list but Rokus report, and
asks only for Enabled, never Permissive. Its developer-mode step's button presses the remote's secret keys over ECP (`run`), which that
setting allows; the licence and the password stay the person's, on the Roku.

**Lamp's building blocks on devices** (`DeviceSupport`, DeviceSupport.swift): TVs and declared app kinds get `LampAI`,
`LampStore` and `LampAssets` as Mac, iPhone and Android apps do, under the same names and with the same advice in their
comments, so a change to one of those is made to all of them. A declared kind asks for them by library in
`app.declared.support` (`"web": "Web/lamp.js"`, `"brightscript": "components/Lamp"`); the TV kit always has the web one
in its `Web/lamp.js`, the Xbox's integration asks for it too. The web library is plain ES5 with Promises
(`DeviceSupport.webJS`, LampStore on localStorage); the BrightScript one runs each LampAI call in a Task node
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
app. The gateway listens on the network while a TV app is set to open on a TV or a device app takes the building blocks
(`Store.syncLocalNetwork`); from the network it answers a browser's preflight and lets the device's page read the answer
(only there: nothing on this Mac is answered across origins), and admits this Mac's own addresses as Host beside its
name (`Store.isMacHost`), since a web page can't choose its Host and these devices don't resolve `.local` names.

Settings → Your Devices lists what integrations find (`Integrations.devices`, after the kits' own) and the devices
that answered Lamp's SSDP scan that nothing knows, read from their UPnP description (routers left out). Set Up… on one
Lamp knows opens its window; on one it doesn't, it opens the device's setup conversation (`Store.setUpDevice`), one
per device, whose first request is `Agent.deviceSetupRequest` (what the device said of itself). That conversation is
no wish (`LampProject.deviceSetup`, `makesNoApp`): it's never on the desk, never named, scaffolded, built or saved, and
every request in it carries `Agent.deviceSetupNote` in place of the app's notes, so a follow-up ("it still says
waiting") stays about the device. Lamp refuses the app tools there (`Store.deviceSetupRefusal`: looks, use, versions,
art, kinds, connectors, `write_wish`), leaving the integration, skills, notes and the chat's cards. When
`device_integration` keeps an integration it looks for the device at once, puts each found one's next step in that
chat, and moves the conversation to the device's new id, so the setup window's Ask About Setup… leads back to it. Each kind of card has its gallery entries ("Device setup").

**Windows packages.** A declared app kind may say `wrap: "msix"`: the package step leaves a zip of the app's files and
Lamp makes the package itself (`MSIX`, MSIX.swift), with nothing outside Lamp: the zip read as plain files only (no
link, nothing above its top), a manifest Lamp writes (the identity is Lamp's: `Lamp.<folder>`, publisher `CN=Lamp`, a
version from the time so each build replaces the last), logos drawn from the app's icon, the block map and content
types, laid out as Zip64 with every file stored and the signature the one plain deflated record (Windows opens nothing
else), and an Authenticode signature (the APPX digest blob in an SpcIndirectDataContent) with a key and self-made
certificate kept in Lamp's folder (`MSIX.Signer`), which the device installs beside the package (`{certificate}`). The
bridge launches it by its names (`{packageFullName}`, `{appUserModelID}`, and `{base64:…}` of either). For Xbox's Device
Portal a request also carries cookies the device set earlier in its sequence (`{cookie:CSRF-Token}`), polls an install
that answers 204 until it's done (`poll`) and fails with the device's words unless the answer says what `expect` asks.
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
the rest Edge's `Gamepad…` names), and `navigator.getGamepads()` gives the standard mapping. Its web view never shakes the controller, so lamp.js puts its own `vibrationActuator` on every gamepad in the host, whose `playEffect` and `reset` go to the host as `rumble` messages, played with Windows.Gaming.Input as a native game's `lamp_rumble` is. The web view numbers controllers in another order than the host, so each effect carries what the page sees on its gamepad (buttons, sticks) and the host shakes the controller whose reading matches, remembering the pair for effects asked while nothing tells them apart. A package Lamp put on a
console before installs over the earlier EdgeHTML one (same family, newer version), so nothing moves an app across.

## Games

A game is a kind of wish of its own (`Platform.game`, Targets/GameTarget.swift, `GameKit`), never a device's: the naming
call gives "game" for a 3D game or one played with a controller or on an Xbox (a 2D game played with the mouse or by
tapping stays a Mac or iPhone app), with the devices it's played on beside the Mac in its `places`. Its home is the Mac, and the places it's
played are given one at a time (`LampProject.places`, kept in meta.json; `Target.startsAt`, `Platform.addsPlaces`,
`LampProject.openPlaces`, which `destination` goes by): the Mac always, an iPhone and iPad (`.ios`, the simulator or
the person's own, whose Xcode project carries `Web/`), Android (`.android`: Lamp's Android app in the game's
`Lamp/Android` (never `Android/`, which `Parts.folders` reads as a wish's Android app), `GameAndroid`, built and installed
like any Android app of Lamp's: a WebView serving `Web/` from the app's assets, the controllers read natively and handed
to the page's `lampNativePad`; in a wish of several apps it also carries Lamp's Kotlin blocks and answers the page's
`Lamp.wish` with `LampWish`, the "Wishes" guide) and the Xbox (`.device`, with `LampProject.integration` "xbox-one", the integration's web
app, installed as a game). `make_app_for` on
a game sets its places (`Store.kindPlaces`, `setPlaces`: every place listed, the Mac kept) and never changes its kind,
given as its entry's `places` in `make_app_for`'s `apps`, and a list without the game takes it away like any app of a wish (the "Wishes" guide; a game
can also be added beside a wish's other apps, in Game/);
Try On's "Play on iPhone and iPad Too" and "Play on Xbox Too" do the same (`addPlace`), and a place given is where it
opens next. What each place needs (Xcode and a simulator, the console's tools and the Xbox) is asked for when the game
first goes there, never up front: the kind's `setup` is `.none`. The places and the budget of the slowest (an Xbox
One's, a mid-range Android phone's, an iPhone's, an Xbox Series S's, an Xbox Series X's, this Mac's) ride with the request in
the device line (`DeviceNote`, `Rules.gamePlaces`), not in the prompt, since a place may be given at any time. The Xbox's is
the console chosen under Try On, else the slowest of the person's (`GameKit.xboxModel`), as Device Portal names it: the
integration's description says Xbox One on every console, so its `device-portal` step is the model step (`"model": true`,
`Integrations.model(of:)`), which also gives the device its model in the list and the agent's line. An Xbox whose setup
hasn't reached Device Portal is budgeted as an Xbox One. Places on the project are general: games and screens take them,
and an app kind that takes places one at a time (an Apple TV or a TV beside a SwiftUI app) is a `startsAt` away.

A game is drawn with three.js (`GameKit.Engine.web`, written in its `.lamp-game` mark): the model writes it best and every
place has a web view, and on the Xbox a game installed as a game gets enough of the console. A three.js game is a page in `Web/`, as an Xbox web app's is: `index.html` and the agent's modules,
with Lamp's `Web/lamp-game.js` (the game runtime: `game({ renderer, init, frame, touch })`, the same pads, buttons,
seeded `random()`, `save`/`load`, `log`, `rumble` and `sound` the kit has, the canvas fitted at 1920x1080, touch
controls on a touch screen) and three.js in `Web/three` beside it. On the Mac and iOS the Swift around it is
`LampWebGame.swift` (a web view serving the bundle's Web/ at `lamp-game://app/`, its log into the app's log, sound with
no tap first), built by `GameKit.webBuildSh`; on the Xbox it goes as the integration's web app ("xbox-one", the package
its declared step makes, `Web/lamp.js` written then), installed as a game. The agent's preview of it is
`WebGamePreview`: a copy of the page (`GameKit.stageWeb`, under the sandbox) in a web view nobody sees, given the same
script as the C++ kit's preview (`window.lampPreview`), which `lamp-game.js` plays itself at exactly 1/60 s a frame with its
clock and random numbers fixed, pausing at each `shot` while Lamp pictures the whole page, HTML over the canvas
included; the same script gives the same pixels. Its stats count draws and triangles (three.js's `renderer.info`).

A game made before three.js games is C++ on Lamp's kit (a device app of "xbox-one:game" then). It reads as a game whose
engine is `native` and whose one place is the Xbox (`GameKit.migrated`, in `Store.readWish`; its folder's old
`.lamp-device` marker still reads as a game's, `GameKit.isMade`, the kind `refines` the device kind, until its next build
writes `.lamp-game`), and is built and played as it was: for the Xbox, and in the kit's preview on the Mac. It can't be
given another place (`setPlaces`, `Store.placesToAdd`), and no new game is made in C++ (the naming call has no word for
it, and `make_app_for` takes no C++ kind).

On the Mac and on iOS a three.js game is an app like any other Lamp makes, of Lamp's own (`GameKit.webPackageSwift`,
`GameKit.webBuildSh`, `Sources/LampGame.swift`, `LampPage.swift` and LampSupport.swift, none the agent's), so its Mac copy
is installed, opened, quit and shown on the desk as a Mac app is, with the wand floating over its full-bleed window and
the chat beside it. A change to a game never goes into the open app (`LiveReload.eligible`, `Target.hostedByLamp`): it
reopens, held for Reload while the person has it open.

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
`install` and `launch` (asked again after a few seconds when the console refuses a launch just after an update,
0x80073D00); `look` is Device Portal's screenshot and `log` reads the game's log from its LocalState. Deleting a wish
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
against Microsoft's manifest. Microsoft's licence is the person's to accept, in the setup window, before xwin runs:
nothing of Microsoft's is passed on. Intel Macs make and play games, but can't put them on an Xbox (LLVM publishes no
such build).

## Screens

A screen (`Platform.screen`, `ScreenKit`, `Targets/ScreenTarget.swift`) is something shown full screen and glanced at
from across a room: a family calendar, a photo album, a dashboard, a clock. It's the TV app's page in `Web/`, with the
same `Web/lamp.js` (`TVTemplate`), laid out at 1920x1080, and it takes places as a game does (`addsPlaces`, the Mac
always first): on the Mac, the iPhone and the iPad it's a Swift app of Lamp's own around the page
(`Resources/GameKit/apple/LampScreen.swift` with LampSupport.swift, so it has the wand and the chat beside it), which
zooms the page to the window; on a Samsung or LG TV it goes as a TV app does, and on the Xbox as the integration's web
app. A TV app (`Platform.tv`) stays what it was, the TV its one place: a screen is its own kind, whose recipe refines
the TV's (a screen's folder holds a TV app's page as well as its mark, `.lamp-screen`). On the person's own iPhone or
iPad the phone's Xcode project carries `Web/` as a folder beside Assets (`Template.withWebFolder`, `Devices.stage`), as
it does for a three.js game. Wherever it's shown the agent looks at it in the TV preview on the Mac
(`openDevicePreview`), the same page at the same size, so a change is seen without a build of the Mac app; pointed at a
TV it's staged and looked at as a TV app is. `make_app_for` with the places it's to be on sets them (`Store.setPlaces`),
and the request's device line says where it's shown (`Rules.screenPlaces`).

A kind that takes places has what its places give it, not what its kind could (`LampProject.hasMac`, `hasIOS`, `hasTV`,
`hasDevice`, read where an app is at hand): a game played on the Mac alone is asked for no Xcode or team. A game's or a screen's Mac copy is installed in Games/ or Screens/ of the apps folder (`Target.installFolder`), apart from a Mac app of its wish, which has the wish's name.

**What a page can reach.** A three.js game's page and a screen's have Lamp's web building blocks in `Web/lamp.js`
(`DeviceSupport.webJS`, written for a game on the Mac too, not only on the Xbox), and on the Mac, iPhone and iPad the
app around the page answers for them (`Sources/LampPage.swift`, `LampPage.attach`, Lamp's, shared by `LampWebGame.swift`
and `LampScreen.swift`): LampAI's calls go through the app to Lamp with the app's own token (`lampGateway`, only the AI
routes, only from the app's own page), and `LampNative.call(name, args)` reaches Swift the agent writes in
`Sources/Native.swift` (`Native.register()`, each call `LampNative.on(name) { args in … }` returning anything Encodable),
which has every building block in LampSupport.swift: the person's mail, calendar, reminders, contacts, photos, location.
So a game made of the person's unanswered emails, or a family calendar on the kitchen iPad, is a game or a screen and not
a Mac app. `Native.swift` is the app's own: Lamp writes it only when it isn't there and takes it away with the kind only
while it's still Lamp's scaffold, and the two Package.swift files compile all of `Sources/`. Everywhere else (a TV, the
Xbox, Android, Lamp's preview of either) `LampNative.available` is false and its calls reject, so the rule
(`Rules.pageNative`) has the page show example content then, which also keeps the game preview's replay exact; a C++
game has no such bridge. In a wish of several apps the same app answers the page's `Lamp.wish` with its own `LampWish`
(`LampPageWish`, written only for such an app, as `LampWish` is), so a game or a screen on the Mac, the iPhone or the
iPad is one of the wish's peers (the "Wishes" guide).

