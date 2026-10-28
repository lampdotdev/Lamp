# Live changes to an open app

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

A game drawn on Lamp's game runtime goes its own way: a change of its page goes into the open game by the page itself (`PageLive`; "Games" in the devices guide), on the Mac and in the simulator alike, and none of what follows applies to it.

Whether the change was asked for beside the app or in Lamp's panel, a change goes into the open app without a restart when it can (`LiveReload`). The
Mac app, or the Mac half of an app for both while Try On points at this Mac, is
built live (a widget or share extension is built from the same copy, and a change to one reopens the app): build.sh with `LAMP_LIVE=1` copies Sources into `.lamp/live` with each `var body: some View` wrapped
(`Template.liveCopySteps`: the body becomes `AnyView` and reads `LampLive.generation`, so its type never changes and
every view draws again on a reload with its state kept, except where a body's structure changed: SwiftUI builds what's
inside it again, its views' state included, which `Agent.liveNote` tells the agent), and builds that copy unoptimized, testable, with
`LAMP_LIVE` and `-Xlinker -interposable` (SwiftPM for a Mac app; Xcode for an app for both, from a copy of the
device project, with its debug library off so the code is in the one binary). The copy is made by one
perl pass over each file (`Template.livePerl`: the body wrap, a read of the generation in what SwiftUI keeps besides a body (a modifier's
`body(content:)`, a style's `makeBody`, a layout's methods, the body of content that isn't a view (a toolbar's, a chart's, a map's, a tab's); `LampLive.touch`, matched only up to the declaration's own
`{`, never across another declaration; and for a
`sizeThatFits` written as one expression `LampLive.touched`, which runs it after the read; a layout is asked again only
when SwiftUI lays out again, which the read doesn't force; a representable's make and update aren't given the read,
since every representable would then run its update on every change (a web view reloading), and neither is a
`Shape`'s `path(in:)`, which SwiftUI asks again only when the shape's value changes: `Agent.liveNote` tells the agent), Lamp's entry, the spare places and the `final` below,
with the stretches of strings and comments found once and never touched). It makes every class `final` that nothing
in Sources subclasses (`live.pl scan` lists the names used as superclasses and as the bounds of generic parameters
and `where` clauses, followed through typealiases): a final class keeps no method table, so a method or computed
property added to it goes in, where one added to a class with a table reopens the app; a class made final that
something subclasses after all fails the build in the compiler's words, which `LiveSlots.brokeFinal` reads (unless
the app's own code wrote that class `final`, when the error is the agent's), and the copy is made without the step
from then on (`no-final`). A class's finality and its initializers (which have method descriptors, a final class's too; a convenience initializer, as any in an extension is, has none
unless it's required) are held with the layout (`LiveReload.Group.inits`),
so a subclass added, or an initializer added or changed, reopens the app with its reason rather than being refused
by the runtime after the compile. So is each type's shape (`LiveReload.Group.shape`): struct, class, enum or actor, an
enum's `@objc` and `indirect`, whether the type is generic (itself or declared inside a generic type, with its
parameters, `generic<T>`), a class's superclass (the first name it inherits when
that's one of the app's classes, or a system name the class's initializers show it inherits from: one of them
overriding, the compiler's own included, or a `super` call; a system protocol such as `ObservableObject` is no superclass), and a protocol's requirement signature (`: AnyObject`, what it inherits, its associated types' constraints) and its
`@objc` (whose values are one word where a Swift protocol's take two), each of which lays values, objects,
method tables or witness tables out differently while the type holds the same fields; a stored reference's `weak`
or `unowned` is part of its field's entry (`Owner<tab>weak helper: Helper?`). A new class under one the open app has
reopens it too: the library's copy of it would be laid out from, and cast against, the change's copy of its superclass,
not the app's. A shape is compared only where both
layouts have one, so a layout an earlier Lamp kept says nothing of it. After a build, `Store.install` tries
`reloadInPlace` first, which decides the app is open and built live, takes the verdict and hands the changed files to
`LiveReload.put`, the one pipeline from the layout check to the record of what the app now runs, acting on its
`Outcome` (it went in, with what was done beyond the code; or why the app has to reopen): the change goes in when the app is open, was built live, and the change didn't touch what's read only at launch (the App, its scenes, its menu commands, an application delegate and their extensions, wherever they're written: `SwiftSource.LaunchReader`, held to what the open app had as part of the layout, with the code they call, as far down as that goes but not their actions', `LiveReload.launchCalls`, since it ran once too
(into an initializer's type only by what its stored properties' starting values call: a view's `body` runs at each draw,
and the values themselves are state like any object's, so the window's view and the model the App holds change live; and
never into a SwiftUI view or an observable model, whose initializers and starting values build the state SwiftUI draws
from, kept by a live change like every view's and model's, while a controller's, an `NSMenu` it builds once, is AppKit's
and still counts); a view or helper beside them goes in like any code; the file of a SwiftData `@Model` class is held whole, since its accessors find its data by key paths a recompiled file makes over again, and one the change didn't touch is left out of a compile of every file when it names nothing newly declared, `LiveReload.addedNames`; a conformance, subscript or operator, which code reaches without naming it, or a declaration taken away keeps it in) or Lamp's own files, and leaves every type
holding what it did (`LiveReload.layout`: the compiler's own list of each type's stored properties (their types in Swift's short
spellings, so `Array<String>` is `[String]`, only where the name is Swift's and no type of the app's) and cases (with their raw values, which an `@objc` enum's values are and
a raw-value enum hashes by; a raw type given to an existing enum or taken from it reopens the app too),
from `-dump-ast` of just the changed files, compared for the open app's sources and the new ones; no reading of the
text; a typealias is printed as itself wherever it's used, so each is listed with what it names and one the open app has that now names something else reopens, `LiveReload.aliasGroup`, as does a name that was a
typealias and is now a type of its own, or the other way round; a case is listed with whether it's `indirect`; an associated type the compiler inferred, such
as Identifiable's `ID` or a Sequence's `Iterator`, is a typealias it declares itself and is listed the same; a member
returning `some …`, a modifier's `body(content:)` or a style's `makeBody`, whose type is what it builds, is listed by that
type as the compiler prints it where the body's value becomes the opaque one, `LiveReload.opaqueGroup`, except a view's own `some View` helper that no protocol requires and only views' bodies use, whose value is made again at every draw: it goes in with every file compiled again, `LiveReload.freeOpaque`; so `1` may
become `1.5` only if the member returns a Double now, and `Text("a")` may become `Text("a").bold()`; where that type is
opaque too (a modifier's `some View`) it's listed by a digest of every node in its body whose type involves an opaque
one, by that type (`(some Equatable, Int)`, so a tuple's or array's plain parts count) and by the declaration it calls
with the types it was given (`padding [with … Self -> Text]`), which together are the type: `.bold()` added before
`.padding()` changes nothing, `.font()` after it does, and so does another overload (`padding()` to `padding(12)`),
whose opaque result is another type even when it builds the same one: the open app's witness tables and callers were laid out for the type it had, and the
compiler prints both as `some View`; a view's own body, wrapped by the live copy, and a private member that isn't stored are left out, though what a
private one builds is part of the entry of any member whose body names it, since an internal member built from a
private one returns its type to callers anywhere; a private type is listed with its file,
`LiveReload.placeGroup`, since its mangled name carries it and one moved to another file is another type at run time (so is a type, a
static or a global made private or no longer private, or a private static or global moved to another file, which
reopens the app too, as does a conformance taken away, whose record the open app keeps, unless what it still conforms
to brings it, as the system's Hashable brings Equatable),
and keyed with its file throughout the layout and the declarations (`Row@A.swift`, each part of a nested one; `LiveReload.bare`
gives the name back where the code names it, as a field's type or a use in old code does, and `readable` says "Row in
A.swift"), since two files may each declare a private type of one name and the two are two types with their own fields;
every such entry beyond a type's own fields is one of `LiveReload.Group`, which makes and reads them; the printout is
read in one pass, `SwiftSource.walk`, which keeps the scopes and keys every type the one way (nested under its outer
type, a private one with its file, a local one with its function) for every reader of it: the layout (`LiveReload.Members`),
where each property is declared (`SwiftSource.DeclarationsReader`), what's read at launch (`LaunchReader`) and what
old code does (`LiveReload.OldCode`), all taking the same lines in one walk in `LiveReload.analysis`, so a type can't
be keyed two ways by two readers); what a stretch of code names (a constant, a type, a view's `$name`, a publisher) is the
compiler's own resolution of it (`Declarations.uses`, from each reference's `decl`, each annotation's `bind` and each type
written out), never a search of its text, so a string, a comment or another type's member of the same name is no use of
it, and a case alone (`.a`) is no use of its enum as a whole (`LiveReload.verdict`, comparing with the sources the open app runs, kept in `.lamp/live/running`, which holds only
for the copy that took the last change: one opened again since, by the person or macOS, runs what was installed,
which Lamp keeps beside it (`.lamp/live/installed`), so the change is judged against that, `LiveReload.tookChanges`,
`backToInstalled`), only the changed files are compiled (as primaries, the rest of the live copy read for context) and
linked into a library. Every file is compiled when what's declared changed (a function, an initializer, a computed
property, a conformance, a member's `@objc` and its selector, a stored property, which may stand where a protocol extension's member of its
name did, and its observers, which turn every write into a call, a typealias, and a private member made visible: `LiveReload.declarationGroup`, `declarationsChanged`; not a type a freestanding
macro writes, such as `#Preview`'s, which is named after its line and which nothing in the app uses), since an unchanged caller may then mean
another one (a new overload, a method where a protocol's default stood in), and a file taken away while another
arrives (one renamed) is compiled like any other: what was private to it is named after its file and would start
over, which the layout's check says for each type, static or global that moved.
What's compiled is decided before anything is: the changed files are compiled alongside the layout's check, and that
library is the one sent unless something widened it (spares rewriting the copy, what's declared changing, an enum
growing, a constant remade), in which case every file the change needs is compiled once, at the end of `attempt`,
never once per reason. The library is what the app loads when asked with a request signed with its token, only from its
own `.lamp/live` (`LampLive` in LampSupport, under `#if LAMP_LIVE`). It points the app's own calls at the new
functions by rewriting the symbol pointers they go through, and the method tables of the app's classes (their
deinit included) at the changed methods; types, metadata and stored globals are left alone. A library compiled from
a changed file defines that file's types over again, and its code refers to its own copies directly, which no symbol
pointer reaches: a value would then carry one copy's identity or the other's, so `as? Point` fails across the change,
a conformance added in it isn't found, and SwiftUI, seeing a new type for a view's body, remakes the whole subtree
and loses every state in it. So between compiling and linking, `LiveObject` rewrites each object: every type's
metadata, descriptor and protocol descriptor it defines is renamed (`$lampcopy`), and the code's references become
loads through the global offset table of a weak undefined symbol with the original name (a reference to a type's full
metadata at its address point's offset, `…VMf + 16`, names the type's own symbol, `…VN`, there, since a load through the
table carries no offset), which `LampLive` binds to the
app's copy, or to the library's own for a type the app doesn't have (a new one, kept for the changes after it, and an
enum it brings stays that change's when a later change grows it, so its values made before are the same type). A
conformance's descriptor and witness table are treated the same, since the runtime tells generic types apart by them
too (`[AnyHashable: …]` keys), which is why a protocol's requirements, their accessors included, are part of the
layout a change is held to (`LiveReload.members`): the app's witness tables must fit. What the library's data names
is worked out before anything is pointed at the new code, so a change refused leaves the app as it was, and written
before too, since each write opens and closes a page of the library for writing, which a thread already running
the new code there would stop at. So is every
stored global's or static's addressor, since the library's own code calls its own copy directly and would otherwise
keep a second copy of the value; through the table the library's accessors reach the app's storage, so they are
code like any other, and a `didSet` added to a static goes in. The mangled type
names and the records of conformances the change adds, which the library's data still holds, are pointed at the app's
descriptors as it loads (`LampLive.redirectDescriptors`, writing through the library's text, which a Mac app without
the hardened runtime may). A class Swift makes as the app runs (a generic class at each type it's used at, a class under
a generic superclass) gets its method table from the app's description of it, which holds the app's code: so the live
copy starts the app through an entry of Lamp's (`__LampEntry`, added by the copy step before the App's own, a comment
after `@main` included), which
first points the runtime's call that fills such tables in (`swift_initClassMetadata2`, through the same symbol pointer
as any call) at `LampLive.classMade`, which records every class made and points its table at the newest code, and a
change points every table made so far the same way. A key path to a computed property is told apart by its getter's address, and a change has a getter of its own, so a
key path the change's code makes would be another than the app's, and observation keyed by the app's
(`withObservationTracking`, an App's or a scene's body, which no change draws again) would stop hearing the
property: every key path made goes through `LampLive.keyPathMade` too (a hook on `swift_getKeyPath`), which points
each of a change's getters in it at the app's of the same name, or the first change's that had it. A method's
place in a table moves to the new code whatever the method's access, a private class's and a private override's
included, since every code symbol of a change is read, not only the exported ones. A witness table (what a call through a protocol goes through) holds a
thunk for each requirement, which calls whichever method answers it, so one compiled when the protocol's own default
answered goes on calling it after the change answers it in the type: the app's tables, and those the runtime makes
(recorded through `swift_getWitnessTable` the same way, `tableMade`; a conformance with no table of its own in the
image, to a system protocol that may change between releases, has its table asked for and recorded at launch and when
a change brings one, `recordTables`, since the first to ask may be a cast rather than a hooked request), are pointed
at the new thunks. A default argument is made by a function of its own, which every caller calls, so it's rebound like any
function. What a class answers to from Objective-C (an override of a system class's method, a selector's target) is in
its method list, not its table, so a kept class takes its copy's methods (`takeMethods`, read off the copy's class data,
since the runtime has never seen the copy), and the change's categories (an extension's `@objc` members, an override in
one): the runtime would attach those to the kept classes as the library loads, before any check, so `LiveObject` renames
their list (`__lamp_catlist`) and `LampLive` attaches them once the change fits (`attach`). What `LampLive` can't make
right it refuses, and the app reopens: a class's method table that changed shape, a class whose methods the change lists
in another order than the app (one added, taken away or moved), since a table made after it would be laid out from the
app's list, or a kept class that answers to something from Objective-C its copy no longer has (`removedMethods`), which
it would go on answering with old code; that last is judged only for a change compiled from every file (`whole`, sent
with the change), which is what a declaration taken away gets, since another leaves what an unchanged file's extension
adds. The
build then waits to be installed until the app closes (`LiveReload.awaitInstall`, which unlike a held build doesn't
keep the agent off the app). The libraries of earlier changes go once a later one is in, and all of them when the
app is installed (`LiveReload.forgetLibraries`): a loaded one stays mapped, and otherwise a long session leaves one
for every change tried. Anything else needs the app reopened, with why in the chat's
details (`LiveReload.Verdict`; what `LampLive` refused, and a change that didn't compile or load, say so there too,
through `LiveReload.send`'s answer), so the rules can be tuned by what happens. The compiler's printout of a big app is tens of megabytes: it's kept whole off the main actor (`Sandbox.output`), each pattern is tried only on the nodes it could match (`SwiftSource.node`), and what's read from it is kept in memory by a digest of the code (`LiveReload.Analyses`), so the same code is never printed twice, the open app's layout after a reopen included. A change refused is refused again at the install after its build without that work, while nothing it was judged on has changed (`LiveReload.put`, `refusalKey`); a refusal by the open app itself is tried again. For a request's change, while the app is open, Lamp doesn't reopen it under the person: the build is held (`Store.awaitReload`, `Runtime.awaitReload`), the app shows a Reload button beside the wand in its title bar (`LampMagic.ReloadButton`, tinted glass in the accent color whose tint brightens and settles again, shown with a `reloadReady` notification) and the chat a line with one too (`.reload`, under the agent's answer), and a click on either reopens it where it was (`Store.reloadWaiting`; the app asks with `reloadNow`, which puts in only a change Lamp holds). The agent is told the change waits for the person (`reloadNote`) and goes on with what's left, never saying the change is in; a look after that stops the turn until they press it (`Store.held`, below), so the agent never acts on an app it can't see. Reload pressed while the agent works isn't kept for the turn's end: the turn that owns the app reopens it as soon as the agent is between steps (`Store.reloadInTurn`, from the `autoApply` loop: no look, build, change going in or call into Lamp under way), the paused request goes on once the app is given back, and a look in that turn would say the change is on screen (`Turn.reloadedByPerson`). Closing the app installs it too. A look with `reopen` asks the same way while the person has the app open (`Store.asksBeforeReopening`, the one check for both): it puts in what it can as the app runs, then holds the app for Reload and tells the agent so (`askedToReopenNote`). Both show the same Reload button and chat line, nothing of their own. Open App and Undo still reopen it, and so does every change and every look in a new app's first turn, which
nobody is using yet and whose passes the person is watching go in; when the person keeps the app open at its question (unsaved work), the build waits for Reload the same way. A live build reads the app's own files from its Assets folder rather than its bundle (`LampAssets`), so a new picture goes in live too (a change of those files alone has no code to load, so the app is asked to draw again, `LiveReload.redraw`); the package, the
app's settings and its icon still reopen it. Each request to a live app ends with `Agent.liveNote`, which tells the
agent what goes in without reopening. The note opens by saying the person is watching the app beside the chat and
sees a live change at once and a held one not until Reload, so the agent works in small shown steps. Each look then
tells the agent which way its change went (`ChangeOutcome`): into the open app, waiting for Reload with LiveReload's
reason and, where there's a known shape that would have gone in, that shape (`LiveReload.advice`), or reopened or
opened; and how long the look took, since a look is how the agent sees what the person sees, and it puts looks off
when it's only told they take a while. A change held for Reload doesn't stop the agent by itself: the look's
answer (`reloadNote`, `askedToReopenNote`, `keptOpenNote`, through `Store.held`) says to go on with the passes left,
that they're held with it and show after Reload, never to say a held change is in (a progress line says what was built
and that it shows after Reload), and that looking again is how to ask to see. A look once the agent has been told, or
any `use_app` while the change waits, is the agent asking to see or try an app that doesn't show its change, and
stops the turn (`Store.stopsToSee`, `Store.pause`): the answer (`seeNote`) tells it to say in a sentence that it
needs to see the change and ask for what puts it in (Reload, or closing the app where the person kept an earlier
copy open and no Reload is offered), and end; an agent that calls another tool is ended by Lamp, as one is
after `ask` (`Store.endIfOver`), Codex by its own interrupt so its conversation keeps the answer. Lamp's own request
to carry on (`Agent.afterReload`, a `QueuedMessage` marked `afterReload`, hidden in the chat as a crash fix's request
is, with `ChatLook.carryingOn` above it) waits in line until the held change is in (`Store.startsNow`): the person's
Reload, or the app closing, puts it in and the agent goes on in the same conversation on every engine, looking first.
A Reload pressed while the turn goes on puts the change in between the agent's steps (`reloadInTurn`) and the agent is
told at its next look, which no longer stops it (`Turn.toldHeld` is cleared). The paused queue is
kept across a relaunch like one waiting for setup (`Store.keptAcrossRelaunch`, `QueuedMessage.saved` with its flags and
what each message points at, its files copied aside as a request waiting for setup has them, `Store.keptForLater`),
since the held build outlives Lamp too; Undo, an earlier version and a request sent again drop it
(`Store.dropPausedRequest`). A file the agent wrote in the moment before Lamp ended it that doesn't build is neither
saved nor installed, as after any build that fails, and its errors ride with the carry-on request (`Store.carry`). Only
the Reload button reloads the app, or Lamp for the person once they've stepped away: with no input on the Mac for
three minutes (`AwayReloads.after`, the window server's own count, so no permission is asked for) while a request's
change waits for it, Lamp presses it and says so in the chat (`Store.reloadIfAway`). A turn still at work puts it in
between its steps; once the turn is over (paused, the agent asking for Reload in its reply, or the Reload put off until
its end) the agent gets the same carry-on request as after a pause (`Store.queueCarryOn`), decided when the change is
actually in, so it looks and finishes what was left. After the person's Stop, or while a question of the agent's waits for
their answer, Lamp neither reloads for the agent nor carries it on until they send a request (`AwayReloads`). A message typed meanwhile waits in the same line (the chats say "Sent once you
press Reload" under it, `ChatLook.waitingForReload`), since the chat is beside the app and a reopen takes the chat
down with it, and nothing the agent did meanwhile could be seen. So the note asks for the changes that go in live
first and the held ones last, naming what's held (the icon, capabilities.json, a widget or Share item, what's read at launch, a Codable
type's new stored properties), so a request ends with one Reload at most. Changes saved close together go in together
(`Store.autoApply` tries a state once it holds still), so one that can't go in live holds back everything saved with
it, and the agent can't always tell which those are (an edit to code a launch-time constant reads is one): the note
asks for the most visible piece (a theme's colors) to be saved alone and looked at before anything else, and for a
look before the first change that needs a reopen, with those changes started only once it says the earlier ones are in. The turn's end tallies them in a detail line (`Store.outcomeTally`), which is how often changes go in live,
and says how long the person waited to see the turn's first change and the longest wait between changes after it
(`Store.paceTally`, from `Turn.shown`), which is what the rules for showing work early are judged by. While
the agent works, Lamp also puts each change it saves into the open app by itself (`Store.autoApply`: the sources read
every two seconds, a state tried once it holds still, through the quick path a look takes), so the person sees each
piece as it's written; what can't go in live is left for the turn's end, which holds it for Reload once with the rest.
A build of Lamp's waits for a change going in and keeps the loop off while it runs (`Turn.building`, `Turn.applying`);
one for sources the agent has moved on from gives way, before its compile, to the build that takes the newer ones, and
Stop ends one the same way (`Turn.cancel`). The
open app's layout is worked out as soon as the app is open (`LiveReload.warm`, `Store.warmLive`), so the compiler's slow first
read of a session is over before the agent's first save rather than in front of it.

New stored properties go in live too (`LiveSlots`, in LiveReload.swift). The copy step (`Template.livePerl`) gives
each type of the app's spare room the open app's values already have: every class a few places,
`__lampSpare_<Class>_0`… of `LampSpare?` (named after the class, so a subclass's don't clash with what it inherits;
plain in an `ObservableObject` too, so only a moved `@Published` property announces its changes, its setter calling
`LampSpare.announce`), every view one `@State` box (`__lampState_<View>`, a
`LampStateBox`, which keeps new `@State`, and new `@AppStorage` in the standard defaults under its own key, drawing the
views that read it again when the defaults change, from anywhere; not in an app that gives views a store of its own,
`defaultAppStorage`, which Lamp can't tell a view reads from), one spare for new parameters
(`__lampSpare_<View>`, one more argument with a default of the initializer Swift makes for the view, as a struct's is), and its environment
(`@Environment(\.self) private var __lampEnv_<View>`), from which a new `@Environment(\.key)` is read as a computed
property: SwiftUI hands the whole environment to the view at each draw, and draws a view that keeps it again only when
something in it changes, which costs little. One read by its type (`@Environment(Store.self)`) reopens the app, since
the environment can't be asked for it by type. And every other struct one place holding any number of properties by name (`__lampSpare_<Struct>`, not optional,
so its own `==` and hash run: they take a property never set as its starting value; saved data leaves it out
through two overloads of the keyed coding containers, which the compiler's Codable code takes over the general ones). A struct's moved properties drop out of the initializer Swift makes for it, which the new code may call with them,
so `LiveSlots.memberwiseInitializers` makes that one again in an extension in the struct's file, from the labels and types
the compiler lists for it (`SwiftSource.Declarations.memberwise`), one for each moved property, so a call passing any
of them is matched by the first it passes and one passing none only by Swift's own. So does a struct whose memberwise
initializer is private, since these extensions go in the type's own file. A view's moved `@State` is no parameter of
the view's initializer any more, and can't be made one (SwiftUI makes the state box lazily, after the initializer
has run, so a value given that way would be lost): a change whose code passes it there reopens the app, saying so. A
view's new plain property (any but a `let` with a literal, which stays that literal) is a parameter, kept in the view's
own spare and set by its memberwise initializer made again as a struct's is (state already in the box left out of it),
only where every value of the view is made by a body, code only bodies call, or an old-style preview
(`LiveReload.madeOutsideBodies`): each is then made again by the new code before it
draws, so one with no starting value reads, until then, as its type's empty value (`LiveSlots.emptyValue`: nil, false,
0, "", an empty collection, an action that does nothing), which nothing sees; a type with none reopens the app, and so does a starting value that may differ from one read to
the next (`UUID()`), since a call that leaves the parameter out never sets it. A view
made elsewhere (the window's root, a hosting view's) keeps what the open app made, so a new property of it goes in only
as a literal, which it then always is, and one its maker passes reopens the app. A new `@Binding` is a parameter the
same way, its binding kept in the spare under its `$name` (`__lampBinding_<name>`), which the property reads and writes
through; SwiftUI hears it as it hears any binding read in a body. Any other wrapper reopens the app: SwiftUI fills a
wrapper in only where the view stored it when the app opened. A struct or view declared inside a function can't be extended, so a
property added to one reopens the app with that reason. A class's moved property is a `final` computed one, so a
class something subclasses keeps the method table the open app laid out. The spare itself is a parameter
of that initializer too, with a default, which a call never notices but a reference to the initializer as a value
(`.map(Item.init)`) does, since it matches by the whole signature: when a live build fails on the spares
(`LiveSlots.brokeBuild`), every struct the copy gave a spare has its memberwise initializer written again without
the spare's parameter, in `.lamp/live/Sources/LampMemberwise.swift` (`LiveSlots.addMemberwise`, from a dump of the
plain sources, which the copy step keeps), and the build is tried once more before spares are given up.
Left out is what a spare would break: SwiftData and Core Data models, `Sendable` classes, `Equatable` views (declared
so, or made so in an extension, which the scan reports), a class under a class of the same simple name (whose spare
places would clash), the App
and its scenes, property wrappers, App Intents, OptionSets and RawRepresentable structs (declared so, or made so in an extension, which the copy step's scan reports), whose `init(rawValue:)` is the memberwise one, BitwiseCopyable structs, which can hold no spare, and every struct in an
app any of whose own files lays memory out by hand (vertex data, a value's or an array's own bytes; the struct read as
bytes may be declared in another; Lamp's own files always do and are told apart by name, `-own=`). When
the only difference in layout is new stored properties in such types, `LiveSlots.fit` rewrites each one-line
declaration in the live copy into a computed property kept in a spare, found by the compiler's own
source ranges (`SwiftSource.declarations`, from the same `-dump-ast` as the layout), so however it's written (with
attributes on lines above, in a `var a = 1, b = 2` list, in a type written on one line) it's replaced exactly, with
no reading of the text (a view's `$name` becomes a binding to its box, in the view
and in every extension of it, but not in a type declared inside it, whose `$name` is its own); a view's `let` with a
literal, or a `var` with one in a view made outside bodies, becomes a computed property returning it, and the change is compiled again and checked as usual. Being stored, a spare is observed like any property, so
views redraw. A value set is read back as set, nil included: a spare tells "set to nil" from "never set" by holding an entry at
all (`LampSpare.has`, a class's non-nil `LampSpare?`, the state box's stored entry), since a nil boxed as `Any`
doesn't cast back. A class's starting value that isn't a literal (`.now`, a call) is worked out on the first read and kept;
a struct can't keep one from a read, so its new property needs a starting value that comes out the same every time (a
literal (by the compiler's word, however it's spelt: `"a\nb"`, `0xFF`), an empty collection, one of the app's own
enum's cases, or a constant of the system's named one by one (`.zero`, `.blue`: `LiveSlots.steadyMembers`, never where the app
names a type or an alias the same, `Declarations.ownTypeNames`), judged again each time the property is put back;
anything else, or a different one later, reopens the app, since the spare compares a value that never set the
property by the starting value it was taken in with); a class's property written `nonisolated` reopens it too, since
the spare places take the class's actor. `@State` is read in both forms the compiler has given it: `_name: State<T>`, and
`__name: LazyState<T>` where it is a macro. Cases added at the end of an enum whose cases carry nothing need no
spare: its values keep their size (`LiveSlots.casesAdded`). Only while nothing the app keeps holds it but as itself or
in a plain collection (an array, set or dictionary through any depth) or a view's state or binding: Swift uses the numbers after the last case for `nil` in an optional of it and for other enums'
cases that carry it, which a new case would take over. That's looked for in every stored field, static and global of
the new code (`LiveReload.enumsHeld`), before the change goes in; a property added while the app was open keeps its value in a spare as any value, under the enum's metadata, which
stays the app's, so it's held to the same plain forms as a field; and a value type
that carries the enum by value (a struct with a field of it, an enum with a payload of it) is held to the same plain
forms, since its own optional and payload cases borrow the enum's numbers, unless it has a spare of Lamp's, whose
`Any?` gives Swift more; an app that keeps
values of any type reopens instead, since one could hide there: `Any`, `AnyObject` (a value is boxed for it),
`AnyHashable`, a `NavigationPath` or one of Foundation's collections, `any P` for a protocol the app doesn't declare (the standard wrappers conform to those on their own,
so `any Collection` may hold `[Mood?]`), or `any P` for one of the app's own when the enum conforms to P, directly,
in an extension or through a protocol that inherits P, or an extension of a system type does and could wrap it
(`LiveReload.existential`); a model keeping `any Shape` is no reason to reopen for a Mood that is no Shape. When an enum
grew, every file of the app's is compiled again, so no code of the open app's meets a case it never knew (a switch over
it, or printing it, reads past what its metadata describes); code already running keeps the version it started with (not what the `@State` macro writes, whose closure SwiftUI calls only to make a new view's first value),
so the sources the open app runs, and those of every change that went in since it opened (`.lamp/live/old-code.txt`,
`LiveReload.recordOldCode`: what an earlier change's code started may still be running), are read for a switch over the
enum, or an interpolation of it, in a loop (one that may never end), or in an escaping closure that outlives a draw (one made outside a view's body or a
member returning a view, or one a body hands to anything but SwiftUI, a Timer's, a dispatch queue's, the app's own, or
sets into a property or gives as a property's value; a Button's action is made again at the next draw; one handed to a view of the app's own counts as kept,
since its initializer may keep it anywhere), an async
closure or an async function (`LiveReload.enumsMetByOldCode`), and the app reopens when there is one. The enum's description and value witnesses stay the change's
own (`LiveReload.compile(keep:)`, renamed `$lampown` so `LampLive` binds every later change to them), since the app's
don't know the new cases; its metadata stays the app's, so a value boxed before the change and one boxed after are the
same type to a cast, and the app's metadata is pointed at the change's description and value witnesses (`LampLive.load`,
two pointers), so the app's field records, the runtime's asks (printing, Codable, hashing, a cast) and code compiled
before still read the new cases. A constant made from the enum (`Mood.allCases`, or `allCases` written inside it, or through a typealias: the compiler's own
`allCases` is recorded as a use), or by code that names it (`countMoods()`), is remade like one whose
text changed (`LiveSlots.constants(naming:)`; one holding an object isn't, the object being state like any other); a stored static, global or lazy property made so reopens the app, since
the open app made it once (`LiveSlots.stored(naming:)`). SwiftUI keeps the last value a few of its modifiers were given
(`onChange(of:)`, `task(id:)`, `animation(_:value:)`, `id`, `tag`), made by the open app's code: an optional of the
enum given to one reopens the app, since its nil would read as the new case. What old code may still be doing is read more widely than a
switch or an interpolation: any value of the enum's type, or of a type holding it by value (`LiveReload.holders`),
that running code has in hand reopens the app, since an old frame reads it by the layout it was compiled with (an
optional of it, a comparison, a hash, a cast); a class is no such holder (its field keeps its layout, and old code
reading it is caught as a use of the enum itself), nor a view, whose value lives in SwiftUI's graph, nor a key path
passed as a function (`.map(\.name)`), an escaping closure the compiler makes for that call alone. A generic enum
reopens the app when it grows: the runtime lays its values out for each type it's used at, and there is no one
metadata to point at the change's; a private enum's symbols carry the compiler's discriminator, which `LiveObject.isKept` allows for, and where the
compiler writes a word of the name by its place (`Pet` and `PetMood` are `3Pet0A4MoodO`) the enum's own descriptor
gives its spelling, found by demangling (`LiveObject.demangledType`). What a grown enum is checked against (the layout with statics and globals, `held`)
and what old code does come from the analyses already made (`Analyses.Entry`), not a further run of the compiler.
A property in a Codable struct's `CodingKeys`, written or made by the compiler, would drop out of what's encoded and
decoded once moved into a spare, so the struct's coding is written out beside it in the live copy, as the compiler makes
it (`LiveSlots.codingExtensions`: every stored property of the new code's, the moved ones set after the rest, under the
CodingKeys the code writes or by name, an optional decoded if present, a `let` with a starting value encoded and never
decoded), only the halves the type's own code doesn't write; the CodingKeys the compiler made, which only that coding used,
are no enum that grew. A class's (its decoding initializer can only be written in the class itself) or a generic
struct's (Codable only where its parameters are) reopens the app, and so does a written CodingKeys of one case gaining a
second, since a one-case enum takes no room. One the type codes itself and leaves out goes in as any property; where its own decoder reads the keys Swift makes,
which Swift stops making once the other half is written here, they're written too with the cases the compiler would
have given them, and only while their number holds (the room their values take). One set in an initializer the type
writes itself (`SwiftSource.Declarations.assigned`) reopens the app: the open app's values were made by the old one and
would read the property's starting value where a fresh launch's have what the new one sets. Except in a decoder whose
value for a missing key is that starting value (`decodeIfPresent(…) ?? 0` for `= 0`, `LiveSlots.decodesToStart`): the open
app's values were decoded from data saved before the property existed. One with observers, `lazy`, or held weakly or
unowned, or `@ObservationIgnored` (a spare is observed), or a `@Published` one whose `$name` publisher is used
anywhere in the app, or
one with no starting value, or a struct's whose starting value isn't the same every time, reopens the app; `LiveSlots.fitting` says
which, and the chat's detail carries that reason beside the layout's, with the
copy step's own names said as what they are (`LiveReload.readable`). A view's `$name`, its state's binding, becomes
its box's only within that view's own declaration (`SwiftSource.Declarations.types`), since another view in the
file may have state of the same name. Which property is in which spare
(`.lamp/live/slots.json`) is put back into each fresh copy (they come back as additions, and `LiveSlots.fit` puts
them in the same places) until the app is installed again; a property taken out of the code has its place retired
once the change is in (`LiveSlots.retire`), since the place still holds its value (a Hashable struct's reopens the
app instead, `LiveSlots.retiredFromValue`: the spare counts what it holds in `==` and `hash`, so the open app's sets
holding such values would lose them), and its name is sent with the change
for the app to set aside (`LampSpare.retired`: what it left neither reads nor counts in `==` or `hash`), and a name
brought back gets a place of its own (a class's under a new index, a struct's or view's under its key, the type and
name numbered by `Slot.generation`, `LiveSlots.spareKey`); what `fit` planned (the places, the constants remade) is written down only once the change is in
(`LiveSlots.commit`), so a change refused leaves no record of places it never took: the whole build compiles the plain copy, keeps what it compiled in `.lamp/live/built` once it has built (a failed
build's sources would name code no app runs), and what else went into it as it started (`LiveReload.noteBuilt`), and that's what the open app runs
once it's installed (`LiveReload.markRunning(from:)`). A spare never reaches saved data: `LampSpare` encodes as nothing, and a computed property isn't encoded. Nor
a description: a struct given a spare is made CustomReflectable in its own header (`LampSpare.mirror`, from the
runtime's own reading of its fields), so `"\(item)"` and `dump` leave the spare out and show what it keeps after the
struct's own fields; one with a mirror of its own keeps that. If spares ever keep an app from building, it's built again without
them (`LiveSlots.giveUp`, `.lamp/live/no-spares`), so the agent only sees errors in its own code. Whether they were the
cause is judged by that build, not by the compiler's words, which print the lines around an error, spares included: when
it fails as well the errors were the agent's, and the give-up is taken back (`LiveSlots.takeBack`, in
`Store.buildSparing`), or every later change would wait for Reload. The marker, like `no-final`, counts the whole live builds since and goes at the first one from the tenth on made while the app isn't open (`LiveSlots.expireGiveUps`; while it's open, its next changes would be judged against code without the step), so the step is tried
again now and then at the cost of one failed build when it still breaks.

A constant (a static or global `let`) whose value changes would otherwise not change at all: the open app made its
value once and keeps it in storage the new code goes on reading. So each constant's value is part of the kept layout
as a digest (`SwiftSource.constantEntries`, not compared as what a type holds), and one that changed is rewritten in
the live copy into a computed property that makes the new value once and keeps it (`nonisolated` in a type, as the
`let` was, so readers outside a `@MainActor` type still compile, unless it names an actor of its own; one whose value
then can't be made there, from the type's own main-actor code, reopens the app with that reason) (`LampConstants`, by name and
value; `LiveSlots.changedConstants`, `rewriteConstant`). The first time a constant is rewritten every file is
compiled again, so every reader goes through it; it stays rewritten until the app is installed again. One that can
hold an object needs the app reopened instead (it waits for Reload, as above), since a second object would split the
app's state: one of the app's own classes, and anything that isn't a plain value of Swift's or SwiftUI's
(`holdsObject`), so a Lamp building block such as `LampAPI.own(…)` or a system class too. A system type the code can't settle (`Font.Design` in a theme's typeface: what it holds isn't public) is asked of the system before the constant is judged (`LiveReload.plainTypes`): a small program naming it by the module and name the compiler resolved it to (`SwiftUICore.Font.Design`, `Declarations.systemResolved`), compiled with the app's SDK and run in the app's sandbox on this Mac, says whether it holds any reference (`_isPOD`); only a constant that changed asks, never about the app's own classes or a name the compiler resolved to one of the app's declarations anywhere (`ownResolved`, the widget's shared code included), each type once per macOS version (`plain-types.json` in Lamp's folder), asked ahead when the app opens (`LiveReload.warm`, for every constant the app has, once for the sources the open app runs on this macOS, `plain-asked.txt`, whether its layout was saved already or not) so no change waits for the compile, and the refusal names the field. A pointer (`OpaquePointer`, `Unsafe…Pointer`, `ObjectIdentifier`, `Unmanaged`; `pointerValues`) is never plain, though its bytes are: it names what the open app opened or made once (a C library's handle), which a new value would make twice. A tuple's labels and Lamp's
own spare places in a struct name no type of their own, so they don't count. A constant declared in one list with others (`let a = 1, b = 2`) isn't rewritten, and the reason says so. A
constant's digest also takes in what its starting value calls: the text of every declaration of the app's it calls,
as far down as that goes (`SwiftSource.calledText`), so one made by `build()` or from a computed `width` is given its
new value when that code changes, and its kept value is named by that text too, so the next change to it is another
value again. It follows an initializer or a case into its type's stored properties' starting values and
its cases (`calledText(members:)`), so a constant made by `Settings()` changes with a default. One that can hold an
object isn't remade (`static let shared = Store()`): the object is the app's state, kept like every other. A constant
read by what runs only at launch (its types and their extensions), there or through what it calls
(`SwiftSource.reaches`), reopens the app, and so does
a constant of the app's own option set or raw-value type, which the open app's values of it are made of.
So does a key's `defaultValue` (an environment value's, a preference's, computed too, in the type or an extension of it, with what its getter calls) or an `@Entry` value's, which
SwiftUI reads once and keeps. A view's plain property given another starting value (`let columns = 2` to `3`, an
`@AppStorage` default, or what it's made by: `initialColumns()`; `Group.defaults`, digested with the code it calls) reopens the app when the view is made once (the window's root, a hosting
view's), which keeps what it started as; one a body makes is made again. A case's raw value is a value, never read
as a type a constant holds. A `#Preview`'s code, and the type its macro writes, is no use of anything and no old code.

A stored static or global `var` is made once too, the first time it's read, so a new starting value for one can't
show without reopening, and whether it seemed to would depend on whether it had been read: its starting value and its type are part of the layout as a digest as well (`LiveReload.Group.stored`), and one that changed reopens the app, as does one whose starting value calls code that changed, unless it holds one
of the app's objects (an initializer's type isn't followed into its members: the value is state, kept as an object's
fields are); a lazy property's is held the same way, since each object made it once. A static or global gone
from `let` to `var` or back reopens it too. So does a type's own `hash(into:)` changing, being written or taken away,
or what it reads changing (a constant, a helper, as far down as that goes), an app's own hash of a system type
included (`LiveReload.Group.hash`): the sets and dictionaries the open app keeps put each value
where the old one said, and a lookup by the new one looks elsewhere.

A view's stored parameter that changes from one plain value to another of the same size (`heat: Int?` to `Double?`,
`LiveReload.viewRetyped`, `plainLayout`) goes in too, with the app's own metadata: a view's value lives only until its
next draw, when its parent makes it again with the new code, and two such fields copy, destroy and compare alike, so
the open app's value witnesses do right by either (a `Bool`, a `Bool?` and a one-byte number are three layouts:
their spare bit patterns, which Swift uses for `nil`, differ). Only when every place the app's code makes one is a
view's own `var body` or code only bodies call (`LiveReload.madeOutsideBodies`), not an action closure in one
(`.onAppear { openPanel() }`, which runs once and hands what it made on; `Declarations.actions`): what a modifier's or a style's
body, a hosting view's root or a stored property made is kept as the open app laid it out. Not a name the app declares itself (`typealias Date = String`), in
either layout, nor a view something holds by value, through a typealias too (it's laid out in that), nor its wrappers
(`State`, a binding, the environment, which SwiftUI keeps), nor one the App's scenes make, there or in code they call
(`SwiftSource.reached`), never made again, nor one that code still running has in hand (`retypedViews` in `attempt`, read like a grown enum's old code);
every file is compiled again so every caller makes it the new way.

**The live cases** (`Tests/LiveCases`, run by `LiveCasesTests`) are the record of which side each kind of change
lands on: every case found by a review round, as an app's sources, one `afterN/` folder per change and `expect.txt`
with the verdicts Lamp gave and what the app printed. The test runs each through Lamp's own pipeline (`verdict`,
`put`, with the library handed to a process built from the case instead of an open app, `LiveReload.deliver`), so
it tries the code as Lamp runs it, not a copy. The process runs alongside: its `reload(n)` waits for the n-th
change, loads the library when it's delivered and answers, which is what `put` commits on, and after a refused
change it's ended, rebuilt from the new code and started again, as Reload does (a `keep-open` file in the case
says the person kept the app open instead, so the next change is judged against the code still running). Each case costs a build and a few compiles, so they run only when
asked (`LAMP_LIVE_CASES=1 swift test --filter LiveCasesTests`, a few minutes with the cases running several at once, or `LAMP_LIVE_CASES=name,name` for some), and
`LAMP_LIVE_CASES_RECORD=1` writes the expectations instead of checking them: after a change to anything above,
run them all, read every difference as a change of behavior (the first line of each print says what's wanted),
and record only what's meant. A new kind of change gets a case: its sources, its edits, and a print of what the
app should see, with what's wanted in the print's words. One case, `r23-real-app`, is shaped like Lamp's own scaffold (an App that makes the
window's view and holds the model, child views, a model, a theme) and runs the ten edits agents make most, one after
another, each wanted in live: a change that sends any of them to Reload is a regression however narrow its own case.

Code already running keeps the version it started with (a closure given to a Timer, a loop in a Task, an observer):
calls go to new code, but a closure already handed out is the old one. `Agent.liveNote` asks for loops and timers
to call a method of the app's each time, so a change to that method goes in.

Where a class's fields are is sometimes worked out at run time (a subclass, or fields after a system type such as
an `@Observable` class's registrar), kept in a global for each field that the app fills in. A library has its own
copies, which nothing fills in, so `LampLive` copies the app's values into each library as it loads
(`takeFieldOffsets`), asking for the class's metadata first when the app hasn't worked it out yet; a class an earlier
change brought takes that change's values, since it is that change's class from then on (`kept`). A field the app
has under no such name (a new class's, or a private one whose code moved to another file, since a private name
carries its file's) is laid out by the library itself, which does it as the app did for the same class. That waits
until the library's references to its own types are bound (`rebind`), since its accessor reads the class's description
through them, and comes before the app's calls are pointed at the new code.

A stored property taken out of a type the open app has (a view's `@State`, a parameter, a model's property, the old
half of a rename) is kept in the live copy as a private field nothing reads, at its place (`LiveSlots.keptFields`):
the type then holds what the open app's values hold, so their other fields keep their values, and the new code goes
on without it. It's given its type's empty value (or an enum of the app's first case), never read, and being private
with a value it's no argument of the initializer Swift makes; a wrapper's storage is kept with its wrapper (`@State`,
`@Published`, an `@Observable` class's tracked property). It's put back at each change until the app reopens. Not in
an Equatable, Hashable, Comparable or Codable type, whose own code reads every field, the kept one included; nor where
the new code uses the name for something else, a field held `unowned`, another wrapper's, or a type with no value Lamp
can write: those reopen the app, saying which.

A file taken away doesn't reopen the app: its code stays in the open app, which the new code no longer calls, and a
type it declared that something still holds shows as that holder changing. A type taken away is therefore no
reason to reopen by itself (`layoutProblem`), but its layout is kept with the open app's until it reopens, so a type
brought back under the same name is held to what it was. Only removing the App's file or Lamp's own reopens. A
removal can change what an unchanged caller means (a deleted method that stood in for a protocol's default), so
every file but Lamp's (the App's included, for what else its file holds) is compiled again and every call goes to
code compiled without it.

