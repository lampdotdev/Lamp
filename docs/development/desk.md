# The desk

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

Lamp's window is the desk and only the desk (`WishDesk`, `Desk.swift`): no wish's chat is ever drawn in it. It's drawn
on Lamp's paper (`Paper`, in LampSidebarKit, which the welcome and the chat draw from too): the person's wishes in one
list, the place to make a new one above it, and down the side the person's devices. Everything someone
makes with Lamp is a **wish** in what they read; a wish may be made of an app, a widget, a menu bar item, a watch app,
so "app" stays where it means that piece. A wish is a thing to change as much as to use, and it may run in several
places, so the desk shows none of a Mac's icon grid and makes no difference between a game and an app.

**The list** (`DeskList.swift`) is every wish: those Lamp came with and those the person made, together, with nothing
set apart for the starters (a starter deleted is gone; a remix of it from the site puts it back). Each row is the wish's
icon (narrower than a picture, and easier to find again down a list), its name and its about.json line, who made it, where
it runs (each place its apps open, `openPlaces`), when it last changed, and **Open** with the wish's menu, ⋯, beside it (`DeskListRow`, `DeskWishMore`),
in a narrow window only the icon, the name and the buttons, the rest being in the side panel (`DeskListRow.compact`); all read from its files away from the main thread for each change to the wishes and as each turn ends (`DeskEntry`).
Who made it is "You" for what was made or remixed here, the author of the work a starter is made from (Lamp when it
names none), or "Shared" for a wish that came from someone else (`DeskList.madeBy`). Clicking a column's name sorts by it,
and again the other way, kept between launches; nothing is dragged into an order. A remix made here sits under its
original, whatever the sort, joined to it by the stripes' line (`DeskList.rows`: by the last link of its chain,
`Credits.remixOf`, naming the original's identity). The list has no filters: a remix is found under its original, and
most wishes are changed in place rather than remixed. Open (or a double click) opens it to use and change at once (`Store.open(fromDesk:)`), always with its chat
beside whatever shows it: a Mac app with windows opens with its chat beside it (`Store.change`, below; a notification's
click goes the same way, `Store.openChat`); a wish that opens no Mac window is used (`Store.use`) with its chat in Lamp's
panel, beside the simulator, the emulator or Lamp's preview that shows it, or on its own where nothing on this Mac does
(`ChatPanel`, "The chat's one screen" in the chat guide); one still coming true, or waiting on an answer, opens its
chat. With VoiceOver a row is picked as a click picks it, and opened by its Open action. A right-click has Open and then what ⋯ has
(`DeskWishMenu`): Duplicate…, Duplicate the Original, Start Again from the Original and Send Changes Back… where they apply, Wish Info
(its chat, on its info panel: `SidebarServer.show`), then the wish's own menu (`AppMenu`: Rename…, Delete… and the rest).
Open isn't behind ⋯: the button beside it opens the wish, and an item first under the pointer would take a click meant
for the menu. Dragged out
of Lamp a row is the wish's shared file, or the app itself in the Dock or the Applications folder (`WishDrag`). A dot
beside a name says it's ready. The one wait the list shows is a starter opened before Lamp has built it, since nothing
else on screen says the click did anything until it opens by itself (`openWhenReady`): "Getting it ready…" takes its
line's place, a sheen crossing it so the wait never looks frozen (`DeskStatusLine`), still where the person asked for
less motion. A wish being made or changed shows that in its chat, never on the desk. When a wish is used where nothing
comes forward (the menu bar, a widget, the background, the person's own phone) the desk says so in `WishHUD`, a large
translucent square like macOS's old volume display. Lamp's mark at the start of its chat's bar brings the desk back in
front (⌘[).

**Remixing a wish, which changes it in place, is the first thing the desk offers; a new copy is a choice made on purpose.** The row picked (clicked,
or moved to with the arrows; the first until then) shows beside it what it is, in a panel the toolbar's sidebar button
slides away and back, shown only where the window leaves the list room beside it (`DeskDetail`): its picture
(`Runtime.previewURL`, else the one its starter shipped), line, who made it and its license, where it runs and its
remixes, Open with ⋯, and **Remix it**: a box whose change goes to this wish (`Store.change(_:asking:)`), sent as if typed
in its chat, which opens beside it as Open opens it; with nothing written it only opens. A starter's own three changes
are there to put in the box. The wish changes in place, a version of its own that Undo and Versions take back. A starter
or a wish opened from GitHub or a file is already the person's own copy, so the original is never touched.

A wish that arrived from somewhere and has been changed since (`Store.original(toStartAgain:)`: its files differ from
the last version that arrived, "From Lamp" or what an update brought, Lamp's own files aside) says "Changed from the
original" in the panel, with Start Again beside it, and the same in its chat's Wish Info, under Credits (`AppInfoView.
creditsSection`, read for the chat by `SidebarServer.changedFromOriginal`); the same is Start Again from the Original in
its menu (`Store.startAgain`), which restores that version as a new one, so Undo brings the changes back. For a starter there's
also Duplicate the Original (`Store.duplicateOriginal`): a fresh copy of the starter as this Lamp ships it, put on the
desk as a remix link puts one, beside the changed copy. Send Changes Back… is
in the menu only for such a wish that came from a repository (`Contribute.canContribute`), and opens its card in the
wish's chat as the chat's Share menu does. A remix link from the site lands the same way: it opens the person's own
untouched copy of the starter with the request written into its box (`openCopy`), to be sent in place.

Remix means changing the wish itself, everywhere Lamp says it: the desk, the site's and a README's remix links (which
open the starter itself), and the shuffle mark in every app, which opens its chat. **Duplicate…** (`Store.remix`, in the
wish's menu and File → Duplicate…) is for making something else of it while keeping it as it is. It makes a new copy, "<name> Remix", with its code, history and icon on another background, and a link back
to the original at the end of its chain, then builds it with its chat beside it; the original stays as it was. From the
panel's menu, what's in the box goes as the copy's first request. A remix made with no change asked opens its chat on
the card its starter's chat opens on (the original's starter.md kept as `.lamp/starter-suggestions.md`,
`Starters.suggestions`), never as a starter itself: its icon is painted and the desk counts it as the person's.

**Making a new wish.** It's typed in the bar over the list, or said with the talk button beside it (`TalkButton`, moving
with `Dictation.level`); either way it goes to a new wish's chat and is sent from there (`Store.wish`, `sendWhenShown`), so
it passes the same setup checks as anything typed in a chat. Its chat doesn't pop up out of nowhere: the bar lifts off
the desk and grows into the chat's window, lit in the colors of the smoke an app being changed shows
(`LampTransition.Look.hues`), with a few sparks rising off it, and the chat fades in where it lands (`WishArrival`, drawn in
a window of its own over the desk, so the chat is laid out once, at its real size). Where the person asked for less
motion, or the chat opens on another screen than the bar's, it opens at once. "Not sure?" beside the bar opens a few
ideas (`DeskIdeas`) and Help Me Find One.

**The devices** (`DeskDevices`) are down the side, since a wish for the TV or the phone is what Lamp
is for and Settings is no place to find that out. Until Lamp has looked on the network (`localNetworkAsked`) they're an
invitation to, whose Find My Devices is the look macOS asks about; from then on the desk looks each time it's shown or
Lamp comes to the front, at most once a minute (`lookForDevices`), and the list is this Mac, then the person's own, then
what was only found that Lamp makes apps for or controls, each kind in the order people make most for
(`DeskDevices.ranked`), then "N More" for what Lamp could only learn (a server, an appliance; it opens Settings → Your
Devices, where the whole network is) and Add a Device (`AddDeviceSheet`). A green dot is ready, and a click puts "for my
<device>" in the bar; "Set up" and an amber dot is a step to take, and a click takes it (`DeviceNextStep.takeFurther`,
Settings where Lamp can't from here). A device's name is short and plain (`DeskDevices.label`: a found one by its model,
never an address or a serial); what else is known is in its tip a moment after the pointer comes onto it (`DeviceTip`),
never its address. macOS refusing the network is `LocalNetworkRefused` under the list.

"Help me find one" (`Store.findWish`) is the site's wizard in the app, held in the ordinary chat: a new wish
marked `finding` whose first request is `Agent.findingRequest`. The agent asks about the person's days in
`ask` cards (`Agent.findRules`), never about apps, and ends by writing the wish into the message box with
`write_wish`, word by word as a wish from the site arrives (`Store.writeIn`), for the person to change and
send. Until that message, nothing is named, scaffolded, built or saved (`startQueued`, `turn`): the wish it
becomes may be an iPhone app, which a scaffold already written as a Mac app would rule out. The message that
isn't an answer to a card names it like any first request and ends `finding`.

A new person's desk isn't empty: Lamp comes with fifteen wishes (`Starters`, from `Resources/Starters`), working
apps to use as they are and to change into their own, which shows what Lamp does better than a question about
what to make. So the welcome is the hello and setup, and ends on the desk (a wish from the site is still made
once setup is done). They're copied once, on the first launch, each saved as its first version ("From Lamp"),
and from then on they're the person's: a later Lamp with other starters gives those only to new people. As soon
as Apple's tools are there they're built one by one out of sight (`Store.prepareStarters`), with nothing in
their chats; nothing on the desk shows it; one clicked before its build is done glows, says it's opening, and opens when it's
ready (`openWhenReady`). A
starter opens with its chat beside it the first time (`MagicPanel.startWithChat`, the hand-off a new app gets after
its first build); one that opens no window has its chat opened in Lamp the first time it's used. The chat opens on
Lamp's own card (`Starters.card`, an `ask` marked `offer`): the starter's line and its three changes, each sent as
the first request when clicked, with the message box answering it too. Nothing waits on it (`Talk.waiting`), so the
desk doesn't say it has a question and using it still opens it. Each
folder holds the app's code, APP.md (which the agent reads first, so it knows the app it's changing), icon.json
(its design), the icon drawn from it in icon/ with its artwork, drawn once the way an app's is: layers of glass
(icon/art.json, `GlassIcons`) or, for a game, a painting (icon/art.png). The artwork goes where an app keeps its icon's,
since Lamp draws none for a starter on the person's Mac, which would offer to set up pictures in its chat;
`StarterIconsTests` draws the icons again, with Xcode set up for the Liquid Glass one, and the artwork again with
`LAMP_PAINT_STARTER_ART=1` and a key), so the desk
shows them at once and Lamp draws one again only once its icon.json changes (`Starters.hasShippedIcon`),
preview.png, a picture of its window that the desk's list shows beside its about.json line, 90 characters at most (every
Mac app saves a fresh one at each launch, `LampRuntime.preview`, and Lamp takes one of the simulator for an iPhone
app, both at `Runtime.previewURL`), and starter.md, Lamp's own: the wish's name and what its chat offers to change first, a line and three changes, each
with its tile's symbol (`- drop: Add a water counter`). The three show how far a starter can go, not small tweaks to
it: one changes how it looks (Hot Shelf as a realistic kitchen cabinet), one what it does (ingredients on every tag),
and one what it's about (Hot Shelf as a beer tracker), in that order. Each is something the app doesn't do already,
that the agent can make in one request with no key or account, its look drawn in code rather than pictures. They
are Mac apps (or a game or a screen, when starter.md says `kind: game` or `kind: screen`, made as any wish of that kind
is) that need no key or account, use the AI the person builds with when they use any, and come with
example content they can clear. After changing LampSupport.swift, `scripts/check-starters.sh` type-checks them.

Each starter is made in a public repository in the Lamp team's account (github.com/lampdotdev/<folder>, the
account `Starters.account` names), laid out as Put on GitHub lays a wish out: the app's code and files with Lamp's own
around them (so `./build.sh` builds it there too), an MIT license, a README and, among its pictures (`.github/`), the
drawn icon and the desk's preview. Lamp's repository holds only what names each one: `Resources/Starters/<folder>/
starter.md`, with the starter's line and three changes, where it lives (`repository:`) and the commit this Lamp ships
(`commit:`). The tree at that commit is fetched beside it (`scripts/fetch-starters.sh`, into `tree/`, never
committed) by `build.sh`, CI and anyone running the tests, bundled without its git history, and read as a repository
is opened (`Starters.copy`: `RepoImport.open` and `Sharing.install`, so Lamp's own files in it are never copied, and
the copy names the starter at that commit on its chain, which Update from GitHub… merges against and Send Changes
Back… goes on top of). A copy made before starters named a repository gets the address from the starter this Lamp
ships (`Starters.located`) and is merged against the version it began with ("From Lamp", an arrival like a shared
file's). A starter of a kind Lamp doesn't share yet has none. A starter based on someone else's work (New York,
Home HQ) still credits that work in its credits.json; its repository is Lamp's version.

What a starter's repository shows is the starter's own: the GitHub description is lamp-app.json's line; the README
(`GitHubRepo.readme` with a `Showcase`) opens with the icon and preview from `.github/`, the description, the buttons (Play in your browser for a game, Open
in Lamp, "Generated apps"), and "Ideas to try" titled with starter.md's `offer` and listing its tweaks, each a link
that opens Lamp on a copy with that request. A game whose page is the whole game also gets a page
anyone plays in a browser (`StarterRepos.stagePage`: Publish's page with the credit bar and the tweaks in its Remix
panel, which names the starter so a remix starts from a fresh copy of it, "Remixing a published page" in the
wishes guide, on the repository's `gh-pages` branch for GitHub Pages, at lampdotdev.github.io/<folder>), which the README
links and the repository's website points to; any other starter's website is its remix link on lamp.dev. `scripts/publish-starters.sh` refreshes all of that: it clones each
repository's latest and stages it with the built Lamp Dev (`--stage-starter-repos … --trees`, as a wish is staged,
with an identity derived from the starter and a fixed export time, so an unchanged repository makes no commit),
pushes one commit of what's Lamp's, never the app itself, and moves the pin in starter.md to it, fetching the tree;
`--dry-run` only stages. The pictures it puts up are the repository's, except ones changed in the fetched tree since
its commit (an icon `StarterIconsTests` drew there, a new preview put there), which go over them; a repository it
can't fetch stops it, so nothing older is ever pushed over a repository's latest. Run it after changing Lamp's own files, before the release that ships the change, and commit
the starter.md files it moved.
A starter may be a game: New York is Slop New York's three.js city as a three.js game (its page in `Web/`, its frame
given to Lamp's runtime with `game()`, its own keys and touch controls, Lamp's three.js with its node materials), so
the agent looks at it and plays it in the game preview like any game, and it can be played on an iPhone, an iPad,
Android or the Xbox too. It builds its whole city before the first frame, about half a minute out of sight, which is
why the preview waits up to two minutes and keeps a page in no window running (`WebGamePreview`). Its credits.json
names Slop New York at the commit the starter is on, with its license file, and the map, terrain and city data it uses;
a starter built on someone else's work ships one, and bringing in a newer upstream updates its commit in the same
change. Every starter's copy starts its wish's chain with the starter itself (`Starters.copy`, "Credit" in the wishes
guide).
A starter may be a screen: Home HQ is Wes Bos's photo-frame-dashboard (MIT) as a screen, its page in `Web/` as plain
scripts with no build step, at home on the Mac, and its changes put it where a screen goes (an iPad, a TV, an Android
photo frame). It's shared as any starter is, its page and Native.swift as the file's code (`ScreenFiles`, "Wishes"). Its `Sources/Native.swift` reads the person's calendars and photos only once they turn them on in the
page's settings, so nothing asks for access as the starter opens; elsewhere the page keeps its examples. Its credits.json
names the upstream repository at its commit and the two fonts it ships, each with its license file. A game's or a
screen's starter has no App.swift: `StartersTests` looks for its `Web/index.html`, and check-starters.sh type-checks its
Native.swift against Lamp's LampPage.swift. `StartersBuildTests` can't build one (the screen and game kits are in
Lamp's bundle): build it in a Lamp Dev instance. New York has no Swift of its own, so it's prebuilt as a copy of Lamp's
player (build.sh builds the player before the starters, and `PrebuiltStarters` hands it to the starter's build as a
person's Mac does); Home HQ's Native.swift makes it compiled ("Lamp's player" in the devices guide).
A starter whose code imports RealityKit (none does now) gets LampScene.swift and macOS 15 like any app with a 3D scene
(`Template.withScene`), and check-starters.sh type-checks it that way; on a Mac below macOS 15 it isn't put on the desk
or offered at all (`Starters.runsHere`), and it's offered once the Mac is updated.

A starter deleted from the desk is gone, as any wish is; a remix of it from the site puts a fresh copy back
(`Store.put(starter:)`, through `Store.add(starter:)`, the one way a starter is put on the desk, which the first launch
uses too), saved and built out of sight like the first launch's.

**A starter added or changed in how it looks gets a new preview in the same change** (`StartersTests` fails
without one). Take it from the app itself, not a mock-up: open the starter's build in Lamp Dev with its chat closed,
and once its window has settled its `.lamp/runtime/preview.png` is the picture (the app writes it at each launch,
without Lamp's chat). Shrink it to at most 800 px on the long side (`sips -Z 800`) and put it at `.github/preview.png`
in the starter's repository, then move the pin (below). Look at it before committing: example content only, nothing
from the Mac it was taken on (names, folders, accounts). A starter that opens no window (the menu bar) is pictured
with its panel open.

**Changing a starter.** Its repository is the starter; Lamp pins a commit of it. A change is best made in Lamp Dev,
where it's played as it's made: open the starter with File → Open from GitHub… (github.com/lampdotdev/<folder>), ask
for the change, then File → Send Changes Back…, which opens a pull request on the repository (a member of the account's
starters team, which has push access to every starter's repository, can Put on GitHub to it directly). A change made in a clone and pushed is as good. Once the repository has moved on,
`scripts/pull-starters.sh [<folder>]` moves the pin to its latest commit and fetches the tree: look at what changed
(`git -C Resources/Starters/<folder>/tree log`, or the repository), run `scripts/check-starters.sh <folder>` and
`swift test --filter StartersTests`, and commit the starter.md. When the icon's design (icon.json) changed, draw the
icon again (step 4 below) and publish, so the repository's pictures match; `scripts/publish-starters.sh` after any
change puts Lamp's own files right again, should a push have touched them. Bringing in what changed in work a
starter is based on (Slop New York for New York) is a request like any other: "Bring in what's new in <repository>
since <the commit credits.json names>, keeping our changes", which the agent ports, moving the commit in
credits.json on.

**Turning an app made with Lamp into a starter.** The app is a wish on this Mac, under `~/Library/Application
Support/Lamp Dev/Apps/<folder>` (or `Lamp/Apps` for the installed Lamp); its repository is made from it.

1. Make it right for anyone, in Lamp: read the code for what only works for its maker or only for now. A date
   written in (a deadline, a year) goes relative to the first launch and is saved then, so the app means something
   whenever Lamp was installed; a global shortcut mustn't take one the system or common apps use (⌘⇧G is Go to Folder
   everywhere); a key, an account or the maker's own files and names have no place in it. Content is example content
   the person can change or clear. Its description (what a shared file carries) is also the starter's description on
   GitHub: one plain sentence about what it does. For one built on someone else's work, its credits name that work and
   the license files beside it.
2. Write its `APP.md` for the agent that changes it, in the shape the other starters' have (`Kind:`, what it does,
   Code, Data, Easy to change), from the code as it is.
3. Write `Resources/Starters/<folder>/starter.md`: `name`, `offer` ("Make <name> yours") and three tweaks of at most
   six words, each with an SF Symbol: a new look, a new thing it does, and a new subject (as above), each big enough to
   show the person the app can become their own rather than be adjusted. They're changes the app doesn't already make,
   that the agent can make in one request with no key or account, drawn in code rather than pictures. The offer and
   tweaks are also the "Ideas to try" in its repository's README. Leave out `repository:` and `commit:`: step 4 writes
   them.
4. Put it on GitHub: `./build.sh`, then `scripts/publish-starters.sh --new <folder> <the wish's folder>`, signed in
   with `gh` to an account that can make repositories in lampdotdev. It makes the public repository (and a game's
   page) from the wish as Put on GitHub would, gives the account's starters team push access to it (the team whose
   members make and change starters), and fills in the starter's `repository:` and `commit:`, fetching the tree. Then its pictures: take `preview.png` as above, and paint and draw the icon into the tree with
   `LAMP_RENDER_STARTER_ICONS=<folder> LAMP_PAINT_STARTER_ART=1 OPENROUTER_API_KEY=… swift test --filter
   StarterIconsTests`, look at the artwork it picked, and run `scripts/publish-starters.sh <folder>` again to put them
   up (the README shows them).
5. Run `scripts/check-starters.sh <folder>` and `swift test --filter StartersTests`, update the count of wishes above,
   and commit starter.md with the change; look at the repository's README on GitHub.

