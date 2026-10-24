# TV apps

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

An app can be made for TVs (`Platform.tv`, chosen when a wish names a TV, the Frame or the living room, or by
`make_app_for` with "tv" alone; given places beside the TV it's a screen, shown on this Mac, an iPad or the Xbox too, "Screens" in
the devices guide). It is a web app, HTML, CSS and JavaScript in `Web/`, the same files for Samsung
(Tizen) and LG (webOS) TVs, with no build step: "building" copies `Web/` into Lamp's own folder (`TVs.stage`, a copy
made under the app's sandbox, links refused), which is all the preview and the packages ever read. Lamp owns
`Web/lamp.js` (`TVTemplate.lampJS`, plain ES5 for the TVs' Chrome-79-era browsers): Lamp's building blocks for the web
(`DeviceSupport.webJS`, below), then the remote's keys by name, focus moved with the arrows to the nearest thing in that
direction, OK clicking, Back with `Lamp.onBack` and leaving the app when nothing handles it (`Lamp.store` is
`LampStore` under the name it had first). The rules are `Agent.tvPrompt` (`Rules.tv…`: a
1920×1080 page that never scrolls whole, design for the sofa, no syntax newer than 2019). Sound is the browser's own
Web Audio (`Rules.webSound`, also given to every declared kind with the web library, the Xbox's included), with no
building block of Lamp's: every one of these browsers has it, and the preview on the Mac plays it with no click first
(WebKit on macOS starts audio without one). The agent tries the app in
the TV preview (`TVPreview`): a window showing it at the TV's size, half scale, from the staged copy, where
the page is opened at an address of its own (`lamp-tv://app/`, `StagedFiles`) rather than as a file, so it reads its own
files with fetch and XMLHttpRequest, as text or bytes, as it does on a TV (WebKit refuses both to a file's page), and
`look_at_app` pictures it (`TVPreview.picture`: the window as the screen shows it, through ScreenCaptureKit's capture of the
process's own windows, which asks nobody, from macOS 14.4; WebKit's snapshot redraws the page without its CSS animations, so it
is only the fallback, and the agent is told its picture can't show movement; each picture says when it was taken and how long
after the one before, since the agent's own thinking between two calls is part of the time a movement took) and reads it as text (focusable things and text, with which has focus) and `use_app` presses
remote keys (synthetic key events with TV key codes), clicks and types; the page's console goes to the app's log;
each app keeps its own saved data there between openings, as a TV does (what it saved when earlier Lamps opened it as a
file is handed to its new address once, `savedFromFileAddress`). The preview runs in the Mac's browser, so everything
the agent is told of it (each look and use with `Store.notTheTV`, the screen as text, the note on its picture) says it is
the TV preview on this Mac and not the person's TV. Where the app is otherwise comes with the request, as the device line
(`DeviceNote.tv`), from Lamp's own state and never a fixed description: whether the preview is open, each of the person's
TVs with what's known of it (chosen under Try On, found on the network, set up, when Play last put this app on it and
whether the code has changed since, `Runtime.putOnTV`, which records what the staged copy was made from, read before the upload, and is read back through `AppFile`), and "unknown" for the rest, the TV's screen size and whether the
app runs there now among them. Lamp's tools don't reach a TV, but the agent is told it may find another way to see one,
not that it can't. Closing the window, by the person or by
Lamp, ends the page (its sound and timers): WebKit runs a page as long as its web view lives, so the preview lets go of
its script handlers and web view when its window closes. TVs are found on the network (`TVs.scan`:
SSDP, then a Samsung TV's own API at port 8001, an LG TV's UPnP description) and listed with the other devices; a
found TV is kept (`TVs.keep`, Lamp's TV folder) only once a setup step has worked, since a scan sees neighbours'
TVs too. Setup is a window of its own per TV (`TVSetup`), each step checked by Lamp. Samsung: developer mode on with
this Mac's address (read off the TV's API), a connection over sdb (`SdbConnection`: adb's protocol on port 26101,
spoken directly, pieces kept to 4096 bytes), which reads the TV's device id and Tizen version, and Samsung's
permission: the person signs in to their Samsung account on Samsung's page (the sign-in posts back to a listener
on this Mac's loopback only), and Lamp makes an RSA key and asks Samsung's certificate service for an author and a
distributor certificate naming the TV (`TizenSigning`, the requests Tizen Studio's certificate manager makes; key and
certificates in Lamp's folder, closed to the agent; Samsung's two public CA certificates ship in
`Resources/TVCertificates`). Lamp then signs every package itself (`TizenSigning.signatureFile`: the W3C widget
signature, written already canonical, RSA-SHA512 over each file's SHA-512; checked to reproduce a Tizen Studio
signature exactly), zips it (`TVPackage.wgt`, with a `config.xml` Lamp writes, never the agent), pushes it to the TV's
staging folder, installs with `0 vd_appinstall` and opens it with `0 was_execute`, retrying until the TV says it has.
LG: Developer Mode from LG's store with its Key Server on, the passphrase it shows typed into the setup window, the
key fetched from the TV (port 9991) and unlocked with `ssh-keygen`, then `TVPackage.ipk` (an ar archive Lamp writes,
with tarred control and data), copied over SFTP as LG's ares-install does (`WebOS.put`: the developer shell has no `scp`, and a
TV whose SSH server offers no SFTP gets the file streamed into `cat`), then `luna-send-pub` over SSH as `prisoner` on port 9922 with its
input kept open until the TV's answer, since it gives up when its input closes (`WebOS.luna`, through
`Subprocess.run`'s `keepInputOpenUntil`), and the
developer-mode session renewed with LG at every install. Play with a TV chosen under Try On (`Store.setTVDevice`, which
runs that TV's setup first) packages and installs; the preview needs nothing set up. Lamp's Info.plist carries a local
network description; the first scan brings macOS's firewall and local network questions. A TV app is shared as a
`.lampapp` like any other (format 10): its Web/ and Phone/ travel (`TVFiles`: pages and scripts as code, which the review
reads, pictures and sounds as data), never Lamp's lamp.js, which the Mac that opens it writes back as it installs them.

A TV app may have a page for a phone (a controller, a buzzer, a second screen) in `Phone/` (`TVTemplate.phoneFolder`,
`Rules.tvPhone`, a short pointer: how to build the page, controllers, tilt and second screens are the `phone-controllers`
skill, which only the TV prompt offers). Lamp serves it, so the agent never starts a server or a login item that would outlive the app: it's
staged beside `Web/` the same way (links refused) and never packaged, into a folder nothing serves, and put in place of
the served one in one swap only once it has passed (`TVs.publishPhone`), so a request never reads a copy being made or
one that failed. It's served by Lamp at a port of the app's own (`PhoneSites`, from `Edition.phonePagePorts`, sixteen
for each Lamp), so each app's page is an origin of its own in the phone's browser and what one app's page keeps is out
of another's reach. The sixteen are a pool, not a limit: an app keeps its port while it can, and gives it up to an app
that needs one once its own page isn't served (or it's gone). A site counts as open only once it's listening
(`PhoneSites.open`), a port another program took meanwhile is left for the next free one, and a page's address is only
ever given for the port its site holds (`PhoneSites.ready`), sent to the TV page again when the site moves. The site answers with the app's files (`Store.phonePage`), reached through no link at any step
(`TVs.phoneFile`), only while the app runs, in the preview or set to open on a TV (`Store.servesPhonePage`), from the
network by the Mac's name or address and on this Mac by a loopback name, with no token, since a phone following a QR
code has none; it's opened and closed with the rest of the network listening (`Store.syncLocalNetwork`). The TV page
reads the address from `Lamp.phonePage(hash)`, which Lamp writes into the staged lamp.js (`TVTemplate.phoneMarker`) and
which lamp.js asks for again as the page opens and every half minute (`/app/phone-page`), the preview being told at once
when the site moves; `Lamp.onPhonePage` hears each change, so a QR code follows the page. The address is plain http at the Mac's local address, so a phone's browser won't give the page motion sensors or the camera, which
need https.

Phones as controllers never go through Lamp's own process: Lamp introduces the two sides and hands out short-lived
credentials, and they talk directly or through a relay of Lamp's own (`PhoneControllers`), over the home network the
phone page is already served on, so nothing is hosted and nothing leaves the home. The relay (`LampRelayKit`'s `Relay`)
runs as a process of its own, `LampRelay` in Lamp's Helpers, started by `ControllerRelay` while a TV app takes players
or a wish's apps have a room there (`WishRooms`, under "Wishes of more than one app") and ended when none does, or when
Lamp quits (its input closes). Lamp tells it on its input which apps' sessions are open
(their generation, phone page port and address, this Mac's names) and gives it the controllers' key; it speaks
WebSocket with the Network framework on a queue of its own and keeps the port it had while Lamp runs. The phone page
loads `lamp-controller.js`, which Lamp serves beside the app's files (`TVTemplate.phoneControllerJS`: `LampController`'s
buttons, sticks, messages and files, and tilt asked for from a tap), asks the page's own site where the relay is
(`lamp-relay.json`, before each try) and opens its socket there, by the name the page was reached at. A link just opened
always wins over a credential the page kept from before. The TV page has `Lamp.controllers` in lamp.js
(`TVTemplate.controllersJS`), the same in the preview and on a TV: it asks Lamp who its players are (`/app/controller`,
through the preview's bridge or the gateway, as it opens and every 15 seconds) and opens its own sockets to each: the
relay, with a host credential, and each of the wish's iPhone apps listening (below), with a ticket. The preview's page
reaches them from WebKit itself, never through an `evaluateJavaScript` or a script message per message. lamp.js numbers
the players, whichever way they came, and tells each its number (`player`). The credentials are the controllers' own
(`ControllerCredential`, `ControllerToken`, signed with a key kept only in Lamp's memory and the relay's: a host's for
the session, marked when it's the preview's so a TV running the same app waits for it; a join link's for fifteen
minutes; a phone's for two, renewed over its socket), never the app's token for its AI, and ending a session (the
preview closed with no TV chosen, or the app's page no longer served anywhere, deleted included: `PhoneSites.sync`)
makes all of them worthless and has the relay let its sockets go. Of web pages, the relay lets in only an app's own
phone page, by its origin (an http origin at a phone page's port and one of this Mac's names); a TV page (the
preview's own address, a TV's `file://` or `null`) and anything that isn't a browser (no origin) are let in by their
credential alone, since such a client could say any origin it liked. A dropped phone keeps its place while its
credential lasts. The relay keeps no message, beats every five seconds, drops a phone's stick or tilt while the TV is
behind, and tells the host when a phone leaves, when lamp.js lets go of what it held; lamp.js drops movement older than
300 ms. A message is at most 16 KB of JSON (`ControllerWire.message`), and the relay closes a socket that sends a
bigger one, so every library of Lamp's (lamp.js, lamp-controller.js, `LampController` in LampSupport) refuses one before
it goes: `send` returns false, the reason with the limit goes to the console or the app's log, and a phone's library
tells the TV app (`too-big`, passed on by the relay), whose log the builder reads. Anything bigger is a file
(`sendFile`/`onFile` both ways, `TVTemplate.filesJS`, `ControllerWire`): up to 64 MB, in pieces of 64 KB in binary
messages, the sender never more than 512 KB past what the receiver has acknowledged, two at a time each way per phone.
The relay holds each file to the size it was announced at and to that window, and cuts off one that doesn't keep to
them; it and the libraries hand the network one piece at a time and text at once, so a button never waits behind more
than one piece. The relay never holds more than it must for anyone: a socket that hasn't said hello within five seconds is
let go (cancelled outright before its handshake ends, since a close frame can't go then), at most 64 wait at once (8 from
one address, an IPv6 one by its /64), a phone past its rate for ten seconds is let go, what phones send a TV that's
behind is dropped, any peer more than 256 messages or 2 MB behind is let go, and an acknowledgement goes on only for a
piece the relay passed. A wish's iPhone app takes each ticket once. The page is plain http, so phones keep their motion sensors from it: buttons and sticks work, and tilt
only where the person has put https in front of the page themselves (`LampController.canTilt`); Lamp builds nothing for
that, and such a page can't reach the relay, which speaks plain ws.

