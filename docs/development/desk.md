# The desk

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

Lamp's window is the desk and only the desk (`WishDesk`, `Desk.swift`): no wish's chat is ever drawn in it. It shows the
person's wishes as icons, first, since using one and
changing it is where most wishes start, and under them the one place to make a new one. A click's hint says it
opens to use and change (`DeskIcon`). Wishes are dragged into the order the person wants (`DeskArrangement`, kept by
instance so a rename keeps a wish's place; name order until the first drag, and a new wish goes at the end after it);
while one is dragged, a trash beside Settings in the toolbar deletes what's let go on it (`DeskTrash`), as the Dock's
Trash does (`WishDrag`). Everything someone makes with Lamp is a **wish** in what they read; a wish may
be made of an app, a widget, a menu bar item, a watch app, so "app" stays where it means that piece. A wish is
typed in the bar, or said with the talk button beside it (`TalkButton`, moving with `Dictation.level`); either
way it goes to a new wish's chat and is sent from there (`Store.wish`, `sendWhenShown`), so it passes the same
setup checks as anything typed in a chat. Its chat doesn't pop up out of nowhere: the bar lifts off the desk and
grows into the chat's window, lit in the colors of the smoke an app being changed shows (`LampTransition.Look.hues`),
with a few sparks rising off it, and the chat fades in where it lands (`WishArrival`, drawn in a window of its own
over the desk, so the chat is laid out once, at its real size). Where the person asked for less motion, or the chat
opens on another screen than the bar's, it opens at once. A click on a wish (or Return, or Open on its menu) opens it to use and
change at once (`Store.open(fromDesk:)`), always with its chat beside whatever shows it: a Mac app with windows opens with
its chat beside it (`Store.change`, below; a notification's click goes the same way, `Store.openChat`); a wish that opens
no Mac window is used (`Store.use`) with its chat in Lamp's panel, beside the simulator, the emulator or Lamp's preview
that shows it, or on its own where nothing on this Mac does (`ChatPanel`, "The chat's one screen" in the chat guide); one
still coming true, or waiting on an answer, opens its chat. Change… on its menu changes it the same way. Under each icon is its
name, and a dot says it's ready. The one wait the desk shows is a starter clicked before Lamp has built it, since
nothing else on screen says the click did anything until it opens by itself (`openWhenReady`): its icon glows, the light
Lamp puts round an app's windows going round it, and "Getting it ready…" is under its name, a sheen crossing it so the
wait never looks frozen (`BuildingGlow`, `DeskStatusLine`); both settle when it opens, and stay still where the person
asked for less motion. Nothing else lights a tile: a wish being made or changed shows that in its chat, and Lamp's own
work on a wish (a rename, Undo, Reload, a new icon) shows nothing on the desk. VoiceOver hears "Opening…" for such a
starter, "Coming true…" or "Changing…" for a wish being worked on, and where a wish lives after its name (`WishPlace`, read
from its files). While the pointer is on a wish, its picture and what it is take the place where a new wish is made
(`WishStage`), which steps back and fades. When it's used where nothing comes
forward (the menu bar, a widget, the background, the person's own phone) the desk says so in `WishHUD`, a
large translucent square like macOS's old volume display. Lamp's mark at the start of its chat's bar brings the desk back in front (⌘[).

Between the wishes and the bar is the shelf of the person's devices (`DeskDevices`), since a wish for the TV or
the phone is what Lamp is for and Settings is no place to find that out. Until Lamp has looked on the network
(`localNetworkAsked`) it's one capsule inviting the person to, whose Find My Devices is the look macOS asks about; from
then on the desk looks each time it's shown or Lamp comes to the front, at most once a minute (`lookForDevices`), and
the shelf is the devices as capsules: this Mac, then the person's own, then what was only found that Lamp makes apps
for or controls, each kind in the order people make most for (`DeskDevices.ranked`), as many as two lines hold
(`DeskDevices.fitting`), then "N More" (which opens Settings → Your Devices, where the whole network is) and Add a
Device (`AddDeviceSheet`), which are always on the second line's end. What Lamp could
only learn (a server, an appliance) is counted in More, never shown. A green dot is ready, and a click puts "for my
<device>" in the bar; a gearshape and an amber dot is a step to take, and a click takes it (`DeviceNextStep.takeFurther`,
Settings where Lamp can't from here). A chip's name is short and plain (`DeskDevices.label`: a found one by its model,
never an address or a serial); what else is known is in its tip a moment after the pointer comes onto it
(`DeviceTip`), never its address. macOS refusing the network is `LocalNetworkRefused` under the shelf.

"Help me find one" (`Store.findWish`) is the site's wizard in the app, held in the ordinary chat: a new wish
marked `finding` whose first request is `Agent.findingRequest`. The agent asks about the person's days in
`ask` cards (`Agent.findRules`), never about apps, and ends by writing the wish into the message box with
`write_wish`, word by word as a wish from the site arrives (`Store.writeIn`), for the person to change and
send. Until that message, nothing is named, scaffolded, built or saved (`startQueued`, `turn`): the wish it
becomes may be an iPhone app, which a scaffold already written as a Mac app would rule out. The message that
isn't an answer to a card names it like any first request and ends `finding`.

A new person's desk isn't empty: Lamp comes with fourteen wishes (`Starters`, from `Resources/Starters`), working
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
preview.png, a picture of its window that the desk shows while the pointer is on the icon,
with the app's about.json line beside it in large type, 90 characters at most (`WishStage`, `WishDesk.describedIn`; every
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
(`GitHubRepo.readme` with a `Showcase`) opens with the icon and preview from `.github/`, the description, and "Ideas
to try" titled with starter.md's `offer` and listing its tweaks. A game whose page is the whole game also gets a page
anyone plays in a browser (`StarterRepos.stagePage`: Publish's page with the credit bar and the tweaks in its Remix
panel, on the repository's `gh-pages` branch for GitHub Pages, at lampdotdev.github.io/<folder>), which the README
links and the repository's website points to. `scripts/publish-starters.sh` refreshes all of that: it clones each
repository's latest and stages it with the built Lamp Dev (`--stage-starter-repos … --trees`, as a wish is staged,
with an identity derived from the starter and a fixed export time, so an unchanged repository makes no commit),
pushes one commit of what's Lamp's, never the app itself, and moves the pin in starter.md to it, fetching the tree;
`--dry-run` only stages. Run it after changing Lamp's own files, before the release that ships the change, and commit
the starter.md files it moved. The drawn icon of a repository published before it lived there is still read from
beside starter.md until the publish puts it up (`Starters.iconFolder(of:)`); that folder goes once every one has.
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

Starters not on the desk (never added, or deleted since; `Starters.missing`) are offered at its end as one dashed
tile, Starter wishes (`MoreFromLamp`): up to four of their icons and how many there are, and a click lists them with
an Add each. Add puts that one back (`Store.put(starter:)`, through `Store.add(starter:)`, the one way a starter is put
on the desk, which the first launch uses too), saved and built out of sight like the first launch's, and opens it
at once as a click on the desk would (`open(fromDesk:)`: one not built yet spins and opens when it's ready). The tile goes
once every one is there.

**A starter added or changed in how it looks gets a new preview in the same change** (`StartersTests` fails
without one). Take it from the app itself, not a mock-up: open the starter's build in Lamp Dev with its chat closed,
and once its window has settled its `.lamp/runtime/preview.png` is the picture (the app writes it at each launch,
without Lamp's chat). Shrink it to at most 800 px on the long side (`sips -Z 800`) and put it at `.github/preview.png`
in the starter's repository, then move the pin (below). Look at it before committing: example content only, nothing
from the Mac it was taken on (names, folders, accounts). A starter that opens no window (the menu bar) is pictured
with its panel open.

**Changing a starter.** Its repository is the starter; Lamp pins a commit of it. A change is best made in Lamp Dev,
where it's played as it's made: open the starter with File → Open from GitHub… (github.com/lampdotdev/<folder>), ask
for the change, then File → Send Changes Back…, which opens a pull request on the repository (with push access, Put on
GitHub puts it there directly). A change made in a clone and pushed is as good. Once the repository has moved on,
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
   page) from the wish as Put on GitHub would, and fills in the starter's `repository:` and `commit:`, fetching the
   tree. Then its pictures: take `preview.png` as above, and paint and draw the icon into the tree with
   `LAMP_RENDER_STARTER_ICONS=<folder> LAMP_PAINT_STARTER_ART=1 OPENROUTER_API_KEY=… swift test --filter
   StarterIconsTests`, look at the artwork it picked, and run `scripts/publish-starters.sh <folder>` again to put them
   up (the README shows them).
5. Run `scripts/check-starters.sh <folder>` and `swift test --filter StartersTests`, update the count of wishes above,
   and commit starter.md with the change; look at the repository's README on GitHub.

