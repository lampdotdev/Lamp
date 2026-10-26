# Wishes of more than one app

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

A wish can be more than one app made to work together: a TV app with an iPhone app that controls it, a Mac app with an
Android app (`Parts`). The wish is its own thing, apart from its apps: its name, chat, versions and icon are the wish's,
and which apps it should have is its list (`LampProject.apps`, `WishApp`, in its meta.json; below). No app of a wish is
its main one: any of them, the first included, is added, replaced or taken away on the person's word, and the wish keeps
its name, chat and history. A wish's first app is made in the wish's own folder, as every wish made so far has it, until
it's taken away or replaced; each other app is an app of its own kind in a folder of the wish's
(`iPhone/`, `Mac/`, `Apple/`, `TV/`, `Android/`), with its own `.lamp/meta.json`, build files, bundle id and runtime folder, so it's built,
opened, looked at and used as any app of its kind is. A wish whose folder holds no app of its own (its apps all in
folders, `LampProject.holdsApp` false, read off its files each time so an Undo that brings the first app back has it
again) is only the wish: it's no draft (`scaffolded`), and nothing builds, installs, opens or writes Lamp's own
files for it (`Template.writeOwnedFiles`, `fill`, `writeSupport`, `Runtime.sourcesChanged`, `buildNow`, `installNow`,
`run`), so nothing puts an app back in its folder. Quitting it (`quit`) finds only a copy of the app it held by that
app's own id (`macCopies`, never by the install place its name shares with a Mac app of the wish), so a restore past
that app quits it as any app is quit. A wish's apps are installed under its name, and where each is installed follows from that
name and its kind alone, with nothing kept beside it (`LampProject.installedURL`): a game or a screen goes in a folder
of its kind's in the apps folder (`Target.installFolder`: Games/, Screens/), every other kind in the apps folder
itself. Wishes' names are unique and a wish has one app of each kind, so no two apps share a place, and a copy of the
wish, a restore, or its other apps coming and going never move one. A game or a screen installed before those folders
is moved into its kind's once, by its own bundle id (`Store.reload`). A rename moves every app's installed copy
(`Store.giveName`); Play, Open and Use open its apps (`openWish`),
the desk captions it with where they are (`WishPlace.of`), and `Store.everyApp` is every app without it. Moving existing
first apps into folders of their own, and a shared file's layout for such a wish, are a later change: until then a file
carries one app in the file's root (`Sharing.export`), and opening it makes a new wish rather than an update. A Lamp from
before such wishes would read one as an empty draft and write a new app into it, so its meta.json says `layout` 2 while
its own folder holds no app (`Template.layout`, written with every save of it and set right whenever it's read), which
such a Lamp leaves alone and shows as made by a newer Lamp (`NewerWish`); once an app is back in its folder it says none. An app in a folder of its own is a `LampProject` in `Store.projects` with `partOf` set (id: the
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
(build.sh, the Info.plist lines) carry the name and what the wish's list makes of each app's building blocks, so a
rename and every restore write them for every app of the wish, under the name the version gives, before the version is
saved (`Versions.restoreFiles(name:)`): written after, the next build left the app unsaved and Undo could never get past
it. A part's quit is judged by its
wish's turn, which is the only one it has. Deleting a wish closes each part first (a Mac part may be kept open
over unsaved work, which stops the delete) and forgets what Lamp keeps for it (`Store.forget`: its installed copy,
build folders, sign-ins and place in the lists), as taking a part away does; the list of apps is set in one go with the parts (`Store.reload`), since a moment without them ends a TV app's
game. A part never has a turn of its own: Lamp's own requests for it (carrying on after its Reload, fixing its crash) are
its wish's (`Store.requestOwner`), and so is everything a part's Reload goes by (whose turn has the app, whether the
person stopped or was asked, what's pressed for them while they're away): the Reload in the wish's chat is for whichever of
its apps waits. No app of a wish comes first in what a turn and the wish's history do to it. At a turn's end each app the
agent changed is built, its errors sent back to the agent with its name and folder, before the version is saved, then
opened, each as itself (`Store.settle`). An app whose change went into the open app counts as built there
(`Runtime.needsBuild`): its whole build, which writes what it was built from, runs on after the turn. Each keeps its own look and crash on launch in the turn
(`Turn.Look.installed`, `crashes`, `LaunchWatch.app`), and a crash is fixed as that app's (`Store.crashRequest`). A part
is worked on under the wish's turn (`Store.asPartOf`, and a part's look through `underTurn`, each leaving the hold as it
found it). Undo and every restore rebuild each part whose files changed, and a copy builds every app, each under a hold of
its own so its crash is fixed through the wish (`Store.rebuildParts`); a rename puts the new name in every app's code and
APP.md. Each app's own menu (Open, Rebuild & Open) is still for that app alone. A copy is found by its install place only
for an app with a Mac copy there, since a TV wish's Mac app is installed under the wish's name. Which kinds a list
of devices makes is `Parts.kinds`: the devices of one part family are one kind between them (Apple's), in `Targets.all`'s
order. No kind leads: what a wish does with the list is `Parts.plan`, below. A wish keeps
its first app in its own folder until it's taken away, and a new wish's first app is the first of its kinds this Mac can
build now (`Store.firstKind`: a TV app with an iPhone app, on a Mac without Xcode, starts as the TV app with the iPhone app
waiting), else the first; one read as a kind this Mac can't build yet is made a Mac app and still keeps its other apps on
its list, so a missing tool holds back only the app that needs it.
The TV app of a wish takes the wish's other apps as players from the wish's own folder or from TV/ alike (`Store.takesPlayers`,
`controllerSession`, which find the wish's TV app wherever it is). A device whose integration declares its apps still
stands alone. A game and a screen are apps of a wish like any other (Game/, Screen/), each with its places of its own in
its meta.json (`Parts.load` reads them), and on the wish's list until it's made (`WishApp.places`). `make_app_for` sets the
wish's apps as the list keeps them (`Parts.asked(apps:)`, `AppAsked`): one entry per app, its `kind` (what it is) and its
`places` (where it runs beyond its kind's own device: a Mac app's "iphone" makes it the app for both, an iPhone app's
"watch" gives it a watch app, a game's or a screen's are where it's played or shown beside the Mac), so a word is never at
once an app and a place, and a game and a screen of one wish each have their own. An entry is an object so it can say
more of its app later. An app left out is taken away like any other. The naming call answers with its `devices` (the
apps) and `places` by app apart (`{"game": ["iphone"]}`, `Parts.places`, `Parts.asked`). A game's own wish told its conversations to
list places among the devices, and then in a `places` of their own, before, so its prompt is recorded as "app apps"
(`followPromptShape`), and one begun
before is started again. `look_at_app` and `use_app` find an app by its own word or folder before reading "mac" or
"iphone" as wherever an app opens (`Parts.pick`), so beside a game "mac" is the Mac app. The request's device line says
a game's or a screen's places and budget whichever folder it's in (`DeviceNote.brief`).
A game and a screen are peers of the wish like the others, named "game" and "screen": their page has `Lamp.wish` in
its Web/lamp.js (a screen's is the TV app's lamp.js; a game's is the device kit's with the same block after it,
`GameKit.lampJS`), and on the Mac, the iPhone and the iPad the app of Lamp's own around the page is the peer, with
`LampWish` in its LampSupport.swift, which the page mirrors (`LampPageWish` in LampPage.swift, `hosted` in lamp.js):
it listens, is found and keeps the values on the device as every Swift app of a wish does, so it goes on with Lamp
closed. A game on Android is the same: Lamp's Android app around its page carries LampSupport.kt with `LampWish`, and
the Android app's libraries and Lamp's debug manifest with it, and answers the page (`GameAndroid.pageWish`, through
AndroidX WebKit's message listener, which hears only the game's own page in its main frame; `lampWishHost` in
lamp.js). A screen on a TV is a TV page as a TV app is. On the Xbox the page itself is the peer, as a TV's is, but
it's https in Lamp's WebView2 host, which may not open the plain links the wish speaks: the host opens them for it
(C++/WinRT's `MessageWebSocket`) and passes each frame both ways as it is (`ws` web messages, `pipe` in
lamp_web_host.cpp; `opener` in lamp.js, a stand-in with WebSocket's calls, so the room's link and the direct links are
the same code as a TV's), saying as each frame has gone so a file's flow counts what's still to go. The page keeps the
handshake and the seals, so the host never holds the wish's key; only the app's own page may ask, and only for a
`ws://` link to this network (a private or link-local address, or a `.local` name, never the console's loopback;
`may_dial`), at most 64 at once. The page claims the wish's key as a TV page does, through the host's HTTP relay
(`LampAI._exchange`), the claim opened by the install (`DeviceApps.install`), and keeps it and the values in
localStorage. It doesn't listen (a listener on the console would need inbound traffic the console may not let in, and
every other kind of app of a wish listens), so with Lamp closed it reaches the apps that do, at the address it last
reached them at or by its sweep, using the console's own address, which the host gives (`here`). Turning Chromium's
own rules off instead (insecure content allowed, Local Network Access off) was ruled out: it would loosen the page for
everything it loads, not just the wish's links, and the console's web view may not honour those switches. A game's
page in Lamp's own preview has no way to Lamp, and a page over https anywhere else no host, so there `Lamp.wish` stays
`away` with a reason saying it can't reach the others (`stranded`); the agent is told where it works
(`Rules.gameAmongApps`, `Rules.screenAmongApps`). The TV preview of a screen joins the
wish only when the screen is shown there (`Store.wishRoom`), so the agent's look never takes the screen's place.
Every app of a wish, Android's included, has `LampWish` (below) to reach the wish's other apps,
and is pointed to the `wish-links` skill on how they can share data (`Rules.wishTalk`, `Rules.androidPartTalk`). A wish is shared whole (`Sharing.export`, format 10 once it has a part): the app in its own folder (or, for a wish whose apps are all in folders, one whose folder is
the one its kind gets, since the app at a file's root comes out named by its kind, `WishRooms.peer`, and every app of a
wish is of its own family, so only a wish's one app can lack one) as any app travels, and each other app under its folder in the file, as an app of its kind (`Manifest.parts`,
`Package.parts`); the review reads every app's code, each part's files named with its folder first, and the Mac that
opens it makes each part as `make_app_for` does, in the folder the file had it in when that's one for its family, as it's
its name among the wish's apps (`Store.installParts`, `addPart`'s `folder`, `Parts.folder(_:canHold:)`, with the file's
family for an iPhone part); one it
can't build yet is kept on the wish's list with its files beside the wish (`Sharing.keep`, `.lamp/waiting/<family>`,
by the part's family since the file's folder for it may not be this Mac's, unversioned, gone with the wish), which go in
over the scaffold, with the family and folder the file gave them, once the part is made (`addPart`, `Sharing.kept`); while
it waits, the others know it by that folder too (`Parts.folder(waiting:in:)`). An update from a
file replaces each part the file carries, changes one of another kind of the same family in place (`convert`, so it
keeps its folder and data), adds the ones the wish doesn't have, and leaves a part the file lacks as it is; a part whose
files can't be put in place, or kept, fails the update, which puts the whole wish back, its list and kept files included. A Lamp from before opens a wish's file as the app at its root alone, so a file
with a part says 10.

A three.js game travels as its page (`GameFiles`): Web/ without Lamp's runtime beside it (lamp-game.js, lamp.js,
three/), its scripts and pages as code the review reads (as a TV app's page is read, and its Sources/Native.swift as any
app's Swift) and its models, pictures and sounds as data. The Mac that opens it makes a three.js game and writes Lamp's
files around the page (`GameKit.write`); the copy opens on the Mac, wherever the sender had put it. Such a file says 11,
so a Lamp from before asks to be updated rather than looking for Swift and finding none. A game in C++ isn't shared:
Lamp makes no new ones.

## Credit

A wish says where it came from in `credits.json` at its root (`Credits`): `upstream`, other people's work in it (name,
author, an https address, the commit, the licence as an SPDX id or `LicenseRef-`, the licence file's path in the wish),
which the agent writes when it brings such work in (`Agent.Rules.about`, in every kind's prompt and so every engine's),
and `remixOf`, the wishes it was made from, oldest first, which only Lamp adds to: a starter's copy begins it with the
starter, and a shared file carries the wish being shared as its last link (`Sharing.export`; the same wish shared again
stays one link). Credit is only added to: what a wish arrived with (a starter's copy, a file opened) is kept in
`.lamp/credits-arrived.json` and read back with the file (`Credits.load`), so a source the file lost while the wish was
changed is still shown and shared. Lamp keeps only what passes `Credits.checked`, from the agent and from a shared file
alike. It's shown first in the wish's info panel and, for a Mac app, in its About window (Credits.html, written into the
bundle by `Store.stageSigned`). In a shared file it's credits.json at the root, which an older Lamp ignores, so the
file's format isn't raised for it.

Pictures `make_art` paints are marked as made with AI twice: in the PNG itself (IPTC's digital source type
`trainedAlgorithmicMedia` in its XMP, `AIMark`), and in the wish's `generated` list, which the info panel and About
window count ("3 pictures made with AI") while the files are there.

Before a wish leaves the Mac (a shared file now, a published page too), `ShareCheck` decides whether it may: work under
an open licence goes with its licence and credit; under a share-alike one (GPL, LGPL, AGPL, MPL, CC BY-SA, ODbL) it goes
and the remix stays under it, which a shared file satisfies by carrying the code and a published page says
(`ShareCheck.notes`); under its own terms (`LicenseRef-`, an id Lamp doesn't know, non-commercial or no-derivatives) it
goes, credited and named; with no licence it can be used here but the share is refused, naming it. A licence file the
credits name must still be in the wish. And nothing of the person's goes: what's staged is searched for the person's
provider keys, the app's secrets and its token for Lamp's gateway (`ShareCheck.keptSecrets`, the values themselves) and
for anything shaped like a key (a private key, the prefixes services give their keys), and a hit refuses the share,
naming the file. The person's data isn't in the folder (an app keeps it in its container) and the chat's attachments
never ship.

### Publishing a game as a page

A wish whose one app is a game drawn with three.js can be published as a page anyone plays in a browser (`Publish`,
an experiment: Settings → Experimental, Lamp Dev only, since the page carries Lamp's own runtime, which needs a
licence that lets anyone pass it on before every Lamp can publish). Its share menu has Publish as Web Page…, which puts
the Publish card in the chat's place (`PublishCard`, `PublishCards`, `SidebarPublish`). It goes on GitHub Pages under the
person's own account, through GitHub's `gh` and their sign-in there, never through Lamp's servers: the page costs Lamp
nothing however often it's played, and it's the person's under GitHub's terms. Without `gh` the card's one button gets
it; signed out, Sign In to GitHub… runs `gh auth login --web` in Terminal and the card checks again once that's done.
Before anything goes up the card shows what will: the repository (the wish's name, made public; a name the account
already has gets a number), the credit, the licence notes, the AI pictures and the size, all worked out by staging the
page with its checks (`Publish.stage`). What goes up is Web/ as the app plays it with Lamp's credit bar over it ("Based on Slop New York by Mr.doob · Open in
Lamp", settling into a thin line on the bottom edge after a few seconds, wrapping rather than hiding its link on a
narrow screen). Open in Lamp is the wish's Share Link (`Publish.OpenInLamp`), once the person has made one: Publish never sends
the wish's words or picture itself, and a wish with none has Make Share Link… on the card, which opens Share Link's own
card where they see and change what it shows (with none, the bar links Lamp's site). That page is the one that works for
someone without Lamp, whose Download Lamp carries the wish into the welcome, and for someone with it ("Open it with this
wish"), where a file beside the page means nothing to a browser without Lamp. The wish as a shared file goes beside
the page too (a three.js game's as its page, `GameFiles`), offered in the README, and made by
`Sharing.export`, so held to its checks. With them go credits.json with this wish at the end of the
chain, a README with the credits and licences, and `.nojekyll`; the staged page is searched for secrets again. The push
signs in through `gh` for that push alone, Pages is turned on (or rebuilt), and the card waits until GitHub says it built
that very commit (an earlier build's "built" is the page as it was), saying so if it's still building after ten minutes.
A repository is kept as soon as it's made, and a failed try keeps the page staged, so Publish tries again into the same
repository instead of leaving one behind and making another. Where a
wish's page went is kept in Lamp's folder (`Published Pages.json`), so Update Page puts the wish as it is now in its
place.

The wish's list (`apps`) is what it should have, not what it has: the kind of each app, and for one it still waits for,
what stops it (`needs`: this Mac can't build it yet, or its folder couldn't be made), so a quit or a failure between
asking for an app and making it loses nothing. The list is in meta.json, which no version holds, so every version Lamp
saves of a wish carries its kinds (`Lamp-Apps`, `Versions.appsTrailer`), its first one too (`Store.initRepo`: a new wish, an
import, a copy), a request that changed only the list is a
version of its own (an empty one, titled by the request), and Undo or going back to a version gives back the list it had
(`Versions.apps(at:in:)`, in `restoreFiles` before any app's own files are written), each app its files have on it and
one still waiting keeping what stops it, and forgetting a part the version doesn't have leaves that list as it is
(only taking an app away takes it off, `takeAway`); a version from before carries none, and the list is what its files make. What's made is read off the files (`Parts.wanted`, `Parts.waiting`,
which take the app in the wish's own folder and each other found as made whatever the list says, `Parts.made`). The apps a wish waits for are made at
the start of its next turn (`Store.makeWaitingParts`), each tried once rather than at every turn, since the kind's check
opens its setup window: one this Mac can't build yet keeps what stops it and gets the chat's setup line
(`IPhoneSetupLine` with `part`, `LogLine.text` "iphone part"), whose setup, once done, clears it and sends the request
that adds it (`Store.retryWaitingApp`, `Parts.request`); the agent is told what waits at the end of each request
(`Parts.brief`, once per conversation and when it changes) and never makes one itself. The list follows every change:
`make_app_for` writes what it asked for, an app taken away or Undone leaves it (`forget`), and an app
changing kind (`convert`, a restore) takes its place in it, whichever folder it's in. A wish for a device Lamp can't make apps for yet
(`waitsForDevice`) and one given its kinds in a turn begun without any (`decided`, whose engines' conversations are
forgotten when that turn ends, or at Lamp's next start) are kept in the meta.json too.

What the agent knows follows the apps. A wish whose own folder holds an app has that kind's prompt, with one rule naming
every app of the wish when it has several (`Parts.rule`); a wish whose apps are all in folders of their own has the wish's
prompt (`Agent.wishPrompt`: what holds for the wish as a whole, then its one app's rules for its folder, or each of
several apps named with its skill). Each kind an app in a folder can be has its rules as a skill made from the prompts'
own rules (`target-iphone`, `target-mac`, `target-apple`, `target-tv`: `Parts.packs`, the kind's rules without those
about the wish as a whole, written for the folder the app is in, since an iPhone app made for the Mac too stays in
iPhone/), named with the request while the wish has that app (`Skills.applying`, so a compacted conversation is told
again), and given whole in `make_app_for`'s reply when the app is added. So a conversation never carries the rules of a
kind its wish doesn't have. Claude Code and Codex keep the prompt a conversation began with, so once the app in a wish's own folder goes or comes back (a restore), the wish's conversations are forgotten as its next request starts, and it starts one with the prompt that fits, told the chat so far (`Store.followPromptShape`, `.lamp/prompt-for`). `look_at_app` and `use_app` take `part` ("iphone", "tv", "mac"; `Parts.pick`), which may be
left out only when the wish has one app (`Store.target`: no app is the one meant by naming none; `make_art` takes it too, for which app's Assets/ a picture goes in), and run under the
wish's turn (`Store.underTurn`). `make_app_for` takes the whole list and treats every app alike (`Parts.plan`): one whose
family is listed stays, changed by `convert` only inside its family (an iPhone app that's to be for the Mac too); a
family it has no app of is added in its own folder (`Store.addPart`); one left out is taken away, the app in the wish's
own folder as much as any other (`takeAway`, one path for every app: quit as any app is, forgotten by `forget`, and its
files removed, for the app in the wish's own folder its files only, keeping the wish's: `.lamp/` but the app's runtime, the history, icon.json, about.json, Attachments/ and the other apps'
folders). A restore to a version without that app quits and forgets it the same way. Whether another app shares an
installed copy (a wish's Mac apps are installed under its name) is read from the apps the wish has now (`Store.everyApp`),
never from the kind a wish whose first app went still names. So "tv" added to a Mac wish keeps the Mac app's code and adds the TV app in TV/, and "tv" alone replaces the
Mac app with a TV app in TV/. What this Mac can't build yet holds back only that app: the others are made, and it waits
on the list with its setup; an app is never taken away while nothing would be left, so it stays until what replaces it
is made. A wish still to be told what it's for has nothing written, so its first app is the first kind listed this Mac
can build now (`Store.firstKind`), in its own folder, and the rest wait as parts. So a wish read as an Android app and
made as a Mac app while Google's tools were missing gets, once they're set up, the Android app beside its Mac app
(`Target.android.setup.later.request`), not in its place, unless the person asks for that. Play and Stop are for the whole wish: Play opens each of its apps not open yet, each on the device chosen for it, and Stop quits them all, shown while any of them is open (`Store.openWish`, `quitWish`, `isWishOpen`, and the desk's Use the same way). Each app has its own menu in the toolbar, the Try On of the one in the wish's own folder included, with Use or Quit for that app alone and where it opens; a line about where a part opens names the part ("The iPhone app will open on…", `Store.placeName`), since it has its wish's name.

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
phone's size and rate limits (16 KB of JSON a message, `ControllerWire`), and passes files and a game's controls to one
peer (below). The same
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

Beside messages, which are for apps open now, the apps of a wish share **values** (`LampWish.values`, `set`, `onChange`
in Swift and Kotlin; `Lamp.wish.values()`, `set`, `onChange` in lamp.js): a small map of JSON, each value at most 8 KB and
all of them 64 KB, that every app keeps on its device beside what it keeps of the wish (by the wish's tag: UserDefaults, a
file in the Android app's storage, localStorage; in the TV preview a store of the app's own, which a wish's TV app has
too, by a UUID made from its instance, `TVPreview.store(for:)`, removed when the app, its wish or the part goes:
`TVPreview.forget`, in the background since WebKit lets go of a closed page's store a few seconds later; `PreviewStores`
makes WebKit's default store first, since WebKit's calls about stores that aren't open crash a process in which nothing
of WebKit has started yet, as Lamp is when opened again and a wish is deleted before any preview opens:
`PreviewStoresTests` runs it in such a process) and that is the
same in every app once they've met. Each setting carries
when it was made: the clock of the app that made it, a count within that millisecond, and that app's name (`c: [ms, n,
peer]`). An app's clock never goes back past the latest setting it has made or heard of, so what it sets next is later
than anything it knows whatever the device's clock says, and every app orders two settings the same way. A removal is a
setting without a value, kept so that an older setting from an app that was away can't bring it back. When another app
comes (open either way, where it wasn't), each sends it every setting it has, a few at a time within a message's size
(`values`, sealed like a message; through Lamp's room the relay passes it to the one app named and keeps none), and each
takes those later than its own; a setting made while others are open goes to each at once. So a value set while apart
arrives when they meet, and where two apps set one apart, the later wins in both. A value taken from another app is held
to twice a value's limit, since apps measure a little differently, and what the store holds from other apps (names,
values, and removals at 32 bytes each) to the wish's apps times twice the whole, 64 KB: every app sets at most the whole,
so everything they set fits and they agree whatever the order, and an app gone wrong or hostile that floods the others
gets no further. Every name counts its name and its value as JSON or at least 32 bytes, and a removed one 32 bytes for as long as its
removal is kept, the same when an app sets and when it takes from others: so all an app can make, removals included,
fits in what the others take from it, and their removals are never let go. When a flood needs room the oldest removals
kept are let go first; a removal always goes, without
being kept when nothing older can make room, and only a value that doesn't fit beside the others' values is left. A value set before an app
first knew its own name takes the name once it does. Nothing here decides what goes in values or who talks to whom: that's
the agent's, from the `wish-links` skill.

Besides messages and values, a wish's apps send each other **files** (`LampWish.sendFile`, `onFile` in Swift and Kotlin;
`Lamp.wish.sendFile`, `onFile` in lamp.js): up to 64 MB to one app open now, in pieces under the controllers' flow
(`ControllerWire`: 64 KB a piece, never more than 512 KB past what the receiver has acknowledged, two at a time each way
between two apps, a file that stops moving for 20 seconds ended, on either side; each app starts its numbering anywhere,
so a file sent after a relaunch isn't taken for one from before still on its way). A piece is a sealed message whose first byte is 1
where a message's is "{" (`WishChannel.piece`): 1, a peer's name with its length before it (the one it's for, from the
sender to the relay; the one it's from, from the relay; none on a link straight between two apps), the sender's id for
the transfer, and the bytes; what the file is (`file`, with `ch` saying what it's for: nothing for `onFile`, `pad` for a
game's controls, below), its acknowledgements and its end (`file-ack`, `file-refuse`, `file-cancel`) are messages, with
`to` and `from` through the room as `send` has. A file stays on the way it started on, straight or through the room,
and ends when that way goes (through the room, when the other app leaves the room, though it may still be reached
straight), since its pieces and acknowledgements can't change ways halfway; it ends too when the other app closes, and an
app with no `onFile` turns files down. An Android app holds a file coming in at its size from the start, so it never
needs room for two copies of it. The relay passes a file only to a member that speaks 3 or more
(`fileOrPad`), holds it to the size it was announced at and to its window as it does a phone's (`Member.sending`),
seals each piece for the receiver as it hands it to the network rather than when it's queued, so it takes its number in
the order things really go out (`RelayPeer.send(piece:seal:)`), and drops a member's files when it leaves; Lamp's proxy
for an Android app carries sealed pieces as it does messages. lamp.js reads and writes pieces with the controllers' own
file code (`TVTemplate.filesJS`, a copy of its own inside `Lamp.wish`), turning the wish's header into theirs and back.
On a TV every piece goes through lamp.js's own AES-GCM, so a big file is slow there. `WishFilesTests` sends files between
two Swift apps through the room and straight, and between a TV page and a Mac app; `WishRoomTests` holds the relay to
them.

What a wish's apps say to each other is numbered (`wire` in each library: 3 since files and a game's controls, 2 brought
values; an app from before says none,
which counts as 1). Each says its number in its join, to the relay and on a direct link, and the relay passes each
member's on (`welcome`, `joined`). An open app whose number differs is **out of date** (`outOfDate`), still open, so
messages still go, with a reason: "The TV app is out of date. Open it from Lamp on your Mac to update it.", or, for one
newer than this one, "This app is older than the TV app. Open it from Lamp on your Mac to update it."; values go only to
an app that speaks 2 or more, files and a game's controls only to one that speaks 3. The builder's note says when an app in the room was built by an earlier Lamp
(`WishRooms.wire`). Opening such an app from Lamp builds it again: a Mac or iPhone app of several is stamped with a
fingerprint of the block (`LampWishVersion`, `BuildStamp.isOutdated(for:)`), an Android one is compared by its
LampSupport.kt (`Template.androidWishOutdated`), and a TV app is put on its TV afresh whenever it's opened. Raise `wire`
in all three libraries and `WishRooms.wire` together whenever what they say changes in a way an older app would misread.

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
the relay, and `BuildStamp` leaves the block out and stamps no fingerprint of it, so no app is built again for code it
doesn't carry (`WishHubStaysOutTests`).

A wish's iPhone or Mac app that steers its TV app's game (buttons, sticks, files to the TV) can do so as a player of
`Lamp.controllers`, with `LampController` in LampSupport, which rides on `LampWish`; the prompt offers it beside plain
`LampWish` messages and the agent picks what fits (`Rules.partTalk`). It finds the wish's TV app in the
wish's list (the app whose kind is "tv"), and what it says goes as **`pad`** messages, the straight way when there is
one, else through Lamp's room (`{"t":"pad","m":…}`, with `to` and `from` through the room; the relay passes one to a
member that speaks 3, at a phone's rate to each player apart (an app, and which of its controllers), since a TV app
speaks to each of its players every frame,
and never drops a button let go for a TV that's behind). Each `LampController` has an id of its own (`pad`, on
everything it says and is told), so it is a player of its own: two in one app are two players, and one made again
while the old one's `leave` is still on its way gets in all the same; a `join` asked again is answered again. One closed
or let go after asking to play, welcomed or not yet, says `leave`, so the TV app keeps no player for it. The controller asks to play (`join`, with
its clock, for telling late movement) whenever the TV app is open and speaks 3; lamp.js's `Lamp.wish` answers only while
the page's `Lamp.controllers` takes players (`welcome`, then `player` with its number), and tells every open app when
it starts (`host`) and stops (`state` with `host: false`). Buttons, sticks, messages and `too-big` go as a phone's do;
files go as the wish's files with `ch: "pad:<id>"`, to `LampController.onFile` and `Lamp.controllers.onFile`, never the
app's own `onFile`. A controller let go or closed says `leave`; an app that closes leaves the game. `Lamp.controllers`
takes such players through a hook any way of reaching players can use (`_attach(source)`: `source.start(hooks)` as the
game starts, `stop()` as it ends), which only `Lamp.wish` uses, so a TV app on its own carries nothing of the wish in
it. So the game goes on with Lamp closed, and Lamp hands out nothing for it: an app of a wish built by an earlier Lamp
that asks `/app/controller` is told to be opened from Lamp. Phones' pages in a browser still join through the relay
(`PhoneControllers`, under "TV apps"). A TV app with a part takes players without a page in `Phone/`
(`Store.takesPlayers`), and its site is served while it runs. `LampController`, with `LampTransfer` and `LampFile`, is
in the wish's block of LampSupport.swift, so an app on its own carries none of it. `WishFilesTests` has a Mac app play a
TV page's game with no Lamp at all.

