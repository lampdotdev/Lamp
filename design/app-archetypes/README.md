# What kind of app is this?

Lamp's apps should feel like Apple made them, never like something an AI put together. But Apple's own
apps aren't all alike: Notes, Weather, Breathe and Freeform are all native and look nothing like each
other. What an app is for decides how it should look, so the agent first decides what kind of app it's
building, and then follows that kind's defaults. The person makes none of these choices. They get an app
that already looks right, and they change it by saying so.

The rules the agent reads are `Agent.Rules.kinds(mac:)`, just before the base design (`macDesign` /
`iPhoneDesign`), and `artRules` for `make_art`. This file is the reasoning behind them: change the two
together.

## How the agent chooses

- **The person's words come first.** If the first request describes a look or a mood ("retro", "minimal",
  "like a Game Boy", "cozy"), or comes with a mockup, build that. Use an archetype only for what they
  didn't say: a "cozy" habit tracker still gets the companion structure, in their style.
- **Otherwise pick the closest archetype**, and when in doubt pick one anyway. A guess the person can
  correct is better than no direction at all.
- **Pick once and remember it.** The choice is the first line of APP.md (`Kind: companion`), which every
  engine reads and the agent keeps current, so every later turn and rebuild keeps
  the same voice. It changes only when the person asks ("make it more playful", "make it more serious")
  or the app grows into another kind. A change in what the app is about isn't a change of kind: see below.
- **Never ask.** It isn't a question for the person, and they never see the archetype's name.

## The archetypes

The **tool** is today's design rules, unchanged. The others start from those rules and change only what
their bullets say, so everything else (semantic text styles, Dynamic Type, safe areas, standard menus and
shortcuts, ContentUnavailableView) stays as it is.

### Tool / organizer
Notes, inventory, a CRM, lists, logs: the person keeps and finds things.
- Today's `macDesign` / `iPhoneDesign` rules.
- Dense and calm: system colors, the accent color, SF Symbols. No illustration.
- The thing it's measured on is how quickly you can find, add and change things.

### Companion / ritual
Water, pomodoro, habits, mood, plants, breathing: a small habit you come back to many times a day.
- One main screen, built around a single image of where you are now (the glass, the timer, the plant).
  No sidebar, no list as the home screen; history is one tap away.
- That image is generated art (see below), not shapes drawn in code. It changes with the state: fill, grow
  or move it in SwiftUI rather than generating a picture for every state.
- A palette of its own: two or three colors that suit the subject, defined once as named colors with light
  and dark versions. System colors are still used for text and controls.
- Big, friendly type for the one number that matters (`.largeTitle` and up, `.rounded` design).
- The main action is one large, obvious button or tap on the image, with a haptic (iPhone) and a small
  spring animation. Something small and nice happens when a goal is met, and nothing nags.
- Warm, short copy with a little personality ("Nice. Two to go."). Never cute at the cost of clarity.
- It lives where the habit happens: notifications for reminders, and on Mac a menu bar item showing the
  state (the time left, the count). Widgets and Live Activities would belong here too, once Lamp can
  build extensions.
- One first screen is allowed when the app can't work without a choice (a daily goal), with a sensible
  default already filled in. Never a tour.

### Collection / showcase
Recipes, books, wines, trips, a record collection: the things are the point and they're nice to look at.
- Pictures lead: an adaptive grid of cards (`LazyVGrid`), large images, titles under them. A list view
  as an option, not the default.
- The detail view is a full page with a large hero image at the top, like Music's album or TV's show
  pages, and the facts below it.
- Each item gets a picture: the person's own photo, or else one generated in the house style, so the grid
  is never a wall of gray placeholders.
- Search, sort and filter as in Photos (a toolbar menu, scopes), not as a form.

### Glanceable / dashboard
Weather, money, fitness totals, a server's status: you look, understand and leave.
- The answer first: the one or two numbers that matter, large, at the top. Details further down.
- Swift Charts for anything over time, with the style kept simple: no grid clutter, highlight the latest
  point, values labeled where they matter.
- Color carries meaning (good, warning, bad) and nothing else.
- On Mac, a menu bar item showing the main number when it's something you check often (and a widget,
  once Lamp can build extensions).
- No art. Some ambient color from the state (a soft gradient behind the main number) is fine.

### Canvas / editor
Drawing, diagrams, page layout, long writing: the person makes a thing.
- Minimal UI: the content is front and center and fills the window. Everything else gets out of its way.
- A larger toolbar (labels under the icons where there's room) holds the
  tools, so there's no tool palette drawn inside the canvas. Settings for the selection go in an
  inspector (`.inspector`), hidden when nothing is selected.
- Proper window management: one window per document (DocumentGroup), tabs, full screen, the window's
  size and position restored, and a full-screen or focus mode that hides the toolbar and inspector.
- Standard document behavior: autosave, undo for everything, export.
- Direct manipulation (drag, resize, pinch) with a menu command or button for each gesture.
- No art: the person's work is the only thing to look at.

### Background utility
A clipboard history, automations, a converter that watches a folder: it works while you do other things.
- On Mac, a menu bar item and a Settings window. No main window unless it has something to show.
- When the app has one main on/off action (pause syncing, keep awake, watch the folder), clicking the
  icon does it. The icon has two clearly different states (`cup.and.saucer` / `cup.and.saucer.fill`,
  say), and right-clicking shows the menu.
- When it hasn't, clicking the icon shows the menu.
- Prefer a real menu (recent items, toggles as checkmarks, Settings…, Quit) over a custom panel. A
  panel is for what a menu can't do: a search field over a long history, a preview, a slider you
  watch while dragging.
- On iPhone, App Intents (Shortcuts and Siri) and the share sheet where possible, and a single screen of
  settings and recent activity.
- Quiet: a notification only when something needs the person.

### Game / toy
Anything played rather than used.
- Fully custom: no standard chrome during play. Menus (pause, settings, scores) are standard SwiftUI.
- SpriteKit for anything with physics or many moving pieces; SwiftUI animation for the simplest.
- Sprites, backgrounds and characters are generated art in one consistent style, with sound and haptics.
- Scores are kept on the device.

## When the subject changes, the theme follows

The kind is an app's structure: a grid, one picture of where you are now, a sidebar. Its theme is the part of
its look that comes from what it's about. Hot Shelf's pink wall, chilies and pepper ratings are hot sauce;
a campfire songbook's taped index cards, embers and lantern vignettes are the campfire; Wedding Words' terracotta is
Naples. Lamp is for changing the apps people have, and the most common big change is the subject: "make it for
my wines". Someone who asks that expects a wine cellar, not a pink wall of chilies holding wine bottles, and they
shouldn't have to ask a second time. So when a request changes what an app is about, the agent changes the theme
with it, in the same request and without asking, whoever made the app: one it built, a starter, or a shared
copy someone is working from. The rule is `Agent.Rules.theme`, at the end of the kinds.

- **What follows**: the palette, backgrounds and motifs, the style pictures are drawn in and the pictures, the
  lettering, the symbols things are rated or counted with, the words and their tone, the example content, and the
  icon. icon.json first, since `make_art` takes its colors from the icon's tint.
- **As particular as before**: the new look is as specific to the new subject as the old one was to the old
  subject, never a plainer version of the old one.
- **What stays**: the kind and its structure, whatever still fits the new subject (a wooden bookcase holds
  records too), what the person chose or styled themselves, their own items, and their saved data (raw values
  are kept and old ones mapped to the new).
- **How much**: as much as the look was made of the subject. A tool in system colors and SF Symbols changes its
  words and symbols; a themed app gets a new theme. A change within the same subject (a wishlist, a new screen)
  changes nothing visual.
- **Watched, not waited for**: a re-theme changes much of what the person sees, so it's built in passes.

APP.md's `Look:` line (`Agent.Rules.appMd`) says what an app's look is made of and where, so the turn that
changes the subject knows what to change. The themed starters carry one written by hand. An app without one is
read from its code.

| Change | What follows |
|---|---|
| Hot Shelf: hot sauce to wine | A cellar instead of the pink wall and chilies, labels redrawn in a style for wine, glasses or grapes instead of peppers, "What are we pouring tonight?", grape varieties for flavour families, wine examples, a wine bottle icon |
| A campfire songbook: guitar to jazz piano standards | A smoky club at night instead of the campfire: lamplight for embers, a piano and a martini among the vignettes, chord charts for piano, a new icon |
| Wedding Words: a wedding in Naples to a friend's wedding in Kyoto | Japanese and new people to talk to, colors and a tone of Kyoto instead of terracotta, a new icon |
| Pet: a cat to a thirsty cactus | The figure, its colors, what it eats and its words, a cactus icon |
| Shelves: books to vinyl | Sleeves instead of spines and new words; the wooden shelf stays |
| Transcripts: meetings to podcast interviews | Words only: it's a tool |
| Hot Shelf: add a wishlist of sauces | Nothing visual: the subject didn't change |

## Pictures in apps

`make_art` (all three engines: `lamp-tools.json`, pi's extension, `Store.mcp`) paints a picture into the
app's `Assets/` folder, which is bundled with the app, and shows it to the agent. It reuses the icon
pipeline (`Icons.swift`), so an app's art matches its icon:

- **The same words.** `Icons.appArtPrompt` asks for what `artPrompt` asks of an icon's object (Apple's
  icon style, rounded forms, soft gradients, light from above), with colors that go with the icon's
  `tint`. A whole `scene` keeps the style and fills the frame.
- **The same model and cut-out.** The icon's model (Settings → Building) paints it, and a single object
  is lifted off its background with Vision (`cutOut`), so it sits on any background.
- **The agent is the judge.** Icons make three candidates and have a vision model pick one; in-app art is
  one picture per call, because the agent sees it, knows what the screen needs, and calls again with a
  better subject when it's wrong. No reference image either: sending the icon along tempts the model to
  draw the icon's object again, and the shared prompt and tint already make a set.
- **Cost.** What it costs counts towards building the app (`agentCost`). The rule tells the agent to make
  only what the design needs and to animate one picture rather than paint one per state.
- **Where it can't run.** With nothing on this Mac that makes pictures, Lamp offers the setup card itself
  and tells the agent to use SF Symbols in the app's palette.

## Menu bar apps

`LampMenuBar` has three forms, all with the same safety nets (the window that stands in for a hidden icon,
the Dock icon while a window is open):

- **A panel** of the app's own, as before: `LampMenuBar("Focus Timer", systemImage: "timer") { PanelView() }`.
- **A menu:** `LampMenuBar(menu: "Clipboard", systemImage: "list.clipboard") { items }`, the items being
  SwiftUI Buttons, Toggles, Pickers, Menus and Dividers, shown as a real menu. Settings… and Quit are
  added at the end so no app forgets them (`settings: false` for an app with no Settings scene).
- **A switch:** `LampMenuBar("Keep Awake", isOn: $model.awake, on: "cup.and.saucer.fill", off:
  "cup.and.saucer") { items }`. A click flips it and the icon follows; a right-click or control-click
  shows the menu, which starts with the same switch. SwiftUI gives the icon its menu, which would open on
  every click, so `LampMenuBar` takes the menu off the icon and shows it only for the right-click.
- With the icon hidden, a menu's items open in a window as buttons and checkboxes.
- `use_app`'s `bar_icon` reads out a switch and its menu, and `item: "click"` clicks the icon.

## Size in the prompt

At five to fifteen bullets each, the archetypes add about 10k characters (about 2.5k tokens) to a system
prompt of about 35k characters today. The system prompt is cached between requests for every engine, so
that costs little, and it all goes in the prompt. It's worth revisiting only if the archetypes grow well
past this, at which point each can move to a file the agent reads once it has picked one.

## Trying it

The same prompts before and after a change, each built once on Mac and once on iPhone. Look for whether the
archetype was the right one, whether the result looks native and specific to its subject, and whether a
style the person asked for won over the archetype.

| Prompt | Expected |
|---|---|
| An app that reminds me to drink water | Companion |
| A pomodoro timer | Companion |
| Track my houseplants and when to water them | Companion (one plant) or collection (many): either is fine |
| A recipe box | Collection |
| Keep track of the books I've read | Collection |
| Show my spending this month from a CSV | Dashboard |
| A clipboard history | Utility |
| A simple drawing app for my kid | Canvas, with a playful touch |
| Inventory for my small shop | Tool |
| A pomodoro timer that looks like a 1970s kitchen timer | The person's style, with the companion structure |
| A snake game | Game |

And for the theme rule, a change to an app that exists (a copy, never the person's own), each expecting the
row of the table above: Hot Shelf to wine, a campfire songbook to jazz piano, Wedding Words to Kyoto, Pet to a cactus,
Transcripts to podcasts and Hot Shelf with a wishlist.
| A minimal, black and white habit tracker | The person's style: no generated art |
