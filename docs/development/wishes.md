# Wishes of more than one app

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

A wish can be more than one app made to work together: a TV app with an iPhone app that controls it, a Mac app with an
Android app (`Parts`). The wish is its own thing, apart from its apps: its name, chat, versions and icon are the wish's,
and which apps it should have is its list (`LampProject.apps`, `WishApp`, in its meta.json; below). No app of a wish is
its main one: any of them, the first included, is added, replaced or taken away on the person's word, and the wish keeps
its name, chat and history. A wish's first app is made in the wish's own folder, as every wish made so far has it, until
it's taken away or replaced; each other app is an app of its own kind in a folder of the wish's
(`iPhone/`, `Mac/`, `Apple/`, `TV/`, `Android/`, a device's app in its device's: `Roku/`), with its own `.lamp/meta.json`, build files, bundle id and runtime folder, so it's built,
opened, looked at and used as any app of its kind is. The folder is the app: its id, instance, name among the wish's
apps (`WishRooms.peer`), bundle and data ids, installed copy and skill all come from it, so Lamp finds, addresses and
changes each app of a wish by its folder, whatever it's called and however many of a kind a wish's files hold (two
Mac apps in `Mac/` and `Mac2/` included); the app in the wish's own folder, from before, is the one exception, and keeps the ids it has. A new app's
folder is found before anything can stop it being made (`Parts.newFolder`: its kind's or device's name, else `Mac2`,
`Mac3`…), letters and digits only, never one that's there already whatever's in it, that differs only in case from
one, that's kept for an app still to be made (`WishApp.folder`), or that an app was taken away from
(`RemovedApp`), even for an app of the same kind: that folder's id and data stay the app's that left, so Undo
brings it back into its own. Which app `make_app_for` is about is read before anything is written (`AppPlanner.decide`,
the one place every caller decides it): a wish with no app, made or still to be made, gets its first; `app` names one
to change by its folder exactly ("." for the app in the wish's own folder; `AppPlanner.select`), and nothing else (no
kind, device or code) picks an existing app; `another` asks for one more beside them. A wish with an app never gets
another by default: a call with neither is refused, as is one with both, a blank `app` or one that names no app, so a
change of mind changes the app the wish has. Whether a request is for one more app or a change to the one the wish
has is the person's to say: the agent asks them with its own `ask` before adding one (the `more-apps` skill,
which every kind of app is offered, with a line in every engine's prompt pointing to it). A call with `another` adds the
app in a folder of its own, only of a code the wish has none of, made or still to be made: two apps of one code (two Mac
apps) can't be added to one wish yet, since sharing a wish (`Sharing.open` keeps only Lamp's own part folders) and a
request's repeated call couldn't tell them apart, and a device's own app is one per wish. Such a call is refused in
`AppPlanner.make`, before any folder is found or anything written, so the same call repeated is refused too. An app Lamp makes later from the wish's list
(`makeWaitingParts`) reuses the folder kept for it and isn't asked about again. `part` in `look_at_app` and `use_app` names an app by its folder before anything else (`Parts.picks`), and
a word that fits several ("mac" beside two Mac apps) is asked about, each app then offered by a word that reaches it
alone (`Parts.address`). A wish whose folder holds no app of its own (its apps all in
folders, `LampProject.holdsApp` false, read off its files each time so an Undo that brings the first app back has it
again) is only the wish: it's no draft (`scaffolded`), and nothing builds, installs, opens or writes Lamp's own
files for it (`Template.writeOwnedFiles`, `fill`, `writeSupport`, `Runtime.sourcesChanged`, `buildNow`, `installNow`,
`run`), so nothing puts an app back in its folder. Quitting it (`quit`) finds only a copy of the app it held by that
app's own id (`macCopies`, never by the install place its name shares with a Mac app of the wish), so a restore past
that app quits it as any app is quit. A wish's apps are installed under its name, and where each is installed follows from that
name, its kind and its folder alone, with nothing kept beside it (`LampProject.installedURL`): a game or a screen goes in a folder
of its kind's in the apps folder (`Target.installFolder`: Games/, Screens/), every other kind in the apps folder
itself, and an app in a folder none of Lamp's kinds has always made apps in has the folder in its name ("Tally
Mac2.app"). Wishes' names are unique, an app in one of Lamp's own folders is one of its kind's family there (a new
app is never given its family's own folder while the app in the wish's own folder is, or was, of that family), and
folders are unique, so no two apps share a place, and a copy of the wish, a restore, or its other apps coming and
going never move one. A game or a screen installed before those folders
is moved into its kind's once, by its own bundle id (`Store.reload`). A rename moves every app's installed copy
(`Store.giveName`); Play, Open and Use open its apps (`openWish`),
the desk captions it with where they are (`WishPlace.of`), and `Store.everyApp` is every app without it. Moving existing
first apps into folders of their own, and a shared file's layout for such a wish, are a later change: until then a file
carries one app in the file's root (`Sharing.export`), and opening it makes a new wish rather than an update. A Lamp from
before such wishes would read one as an empty draft and write a new app into it, so its meta.json says `layout` 2 while
its own folder holds no app (`Template.layout`, written with every save of it and set right whenever it's read), which
such a Lamp leaves alone and shows as made by a newer Lamp (`NewerWish`); once an app is back in its folder it says none.
A wish with an app that a Lamp of layout 2 wouldn't find as it is (two of one code, or one in a folder of another
name than its kind's: `Parts.readByEarlierLamp`) says `layout` 3 whatever its own folder holds, so that Lamp leaves it
alone rather than lose the app or write over it. An app in a folder of its own is a `LampProject` in `Store.projects` with `partOf` set (id: the
wish's, a dot, the folder), never on the desk (`Store.wishes`), with no chat or versions of its own: what's logged
for it goes to its wish's chat (`Store.log`), and the wish's history keeps its folder. No app of a wish comes first
beyond that: each carries the wish's icon. Its design and artwork are the wish's (`Icons.home`), drawn into each app's
own `.lamp/` (its build and finishing run in its sandbox, which opens only its folder), and new artwork or a new design
reaches every app of the wish (`Store.iconToParts`). Its `realDir` takes the wish's folder by name too, since the agent can put a link in its place, and it's
told where its folder is when it's installed (`folder` in `Template.installValues`, read by `LampInstall.app`), since its
id is no folder's name. A wish's parts are found from its files (`Parts.folders`: every folder directly in the wish's,
by any name, holding the scaffold of a kind that can be one of a wish's apps, read off its own files, never through a
link and never one of the source folders of the app in the wish's own folder),
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
for an app with a Mac copy there, since a TV wish's Mac app is installed under the wish's name. No app leads. A wish keeps
its first app in its own folder until it's taken away; what this Mac can't build yet waits on the wish's list with its
setup, so a missing tool holds back only the app that needs it. A waiting app is kept whole on the list (`WishApp`: its
kind, the devices as they were named, its places and integration, `AppTarget.waiting`): a failure changes only what
stops it (`WishApp.needing`), and a retry or the next turn makes what the list keeps (`AppKinds.member(waiting:)`),
never what its kind alone would be, by the path an app made at once takes (`Store.add`), so what it says to do (a watch
app, a game's places, its rules) goes with the requests until one carrying it has reached the agent (`Parts.madeNote`, kept in `.lamp/made-notes.json` and cleared by `Store.told`, as the note about going back is), so a turn whose engine never started leaves it for the next. Each note is kept with its app as it was made (`Parts.Made.App`: who it is and what it was made for, its kind, places and integration, never where Try On opens it) and sent only while that app is one of the wish's: a version restored without it, or an app made for something else since, drops it, a Try On choice keeps it, and a `make_app_for` on the app replaces it with what that says. A request that reaches the agent counts as telling only the notes it carried.
The TV app of a wish takes the wish's other apps as players from the wish's own folder or from TV/ alike (`Store.takesPlayers`,
`controllerSession`, which find the wish's TV app wherever it is). A device's app made through its integration (a Roku
channel) is one of a wish's apps like any other (family "device", one per wish), in a folder named for its device
(`DeviceApps.folder(for:)`: the integration's name in letters and digits, Roku/, which `Part.folderFor` gives a new
one), found by its folder's marker whatever the folder is called (`Part.marked`, `DeviceApps.markedFolders`), so an
integration renamed since never loses its app, read as that integration's from the marker (`Parts.load`), and kept on
the wish's list with its integration (`WishApp.integration`, and in versions as "device:roku" in `Lamp-Apps`), so one
that waits, or comes back with a restore, is made for the right device (`addPart`'s `integration`). Its rules as a part are `Agent.devicePrompt(part:)` (the integration's
rules for the files in its folder), its word in `look_at_app` and `use_app` is its folder's ("roku", `Parts.word(of:)`),
and the chat names it by its device ("the Roku app", `Parts.name(of:)`, `Parts.menu(of:)`). Another device's app is never made out of
it (its code is its integration's, `AppKinds.code`), and `make_app_for` refuses a second device's app while the wish has
one: the agent takes the old one away with `remove_app`, which takes only its own entry off the list (`Parts.lists`),
and asks for the new one, which gets its own device's folder; each folder is found by its mark meanwhile. It isn't shared yet (its kind's `shareRefusal`), so a wish with one isn't either. A game and a screen are apps of a wish like any other (Game/, Screen/), each with its places of its own in
its meta.json (`Parts.load` reads them), and on the wish's list until it's made (`WishApp.places`). `make_app_for` and `remove_app` are plans
(`Places/AppPlan.swift`): the request is typed (`DeviceWord`: the word as asked, "ipad", its row, "iphone", and the
family that word names in its row's `wordFamilies`; the first device asked for that names a family is where Try On
opens the app, and a request naming none leaves that as it is), checked
against the table and the wish's apps (`WishMember`: each made one with its id and folder, and each still waiting, with
what it is: `AppTarget`, its kind, devices, integration, Try On family and places, and `code`, the key of what it's
written in), planned (`AppPlanner`: `AppPlan.add`, `.update`, `.remove` or `.cancel`) and carried out as planned by
`Store.agentKind` and `agentRemove`. `make_app_for` gives one app, the `devices` it's to be on and whether it's `made` "web"
or "native": it updates the wish's app of the same code (changed in place by `convert`, its code and data kept) or adds
one beside the others, and never takes an app away. A device's own app is a code of its own per integration, one of the wish's apps beside the others, one per wish
for now. `remove_app` finds an app by its folder or own word, then by any device it's on through the table (unique,
several or none, each said as such), takes a made one away reversibly, takes one still waiting off the list, and never
takes the wish's only made app. Today's kinds are read in these terms in one place, `AppKinds`, which holds only the
translation from rows to today's recipes: a native app is the kind of its rows' one `native.code` (Apple's a Mac app,
an iPhone app or one for both by where its rows open), built with any row it comes with (`Place.comesWith`: the watch
with the iPhone); until Lamp has one host for every page, a web app is the kind of page whose places reach every row,
the wish's own when it has one that does, else the one that reaches the fewest other places, and a device's own app on
one integration's device alone; what no kind reaches is refused, saying why. Which device is which, which family a
word means and which code a row is are the table's alone, so a row added to it needs nothing in `AppKinds`. A game's own wish told its conversations to
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
its name among the wish's apps while that folder is free (`Store.installParts`, `addPart`'s `given`, with the file's
family for an iPhone part), and an update goes into the app in that folder; one it
can't build yet is kept on the wish's list, in the folder kept for it, with its files beside the wish (`Sharing.keep`,
`.lamp/waiting/<family>`, or `<family>-<folder>` for one in a folder other than its kind's own, so two apps of one
family waiting keep their files apart; unversioned, gone with the wish), which go in
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
author, an https address, the commit, the license as an SPDX id or `LicenseRef-`, the license file's path in the wish),
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
an open license goes with its license and credit; under a share-alike one (GPL, LGPL, AGPL, MPL, CC BY-SA, ODbL) it goes
and the remix stays under it, which a shared file satisfies by carrying the code and a published page says
(`ShareCheck.notes`); under its own terms (`LicenseRef-`, an id Lamp doesn't know, non-commercial or no-derivatives) it
goes, credited and named; with no license it can be used here but the share is refused, naming it. A license file the
credits name must still be in the wish. And nothing of the person's goes: what's staged is searched for the person's
provider keys, the app's secrets and its token for Lamp's gateway (`ShareCheck.keptSecrets`, the values themselves) and
for anything shaped like a key (a private key, the prefixes services give their keys), and a hit refuses the share,
naming the file. The person's data isn't in the folder (an app keeps it in its container) and the chat's attachments
never ship.

### Publishing a game as a page

A wish whose one app is a game drawn with three.js can be published as a page anyone plays in a browser (`Publish`,
an experiment: Settings → Experimental, Lamp Dev only, since the page carries Lamp's own runtime, which needs a
license that lets anyone pass it on before every Lamp can publish). Its share menu has Publish as Web Page…, which puts
the Publish card in the chat's place (`PublishCard`, `PublishCards`, `SidebarPublish`). It goes on GitHub Pages under the
person's own account, through GitHub's `gh` and their sign-in there, never through Lamp's servers: the page costs Lamp
nothing however often it's played, and it's the person's under GitHub's terms. Without `gh` the card's one button gets
it; signed out, Sign In to GitHub… runs `gh auth login --web` in Terminal and the card checks again once that's done.
Before anything goes up the card shows what will: the repository (the wish's name, made public; a name the account
already has gets a number), the credit, the license notes, the AI pictures and the size, all worked out by staging the
page with its checks (`Publish.stage`). What goes up is Web/ as the app plays it with Lamp's credit bar over it ("Based on Slop New York by Mr.doob · Open in
Lamp", settling into a thin line on the bottom edge after a few seconds, wrapping rather than hiding its link on a
narrow screen). Open in Lamp is the wish's Share Link (`Publish.OpenInLamp`), once the person has made one: Publish never sends
the wish's words or picture itself, and a wish with none has Make Share Link… on the card, which opens Share Link's own
card where they see and change what it shows, and can tick Include the wish itself so the link's page offers this
exact wish to anyone with Lamp (site/SHARED_WISHES.md) (with none, the bar links Lamp's site). That page is the one that works for
someone without Lamp, whose Download Lamp carries the wish into the welcome, and for someone with it ("Open it with this
wish"), where a file beside the page means nothing to a browser without Lamp. The wish as a shared file goes beside
the page too (a three.js game's as its page, `GameFiles`), offered in the README, and made by
`Sharing.export`, so held to its checks. With them go credits.json with this wish at the end of the
chain, a README with the credits and licenses, and `.nojekyll`; the staged page is searched for secrets again. The push
signs in through `gh` for that push alone, Pages is turned on (or rebuilt), and the card waits until GitHub says it built
that very commit (an earlier build's "built" is the page as it was), saying so if it's still building after ten minutes.
A repository is kept as soon as it's made, and a failed try keeps the page staged, so Publish tries again into the same
repository instead of leaving one behind and making another. Where a
wish's page went is kept in Lamp's folder (`Published Pages.json`), so Update Page puts the wish as it is now in its
place.

The wish's list (`apps`) is what it should have, not what it has: the kind of each app, and for one it still waits for,
what stops it (`needs`: this Mac can't build it yet, or its folder couldn't be made), so a quit or a failure between
asking for an app and making it loses nothing. The list is in meta.json, which no version holds, so every version Lamp
saves of a wish carries its kinds (`Lamp-Apps`, `Versions.appsTrailer`; an app in a folder other than its kind's own
with its folder, "mac@Mac2", so two apps of one kind come back as two), its first one too (`Store.initRepo`: a new wish, an
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
wish's turn (`Store.underTurn`). `make_app_for` treats every app alike: one of the code asked for is changed by `convert` only inside its code (an
iPhone app that's to be for the Mac too); a code it has no app of is added in its own folder (`Store.addPart`, with the
family and places asked). `remove_app` takes one away, the app in the wish's
own folder as much as any other (`takeAway`, one path for every app: quit as any app is, forgotten by `forget(_, .reversibly)`,
which keeps everything it saved, here and on the person's devices, so Undo or a restore brings it back as it was, and its
files removed, for the app in the wish's own folder its files only, keeping the wish's: `.lamp/` but the app's runtime, the history, icon.json, about.json, Attachments/ and the other apps'
folders). A restore to a version without that app quits and forgets it the same way, reversibly. Only deleting the wish forgets
its apps for good (`forget(_, .forGood)`: their copies on devices, build and signing folders, sign-ins and TV preview
stores), those taken away before included: each app taken away is recorded as it was when it went (`RemovedApp`, in the
wish's `.lamp/removed-apps.json`: its id, instance, folder, kind, family, places and integration), one record per
identity and never dropped, and deleting the wish disposes of its present apps and each recorded identity none of them
is, once each, whether or not an app of the same folder is there now (`RemovedApp.disposals`: a game taken off an Xbox's
wish and made again for the Mac alone still has its Xbox copy taken off). Whether another app shares an
installed copy (a wish's Mac apps are installed under its name) is read from the apps the wish has now (`Store.everyApp`),
never from the kind a wish whose first app went still names. So a TV app asked for in a Mac wish keeps the Mac app's code and adds the TV app in TV/; the Mac app goes only with
`remove_app`. What this Mac can't build yet holds back only that app: the others are made, and it waits
on the list with its setup, and `remove_app` takes it off the list if the person no longer wants it. A wish still to be
told what it's for has nothing written, so the first app its agent gives it goes in its own folder. Play and Stop are for the whole wish: Play opens each of its apps not open yet, each on the device chosen for it, and Stop quits them all, shown while any of them is open (`Store.openWish`, `quitWish`, `isWishOpen`, and the desk's Use the same way). Each app has its own menu in the toolbar, the Try On of the one in the wish's own folder included, with Use or Quit for that app alone and where it opens; a line about where a part opens names the part ("The iPhone app will open on…", `Store.placeName`), since it has its wish's name.

Every new wish is `undecided` until its agent gives it its first app (kept in its meta.json, and through the naming that
follows: `LampProject.named` carries everything a wish is): the naming call names it and lists the devices the request
names, in the table's words (`AppName.Suggestion.devices`), and chooses nothing else. Nothing is written, its prompt has no
kind's rules (`Agent.undecidedPrompt`): the agent decides what it is and where it runs from the request, the table of
devices and the person's own devices, asks with `ask` only when the answer changes what's made, and gives it its first app
with `make_app_for`, whose reply carries the chosen kind's whole prompt. Each engine's conversation began with the
undecided prompt, so it's ended as that turn ends (`Store.decided`), and the next request
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
(`welcome`, with every app the wish has; `joined`, `left`: peer, app, kind, name, the device it said and since when), passes a `send` to one peer, to
every copy of one app or to all as
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
back on a new socket before its old one was noticed gone is said to have left before it's said to join. The app's token is what lets it use those routes; the wish's key is what lets it into the room.

One app of a wish can be open on several devices at once (a screen on the kitchen iPad, on the TV and on an Android
photo frame): each is a **copy** of it, a member of the room and a peer of its own. A copy's peer name is the app's,
a dot and an id its device made the first time the app ran there and keeps with what it keeps of the wish (`copy`
beside `me`: UserDefaults, the Android app's file, localStorage; eight letters and digits; "screen.k3j9x0ab",
`WishChannel.isName`, 32 bytes at most), so the same app opened again on that device is the same copy, and a reconnect
from it still replaces its old socket (code 4000), while a copy on another device sits beside it. The TV preview has a
store of its own, so it's a copy apart from the TV's. Everything that was by peer is by copy: the room's members, a
link straight between two apps, where each was reached (`at`), a file's transfer, a game's player (`LampController`
plays with one copy of the TV app, the one open longest), and the name a value's setting carries (`c: [ms, n, peer]`),
so two copies of one app never tie. What an app is told is still by app: `peers`, `apps` and `peer("screen")` are
apps, each with its `copies` open now (`id`, `device`, `since`), open while any copy is, out of date only when no copy
speaks this one's `wire`; another copy of this app is listed while it's open. A message `to` an app goes to every open
copy of it (the relay passes a `send` or `values` whose `to` has no dot to each member of that app, `Member.isFor`),
`to` a copy's id to that copy alone; `onMessage` and `onFile` say the app (`from`), and which copy sent it as a third
argument (`file.copy` in Swift and Kotlin); a file goes to one copy, the one named or the app's opened last. An app built
before copies (wire 3 or less) joins by its app's name alone, as a copy of that app: the relay and the new libraries
take it so, and it's shown as out of date, but it doesn't know the new copies' names (it sees them as no app of the
wish, so it shows the others as not open and its messages to them don't arrive), so it's rebuilt when opened from Lamp,
as any app of an earlier wire is: `LampWishVersion`, `Template.androidWishOutdated` and a TV app's install on open.
An app with no other app in its wish has copies too (the same app on two iPhones), with a room of its own (below).
`WishNote` gives each copy in the room its own line. Every
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
`Store.syncLocalNetwork`), and ended when the wish is gone, has no app, or has had nobody in it and nobody asking for
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
again what it passes on, and by nothing else: on the network it's sealed, each link with keys of its own.

A device's app made through its integration (a Roku's) doesn't join the room yet (`Part.joinsWish`, `WishRooms.joins`):
it's left out of the room's list (`WishRooms.described`), so the others never wait for it or show it as closed, it isn't
counted among the apps that give an app `LampWish` (`Template.talksToOtherApps`: an iPhone app beside only a Roku app
has none), and the builder's note says it can't reach the others (`WishNote`). Its own building blocks carry
`LampWish.brs` while its wish has other apps (`Template.hasOtherApps`, `DeviceSupport.wishFile`): `LampWish_status()`
always `away` with the reason, the peers empty, and `LampWish_send` and `LampWish_set` sending nothing, the shape the
link will have, and the rules say to keep each app whole without it (`Agent.Rules.deviceAmongApps`, the `wish-links`
skill), with `LampRoku` for steering it from a Mac or iPhone app meanwhile. What the link needs on a Roku: it has no
WebSocket before Roku OS 16 (`roWebSocket`), so it would speak through Lamp's proxy routes as an Android app does
(`/app/wish/open`, `send`, `poll`); HMAC-SHA256 is native (`roHMAC`), but `roEVPCipher`'s GCM is AES-128 only (Roku OS
15.2 and later) where the room seals with AES-256-GCM, so the seal would be AES-256 in ECB (native) for the counter blocks
with GHASH in BrightScript; and the key's claim seals to an X25519 key pair, which BrightScript lacks, so X25519 would be
written in BrightScript (as lamp.js has it in ES5), in a Task node, held to CryptoKit by `WishChannelTests` like the others.
The other way, Lamp holding the seal for the Roku over its token, would leave what the Roku says in clear on the network.

Lamp's room is one way between a wish's apps; the other is straight between them (**direct links**), so they go on
talking with Lamp closed, the Mac asleep or Lamp updating, as long as they're on the same network. A Mac, iPhone or Android
app listens (an `NWListener` speaking WebSocket in LampSupport.swift; a `ServerSocket` and just enough of WebSocket,
`LampWish.Ws`, in LampSupport.kt) at the wish's port for it: 20000 plus a block of eight the wish's key picks
(`lamp-wish port`), plus the app's place in the wish's sorted list of apps, so a TV page, which can't listen or look names
up, knows where to try; any port when another program has that one. Every copy of an app listens at the app's port,
each on its own device, so copies don't collide (two copies on one device, an app for iPhone and Mac open on the Mac and
in the simulator, put the second on any port). It's found by Bonjour (`_lampwish._tcp`,
`Template.wishServiceType`, which an iPhone app's Info.plist names in `NSBonjourServices`) or NSD under a name only the key
makes (`lamp-wish service` of its app's name, then a dash and the copy's id), which says nothing of the wish or the app to
anyone else, and at the
addresses it tells Lamp's room it listens at (`at`, sealed like any message; the relay passes each member's on, eight short
ones at most, in `welcome`, `joined` and `at`). Each app keeps on its device, by the wish's tag, who it is, the wish's apps
and where each was reached (UserDefaults, a file in the Android app's storage, localStorage on a TV), so it finds the
others without Lamp. A Mac app says this Mac's loopback first, for an iPhone app in the simulator, which shares the Mac's
network. Each app dials every copy it knows of (in the room, found by Bonjour or NSD, or reached before) at the last
address it reached it at, what it was told and what Bonjour or NSD found; whichever copy of that app answers there is
taken, as the copy it says it is (an address changes hands). A TV page, which only dials, then sweeps its own network
(its address from Tizen's or webOS's system calls, else the /24s of the addresses it was told) at an app's port, every
address of it, since the app may be open on several devices, 32 at a time, at most once a minute, only for an app no
copy of which it reaches either way, and for its own app only once it has known another copy of it. Tries come again less often each time (2 to 30 seconds, with jitter), and at once when the app comes
to the front, the network changes or Bonjour or NSD finds the other again. A link's handshake is the room's
(`WishChannel`'s steps), the app that listens taking the relay's side and naming itself, so only an app holding the wish's
key answers and only the one it was dialled as; a listener lets in only a hello naming an app of the wish, eight unproven
at a time, eight seconds each to prove. Two apps that both listen and dial each other keep the link the one with the
earlier name dialled, so both sides agree without saying. A message goes the straight way when there is one, else through
the room; another app is open when either way says so, and this one is away (`State.away`, "Can't reach the wish's other
apps…") only when neither way reaches anyone. An app reaches the others only while it runs: an iPhone app in the
background doesn't, and an Android app only while its activity is open. `WishDirectTests` runs two Swift apps through
Lamp's relay going away and opening again without it, a TV page finding a Mac app by its port with no Lamp, and two
copies of one app (a Swift program and a TV page) with a Mac app seeing each other and sharing values with Lamp and
after it's gone, and two copies of an app on its own doing the same. A TV's own
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
arrives when they meet, and where two apps set one apart, the later wins in both. A setting an app takes from
another copy goes on to the copies open now that the one it came from may not reach (those this app reaches straight,
and those in the room when the one it came from isn't there itself, `pass`): two TV pages, which only dial, reach each
other's values through an app that listens when Lamp is closed. A copy that has a setting already takes nothing from it,
so it goes no further; messages and files aren't passed on. A value taken from another app is held
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

Values suit a few small things; what every **copy** of one app shows (a shopping list, chores, a calendar, photos on a
screen open on a Mac, a kitchen iPad, a TV and an Android frame) goes in the app's **shared collections**, built on the
same block and kept the same on every copy of it: `LampStore.shared(name)` (`items`/`all`, `put`, `get`, `delete`,
`publish`, `onChange`; `LampStore.Shared` in Swift, `LampShared` in Kotlin, an object in lamp.js) and
`LampStore.sharedFiles(name)`. A collection is the app's own, never another app's of the wish, unless it's the
**wish's own**: `shared(name, wish: true)` (`wish = true` in Kotlin, `{ wish: true }` in lamp.js; `sharedFiles` the
same) names it `wish:<name>` (`files:wish:<name>` for files), and every app of the wish keeps it the same, so a Mac app
and the iPhone app beside it share one calendar without either keeping it for the other. Everything below holds for it,
except who it goes to: an app's own collections go between its copies that speak 5 and are taken only from them, the
wish's own between every copy of every app of the wish that speaks 6 (`storePeers`, `shares`), each side checking the
name before it sends, answers or takes (`sum` and `ask` say only what both share). The relay passes a `store` message by
its `to` whichever app it's for. Each copy keeps every
item with its setting's time, as a value is kept (`c: [ms, n, peer]`, on the values' clock, a deletion kept a month
without its value), and copies merge item by item, so two copies that changed different items while apart keep both.
What they say is one sealed message, `{"t":"store", op, …}`, through the room with `to` and `from` as `values`
(`Relay.fromMember` passes it only to a member that speaks 5) or straight: `items` (a collection's settings, a few at a
time within 12 KB), `sum` (as copies meet and once a minute, what each sixteenth of each collection adds up to: the
bucket is FNV-1a 32 of the id's UTF-8, low four bits; its number the XOR of FNV-1a 32 of `id\0ms\0n\0peer`; 128 hex
digits a collection), `ask` (the sixteenths that differ where the other has something, answered with their items) and
`file`. So two copies that meet send only what differs, and a setting lost on the way is made up within a minute.
Settings taken from one copy are passed on as values are (`pass`). Limits are sized for real lists: an item 8 KB as
JSON, everything an app sets 1 MB (each id and its value or 32 bytes, deletions included), what it holds from others
twice that times the wish's apps, the oldest deletions let go first, and 32 collections. `publish(items)` is for what one
copy can read and the others can't (a Mac's or an iPad's calendars through `LampNative`): this copy's items become
exactly these, an unchanged one setting nothing and an item another copy set last left alone. A shared file is an item
of the collection `files:<name>` saying its size, type and checksum (SHA-256, the first 16 bytes in hex); its bytes are
kept beside what the app keeps of the wish (Swift: Application Support, by the wish's tag and the copy; Kotlin: beside
the kept file; lamp.js: in memory, so a TV asks again each time it opens), and a copy without them asks one other copy
that has them (`file`: the one that set it first, then each in turn, two at a time of each, again after a minute
without them or when that copy closes), which sends them as a wish's file with `ch: "store:<collection>"`, taken by the
store rather than the app's `onFile` and kept only when the checksum matches. 64 MB a file, 256 MB in all. Swift keeps
the collections in UserDefaults by the wish's tag, Kotlin in a file beside the kept one, lamp.js in localStorage. A page
hosted by an app of Lamp's own (`hosted`) mirrors the app's collections: it asks for one (`shared`), is told it whole and
then as it changes (`items`), and puts, publishes and fetches a file's bytes through the app (`LampPageWish`,
`GameAndroid.pageWish`). `WishSharedStoreTests` has a Swift app and a TV page, copies of one app, each change different
items before they meet, then end with both and with the Swift copy's file on the page.

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

What a wish's apps say to each other is numbered (`wire` in each library: 6 since the wish's own collections, 5 shared collections, 4 brought copies,
3 files and a game's controls, 2 values; an app from before says none,
which counts as 1). Each says its number in its join, to the relay and on a direct link, and the relay passes each
member's on (`welcome`, `joined`). An open app whose number differs is **out of date** (`outOfDate`), still open, so
messages still go, with a reason: "The TV app is out of date. Open it from Lamp on your Mac to update it.", or, for one
newer than this one, "This app is older than the TV app. Open it from Lamp on your Mac to update it."; values go only to
an app that speaks 2 or more, files and a game's controls only to one that speaks 3, shared collections only to one
that speaks 5, and the wish's own only to one that speaks 6 (an older copy keeps its own and catches up once it's rebuilt). The builder's note says when an app in the room was built by an earlier Lamp
(`WishRooms.wire`). Opening such an app from Lamp builds it again: a Mac or iPhone app of several is stamped with a
fingerprint of the block (`LampWishVersion`, `BuildStamp.isOutdated(for:)`), an Android one is compared by its
LampSupport.kt (`Template.androidWishOutdated`), and a TV app is put on its TV afresh whenever it's opened. Raise `wire`
in all three libraries and `WishRooms.wire` together whenever what they say changes in a way an older app would misread.

A wish of one app, which is most wishes and every starter, carries `LampWish` too (`Template.carriesWish`: every app
that holds one), since any app may be open on several devices at once and its copies share values through it: its key,
a room of its own once it asks (`WishRooms.answer` answers `alone` only for a wish with no app), its iPhone Info.plist's
Bonjour type, its install's key, and `BuildStamp`'s fingerprint of the block (a starter's prebuilt copy is stamped with
it too, `BuildStamp.stamp`). Every kind but a device's offers the `wish-links` skill in its prompt's list, which is also
named with the requests of an app whose code uses `LampWish`. What's for a wish of several apps alone still goes by
`Template.talksToOtherApps` (its parts, or its list of apps, `LampProject.apps`, counting apps and not devices, so one
app for the Mac and the iPhone is one): the rule in the prompt (`Rules.wishTalk`), naming the skill with every request,
and the builder's note (`WishNote`). The first app of a wish meant to be several has all of it from its first build,
while the others wait for this Mac to be able to build them: a room that lists the apps still to be made as not open
(`WishRooms.described`, `Parts.waiting`), the pointer in its prompt and the skill with its requests, so it's written to
talk to them from the start. An app with no other app in its wish is `alone` (no reason to show) while no other copy
of it is open, and doesn't look for its copies on the network (no listener, no Bonjour or NSD, so no Local Network
question on a Mac) until Lamp's room has shown it another copy of itself, which it keeps on the device (`copies`
beside `copy`): copies of an app on its own first meet through Lamp, and after that also straight. Only apps that use
`LampWish` ask Lamp for a room at all, since the block starts the first time it's used. `WishHubStaysOutTests` holds
an app on its own to carrying the block without the rule or the note.

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

