# Wishes of more than one app

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

A wish can be more than one app made to work together: a TV app with an iPhone app that controls it, a Mac app with an
Android app (`Parts`). The wish is its own thing, apart from its apps: its name, chat, versions and icon are the wish's,
and which apps it should have is its list (`LampProject.apps`, `WishApp`, in its meta.json; below). One app is at its
root, as every wish has one; each other part is an app of its own kind in a folder of the wish's
(`iPhone/`, `Mac/`, `Apple/`, `TV/`, `Android/`), with its own `.lamp/meta.json`, build files, bundle id and runtime folder, so it's built,
opened, looked at and used as any app of its kind is. It's a `LampProject` in `Store.projects` with `partOf` set (id: the
wish's, a dot, the folder), never on the desk (`Store.wishes`), with no chat or versions of its own: what's logged
for it goes to its wish's chat (`Store.log`), and the wish's history keeps its folder. No app of a wish comes first
beyond that: each carries the wish's icon. Its design and artwork are the wish's (`Icons.home`), drawn into each app's
own `.lamp/` (its build and finishing run in its sandbox, which opens only its folder), and new artwork or a new design
reaches every app of the wish (`Store.iconToParts`). Its `realDir` takes the wish's folder by name too, since the agent can put a link in its place, and it's
told where its folder is when it's installed (`folder` in `Template.installValues`, read by `LampInstall.app`), since its
id is no folder's name. A wish's parts are found from its files (`Parts.folders`: one of Lamp's part folders holding a
scaffold it can hold, any of Apple's kinds in an Apple folder, since a part made for more devices is changed in place),
never from the wish's list, so a rename, an Undo or a restored version can't part a wish from its
apps, and every restore takes them in again at once (`Store.followRestored`, comparing folders and kinds,
`Parts.match`: a part the version doesn't have is quit and then forgotten, one the person keeps open over unsaved work
stays listed until it's closed, and one it brings back or changes is listed again). A wish's name is in its meta.json,
which no version holds, so the versions that change it carry it (`Lamp-Name`, `Lamp-Renamed-From`), and Undo or going
back to a version gives back the name that version had (`Versions.name(at:in:)`), its parts with it. Lamp's own files
(build.sh, the Info.plist lines) carry the name, so a rename and a restore that gives one back write them, the parts'
too, under that name before the version is saved (`Versions.restoreFiles(name:)`): written after, the next build left
the app unsaved and Undo could never get past the rename. A part's quit is judged by its
wish's turn, which is the only one it has. Deleting a wish closes each part first (a Mac part may be kept open
over unsaved work, which stops the delete) and forgets what Lamp keeps for it (`Store.forgetPart`: its installed copy,
build folders, sign-ins and place in the lists), as taking a part away does; the list of apps is set in one go with the parts (`Store.reload`), since a moment without them ends a TV app's
game. A part never has a turn of its own: Lamp's own requests for it (carrying on after its Reload, fixing its crash) are
its wish's (`Store.requestOwner`), and so is everything a part's Reload goes by (whose turn has the app, whether the
person stopped or was asked, what's pressed for them while they're away): the Reload in the wish's chat is for whichever of
its apps waits. No app of a wish comes first in what a turn and the wish's history do to it. At a turn's end each app the
agent changed is built, its errors sent back to the agent with its name and folder, before the version is saved, then
opened as the app at the root is (`Store.settle`). An app whose change went into the open app counts as built there
(`Runtime.needsBuild`): its whole build, which writes what it was built from, runs on after the turn. Each keeps its own look and crash on launch in the turn
(`Turn.Look.installed`, `crashes`, `LaunchWatch.app`), and a crash is fixed as that app's (`Store.crashRequest`). A part
is worked on under the wish's turn (`Store.asPartOf`, and a part's look through `underTurn`, each leaving the hold as it
found it). Undo and every restore rebuild each part whose files changed, and a copy builds every app, each under a hold of
its own so its crash is fixed through the wish (`Store.rebuildParts`); a rename puts the new name in every app's code and
APP.md. Each app's own menu (Open, Rebuild & Open) is still for that app alone. A copy is found by its install place only
for an app with a Mac copy there, since a TV wish's Mac app is installed under the wish's name. Which kinds a list
of devices makes is `Parts.kinds`: the devices of one part family are one kind between them (Apple's), in `Targets.all`'s
order. No kind leads: which app is at a wish's root is the wish's own affair, never the list's (`Parts.root`). A wish keeps
the app it began with at its root, and a new wish's root is the first of its kinds this Mac can build now (`Store.rootKind`:
a TV app with an iPhone app, on a Mac without Xcode, starts as the TV app with the iPhone app waiting), else the first.
The TV app of a wish takes the wish's other apps as players from its root or from TV/ alike (`Store.takesPlayers`,
`controllerSession`, which find the wish's TV app wherever it is). A device whose integration declares its apps still
stands alone.
Every app of a wish, Android's included, has `LampWish` (below) to reach the wish's other apps,
and is pointed to the `wish-links` skill on how they can share data (`Rules.wishTalk`, `Rules.androidPartTalk`). A wish is shared whole (`Sharing.export`, format 10 once it has a part): the app at its root
as any app travels, and each other app under its folder in the file, as an app of its kind (`Manifest.parts`,
`Package.parts`); the review reads every app's code, each part's files named with its folder first, and the Mac that
opens it makes each part as `make_app_for` does (`Store.installParts`, with the file's family for an iPhone part); one it
can't build yet is kept on the wish's list with its files beside the wish (`Sharing.keep`, `.lamp/waiting/<family>`,
by the part's family since the file's folder for it may not be this Mac's, unversioned, gone with the wish), which go in
over the scaffold, with the family the file gave them, once the part is made (`addPart`, `Sharing.kept`). An update from a
file replaces each part the file carries, changes one of another kind of the same family in place (`convert`, so it
keeps its folder and data), adds the ones the wish doesn't have, and leaves a part the file lacks as it is; a part whose
files can't be put in place, or kept, fails the update, which puts the whole wish back, its list and kept files included. A Lamp from before opens a wish's file as the app at its root alone, so a file
with a part says 10.

The wish's list (`apps`) is what it should have, not what it has: the kind of each app, and for one it still waits for,
what stops it (`needs`: this Mac can't build it yet, or its folder couldn't be made), so a quit or a failure between
asking for an app and making it loses nothing. What's made is read off the files (`Parts.wanted`, `Parts.waiting`,
which take the app at the root and each part found as made whatever the list says). The apps a wish waits for are made at
the start of its next turn (`Store.makeWaitingParts`), each tried once rather than at every turn, since the kind's check
opens its setup window: one this Mac can't build yet keeps what stops it and gets the chat's setup line
(`IPhoneSetupLine` with `part`, `LogLine.text` "iphone part"), whose setup, once done, clears it and sends the request
that adds it (`Store.retryWaitingApp`, `Parts.request`); the agent is told what waits at the end of each request
(`Parts.brief`, once per conversation and when it changes) and never makes one itself. The list follows every change:
`make_app_for` writes what it asked for, a part taken away or Undone leaves it (`forgetPart`), and the app at the root
changing kind (`convert`, a restore) takes its place in it. A wish for a device Lamp can't make apps for yet
(`waitsForDevice`) and one given its kinds in a turn begun without any (`decided`, whose engines' conversations are
forgotten when that turn ends, or at Lamp's next start) are kept in the meta.json too.

What the agent knows follows the parts. The wish's prompt is the kind's of the app at its root, with one rule naming the other parts
(`Parts.rule`); each kind a part can be has its rules as a skill made from the prompts' own rules (`target-iphone`,
`target-mac`, `target-apple`, `target-tv`: `Parts.packs`, the kind's rules without those about the wish as a whole, written
for the folder the wish's part is in, since an iPhone app made for the Mac too stays in iPhone/), named
with the request while the wish has that part (`Skills.applying`, so a compacted conversation is told again), and given
whole in `make_app_for`'s reply when the part is added. So a conversation never carries the rules of a kind its wish
doesn't have. `look_at_app` and `use_app` take `part` ("iphone", "tv", "mac"; `Parts.pick`), and run under the wish's turn
(`Store.underTurn`). `make_app_for` takes the whole list and makes the wish those apps by adding and taking away folders, never by
writing an app over again as another kind: the app at the root stays, changed by `convert` only inside its family (an
iPhone app that's to be for the Mac too); a part is added (`Store.addPart`), changed in place inside its family, or taken
away when it's left out. So "tv" added to a Mac wish keeps the Mac app's code and adds the TV app in TV/. A list that
leaves the root app's family out is refused with why, and the agent tells the person the wish keeps that app (a wish
still to be told what it's for has nothing written, so its root takes the first kind listed this Mac can build now,
`Store.rootKind`, and the rest wait as parts). So a wish read as an Android app and made as a Mac app while Google's tools
were missing gets, once they're set up, the Android app beside its Mac app (`Target.android.setup.later.request`), not in
its place. Play and Stop are for the whole wish: Play opens each of its apps not open yet, each on the device chosen for it, and Stop quits them all, shown while any of them is open (`Store.openWish`, `quitWish`, `isWishOpen`, and the desk's Use the same way). Each app has its own menu in the toolbar, the main one's Try On included, with Use or Quit for that app alone and where it opens; a line about where a part opens names the part ("The iPhone app will open on…", `Store.placeName`), since it has its wish's name.

A new wish that could be for more than one kind and doesn't say which (the naming call's `candidates`) is `undecided`
(kept in its meta.json, and through the naming that follows: `LampProject.named` carries everything a wish is): nothing is written, its prompt has no kind's rules (`Agent.undecidedPrompt`), the agent asks "TV, Mac or both?" with
`ask`, and gives it its kinds with `make_app_for`, whose reply carries the chosen kind's whole prompt. Each engine's
conversation began with the undecided prompt, so it's ended as that turn ends (`Store.decided`), and the next request
starts one with the wish's own prompt, told the chat so far (`CatchUp`).

The apps of a wish see each other and talk through a **room** for the wish at the controllers' relay (`WishRooms`,
WishHub.swift; `Relay.configureRoom`): each app of the wish, by its own token, asks `/app/wish` and is told the relay's
socket (by the name it reached Lamp at), which peer it is (its folder in the wish, lowercased: "tv", "iphone", "apple",
"mac", "android", kept when its kind changes in place; an app at the root is named by the folder its kind gets, so the name
survives a move into one; `kind` stays the device word the tools use), and who is in the room now; never anything that
lets it in. What lets it in is the **wish's key** (`WishKeys`): 32 random bytes per wish, made the first time an app of a
wish of several needs one, kept in Lamp's own folder by the wish's instance (never the wish's folder, which the agent's
commands read and versions and shared files carry), gone with the wish, and given to each app only as Lamp puts it on its
device and only by a way nobody on the network can read: the installed Mac app's Info.plist and the phone's build in
Lamp's own folder (`LampWishKey`, `Template.wishKeyPlistLines`), the simulator app's own folder after its install
(`Simulator.tellApp`), the Android app's storage through adb with its token (`androidInstallValues`), the TV preview's
page through its bridge (`/app/wish` with `preview`), and a TV over the network only sealed to an X25519 key pair the page
just made (`/app/wish/claim`, `WishRooms.claim`). That request is plain HTTP, so someone on the network between the TV and
this Mac could put their own public half in it and have the key sealed to them; only an encrypted link to the gateway would
stop that, so the claim is open as little as it can be (`WishClaims`, apart from the token's half-hour claim): from that
TV's address, two minutes from when Lamp starts putting the app there and two more from when it's open unless a claim was
answered meanwhile, and spent by the first claim answered, which in a normal install is the page's own a moment after it
opens. A request that fails spends nothing, and once spent the claim is answered again, for its minutes, only to the public
half it was spent on, which the page keeps across its tries, so an answer lost on its way doesn't need another install.
Over legacy `adb tcpip` (no TLS) the key
crosses in clear with the token. An app proves
it holds the key in a handshake that sends nothing anyone could use again (`WishChannel`, LampRelayKit): its hello names
the wish by a tag only the key makes and itself by peer id, with a nonce; the relay answers with its own nonce and an HMAC
proof over both; the app checks it, sends its own, and from then on everything but beats is AES-GCM, sealed each way under
a key from the wish's key and both nonces, numbered so a message changed, replayed, dropped or reordered lets the link go.
The connecting side is written four times (the relay's side in `WishChannel`, LampSupport.swift, LampSupport.kt, and
lamp.js's own SHA-256, HMAC, AES-GCM and X25519 in ES5, since a TV's page has no WebCrypto), held byte for byte to
CryptoKit's answers by `WishChannelTests`; change one and change them all. Every app of a wish holds the same key, so a
device with one of them could join as any; there is no forward secrecy; and a reset of a wish's key isn't offered yet. The
relay lets a peer in only once it has proved it holds the room's key and named an app the wish has, tells every member who joins and leaves
(`welcome`, with every app the wish has; `joined`, `left`: peer, kind, name, the device it said and since when), passes a `send` to one peer or to all as
a `message` with who sent it, tells the sender when the one it was for isn't there (`undelivered`), and holds peers to a
phone's size and rate limits (16 KB of JSON a message, `ControllerWire`); files between peers aren't carried yet. The same
block in every language, under one name: `LampWish.shared` in LampSupport.swift (a WebSocket of its own to the relay),
`Lamp.wish` in lamp.js (the same, from the TV page, in the preview and on a TV), and `LampWish` in LampSupport.kt, whose
blocks speak HTTP on a socket and so can't hold a WebSocket: Lamp holds the room's socket for the Android app
(`WishProxies`, `/app/wish/open`, numbered so nothing of an old link reaches a new handshake) and carries its handshake and
sealed messages each way as they are, unread: the app posts them to `/app/wish/send`, in the order it sealed them, and polls
`/app/wish/poll` for what came (answered as soon as something has, or after 6 seconds with nothing), and Lamp answers the
relay's beats for it. An app that stops polling (closed, force-stopped) has its socket let go a few seconds after its last
poll could have ended (`WishProxies.grace`), so the others see it leave while it's gone and arrive when it's back; and an app
back on a new socket before its old one was noticed gone is said to have left before it's said to join. The app's token is what lets it use those routes; the wish's key is what lets it into the room. Every
library has the same shape: `peers` (open now), `peer(id)` (any app of the wish, open or not, nil for none), each with a
`status` (`state`, a `reason` in the words to show, `lastSeen`), and the app's own `status`; a state is a value more may be
added to (a `RawRepresentable` struct in Swift, a value class in Kotlin, a string in lamp.js), so code that switches on one
keeps compiling when later work adds reasons. A reason is the same words in every language (`LampWish.notOpen`, `ago`):
where to open an app never seen ("Open the TV app on your TV."), how long ago one was last open ("The TV app was last open
5 min ago. Open it on your TV.", worked out again on every beat), and "isn't ready yet" for one Lamp hasn't made (the room's
list marks it `waiting`, from `WishRooms.describe(kind:)` through `configureRoom`'s `waiting`; once it has been open the mark
no longer counts). When each app was last open is kept on the device with the wish's list, so it's known after a relaunch
with the other app closed. A Mac or iPhone app whose network look is turned down by the system (`kDNSServiceErr_PolicyDenied`
on its browser or listener: the person said no to Local Network) is `localNetworkDenied`, with where to allow it, unless it's
connected anyway. Each library has a ready-made view of all of it, a line for each other app or one app's line, nothing after
`stop()`, for the agent to use, restyle or skip (`LampWishStatus` in SwiftUI and Compose, `Lamp.wish.statusView()`); nothing
tells the agent to show it but the `wish-links` skill. Each app tells Lamp's room how its link stands when that changes
(`status`: its state and the apps it reaches straight), which the relay keeps for Lamp alone (`Member.link`, in
`onRoomChanged`) and never passes to the others. Lamp
keeps what came only until the next poll (an app that falls 256 behind has its link ended, since a sealed message can't be
skipped) and lets the socket go when the app has stopped polling. A room is opened the
first time an app of the wish asks, told the wish's apps again when they change (`WishRooms.sync`, from
`Store.syncLocalNetwork`), and ended when the wish is gone, has no other app, or has had nobody in it and nobody asking for
fifteen minutes, so the relay process runs only while a game or a room needs it (`ControllerRelay` keeps rooms beside
sessions, and starts the relay for either). Where a wish's apps are is asked of `Store.apps(of:)` and `Store.wish(of:)`
alone, and a wish is alone when it has fewer than two apps, so nothing in the hub knows which app is at the root. The relay says who is in each room on its output as that changes
(`ControllerRelay.presence`), and the builder is told, at the end of each request for a wish of more than one app, where
each of its apps is: open or not, in the room or not and as what device, which apps it reaches straight and whether Local
Network is turned off for it (as it told the room), and which are still to be made (`WishNote`, sent
like `DeviceNote`). How a wish's apps share data is the agent's choice with the person, not a rule: what every app of such
a wish gets (`Rules.wishTalk`, in the wish's prompt through `Parts.rule` and in each part's rules) is a short pointer to the
`wish-links` skill, which is also named with each request for such a wish (`Skills.applying`) and holds the ways: `LampWish`
as the default, built in, how to use it well, what to do while an app of the wish isn't made yet (write the sharing with
`LampWish` now, never stand in for the missing app with an online service), and when another way fits (one the person asks
for, Tailscale, ntfy, their own server, or iCloud and a chosen service for apps that must reach each other away from home).
It says nothing about who should talk to whom. A stranger on the
network can reach none of it: `/app/wish` and the proxy routes take an app's own token, the relay and every app's own
listener (below) take a proof only the wish's key makes, and Lamp's routes and relay run only while Lamp does. What one app
of a wish says is readable by the wish's other apps and by Lamp's relay, which holds the key Lamp made and opens and seals
again what it passes on, and by nothing else: on the network it's sealed, each link with keys of its own. A device app made
through an integration has no `LampWish` yet.

Lamp's room is one way between a wish's apps; the other is straight between them (**direct links**), so they go on
talking with Lamp closed, the Mac asleep or Lamp updating, as long as they're on the same network. A Mac, iPhone or Android
app listens (an `NWListener` speaking WebSocket in LampSupport.swift; a `ServerSocket` and just enough of WebSocket,
`LampWish.Ws`, in LampSupport.kt) at the wish's port for it: 20000 plus a block of eight the wish's key picks
(`lamp-wish port`), plus the app's place in the wish's sorted list of apps, so a TV page, which can't listen or look names
up, knows where to try; any port when another program has that one. It's found by Bonjour (`_lampwish._tcp`,
`Template.wishServiceType`, which an iPhone app's Info.plist names in `NSBonjourServices`) or NSD under a name only the key
makes (`lamp-wish service` of its peer name), which says nothing of the wish or the app to anyone else, and at the
addresses it tells Lamp's room it listens at (`at`, sealed like any message; the relay passes each member's on, eight short
ones at most, in `welcome`, `joined` and `at`). Each app keeps on its device, by the wish's tag, who it is, the wish's apps
and where each was reached (UserDefaults, a file in the Android app's storage, localStorage on a TV), so it finds the
others without Lamp. A Mac app says this Mac's loopback first, for an iPhone app in the simulator, which shares the Mac's
network. Each app dials the others at the last address it reached them at, what it was told and what Bonjour or NSD found;
a TV page, which only dials, then sweeps its own network (its address from Tizen's or webOS's system calls, else the /24s
of the addresses it was told) at that app's port, 32 at a time, at most once a minute and only for an app Lamp's room
doesn't have either. Tries come again less often each time (2 to 30 seconds, with jitter), and at once when the app comes
to the front, the network changes or Bonjour or NSD finds the other again. A link's handshake is the room's
(`WishChannel`'s steps), the app that listens taking the relay's side and naming itself, so only an app holding the wish's
key answers and only the one it was dialled as; a listener lets in only a hello naming an app of the wish, eight unproven
at a time, eight seconds each to prove. Two apps that both listen and dial each other keep the link the one with the
earlier name dialled, so both sides agree without saying. A message goes the straight way when there is one, else through
the room; another app is open when either way says so, and this one is away (`State.away`, "Can't reach the wish's other
apps…") only when neither way reaches anyone. An app reaches the others only while it runs: an iPhone app in the
background doesn't, and an Android app only while its activity is open. `WishDirectTests` runs two Swift apps through
Lamp's relay going away and opening again without it, and a TV page finding a Mac app by its port with no Lamp. A TV's own
address on Tizen and webOS is untried on real TVs.

A wish of one app, which
is most wishes and every starter, gets none of it: `LampWish` is written into an app's building blocks only when its wish
has or asks for other apps (`Template.talksToOtherApps`: its parts, or its list of apps, `LampProject.apps`, counting apps
and not devices, so one app for the Mac and the iPhone is one). The first app of a wish meant to be several has it from its
first build, while the others wait for this Mac to be able to build them: the wish's key, a room that lists the apps still
to be made as not open (`WishRooms.described`, `Parts.waiting`), the pointer in its prompt and the skill with its requests,
so it's written to talk to them from the start. An app on its own's LampSupport.swift, LampSupport.kt and lamp.js are what they would be
without the hub, the channel's crypto and the direct links included (no listener, no Bonjour or NSD, so no Local Network
question), its prompt has no rule and its requests no line about the hub, no key is made for it and none goes in its install
(`Store.wishKey(for:)` is nil), its iPhone Info.plist names no Bonjour type, no room is opened for it and so nothing starts
the relay, and `BuildStamp` leaves the block out, so no app is built again for code it doesn't carry (`WishHubStaysOutTests`).

A wish's iPhone or Mac app that steers its TV app's game (buttons, sticks, files to the TV) still does so as a player of
`Lamp.controllers`, with `LampController` in LampSupport, beside `LampWish` for everything else. An iPhone part
listens for the TV page itself (an `NWListener` speaking WebSocket, on the phone or in the simulator) and tells Lamp
where (`/app/controller` with `as: listener`, its own token, every 20 seconds); Lamp keeps where it is and gives it a key
of its own for that listener (`PhoneControllers.register`), and the TV page's answer lists it with a ticket signed with
that key (`PhoneControllers.ticket`: for that listener, for two minutes), so the page opens its socket straight to the
phone and Lamp carries nothing. A phone in the simulator registers from the loopback address: the preview reaches it
there, and a TV on the network at this Mac's address on that network. The phone lets in one page at a time, the
preview's before a TV's, and says who it is (a device id it keeps), so lamp.js gives it its number back when it returns.
A Mac part, and an iPhone part that can't listen, joins at the relay as a player instead, with a link's credential
(`as: player`), which Lamp gives only to a part of the same wish while the TV app is open. A TV app with a part takes
players without a page in `Phone/` (`Store.takesPlayers`), and its site is served while it runs.

