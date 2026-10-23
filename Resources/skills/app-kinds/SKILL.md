---
name: app-kinds
description: How each kind of app (tool, companion, collection, dashboard, canvas, utility, game or toy) is laid out, looks and talks on a Mac and on iPhone, and on a Mac where the app works - a window, or a utility that works where the person already is. Read before writing a new app or changing an app's kind.
---

# The kinds of app

Everything the person didn't say about the look follows the app's kind; their own direction always wins over it. A
style they gave wins over the kind's look but keeps its structure: a "cozy" water tracker is a companion app, made
cozy. Every kind feels like Apple made it, following the Human Interface Guidelines of the app's platform. Put the
kind in APP.md's first line (`Kind: companion`), and never name kinds to the person.

## On a Mac: where the app works

Before the kind, decide where the app works.

- When the wish acts on something the user already has in front of them in another app (the text they selected, the
  post or message they're writing there, the file or page they're looking at), don't make a window to paste or drop
  it into: make a utility that works where they are. A `LampHotKey` takes the selection: read it from the focused
  element through Accessibility (kAXFocusedUIElementAttribute, then kAXSelectedTextAttribute; `LampPermissions` asks
  for Accessibility), and when that gives nothing, send ⌘C and read the clipboard, putting back what was on it. Show
  the result in a small floating panel that doesn't take focus from their app (an NSPanel with `.nonactivatingPanel`
  at `.floating` level, near the mouse) with the one or two actions that make sense (put it back in place by pasting,
  copy, save), or put it straight back in place when that's what they asked for; the menu bar icon holds the
  settings, where the shortcut can be changed.
- When the wish waits or watches for something (a folder, a time, the calendar, a site, the clipboard), it's a
  utility too: it works in the background and reaches the user with a notification, never a window they must open
  to check. Such a utility declares `{"background": true}` in `capabilities.json` at the app's root: then it opens at
  login and keeps running, and Lamp tells the user so (don't explain it yourself; put Open at Login in its Settings
  so they can turn it off). What runs at a time or every so often uses `LampSchedule`.
- A window is for what the user brings things to and comes back to: writing, collecting, browsing, playing.
- Collecting from wherever the user finds things (recipes from any website, articles, quotes, products) is both: the
  window to keep and find them in, and a way to save from where they are without coming to the window: a hotkey that
  takes the page or selection in front of them (the current tab's address from Safari, Chrome or Arc through
  AppleScript, or the selected text) and saves it with a brief floating confirmation, besides dropping or pasting a
  link.

A menu bar app is written as the menu-bar skill says.

## Tool

Notes, inventory, lists, logs, a CRM: keeping and finding things. The base design in your rules, exactly. Dense and
calm: system colors, the accent color, SF Symbols, no illustration. It's judged on how fast things are found, added
and changed.

## Companion

Water, a timer, habits, mood, a plant, breathing: a small ritual come back to many times a day.

- One main screen built around one picture of where you are now (the glass, the timer, the plant), not a list or a
  sidebar; history is one step away. That picture is art from `make_art`, never shapes drawn in code, and it always
  shows the state: animate it (fill it with a mask, grow, move or scale it), never a static picture beside a progress
  bar.
- A palette of two or three colors that suit the subject, as named colors with light and dark versions; text and
  controls keep system colors. The one number that matters is large (.largeTitle or bigger, .rounded design).
- The main action is one big, obvious button or a tap on the picture, with a spring animation (on iPhone, and a
  haptic: sensoryFeedback); something small and pleasant happens when a goal is met, and nothing nags.
- Short, warm words with a little personality ("Nice. Two to go."), never at the cost of clarity.
- Reminders come as notifications; on a Mac it also shows its state in the menu bar (LampMenuBar with
  `dockIcon: true`, its label the time left or the count).
- One first screen is allowed when the app can't work without a choice (a daily goal), with a sensible default
  filled in; never a tour.

## Collection

Recipes, books, wines, trips, records: things nice to look at. Pictures lead, in an adaptive grid of cards
(LazyVGrid) with large images and titles under them; a list as an option, not the default. The detail is a full page
with a large picture at the top and the facts below, like an album in Music. Every item has a picture: the user's own
photo, or else art from `make_art` for the kind of item, so the grid is never gray placeholders; the empty state
shows some of that art too, so a new app doesn't open on a blank page. Search, sort and filter as Photos does
(toolbar menus, scopes), not as a form.

## Dashboard

Spending, fitness totals, a server's status: look, understand, leave. The one or two numbers that matter come first
and large, details below. Swift Charts for anything over time, kept simple: no grid clutter, the latest point marked,
values labeled where they matter. Color means good, warning or bad and nothing else; a soft gradient from the state
behind the main number is the only decoration. No art. On a Mac, when it's checked often, a menu bar icon shows the
main number.

## Canvas

Drawing, diagrams, layout, long writing: making a thing. A minimal interface with the content front and center.

- On a Mac: a larger toolbar (labels under the icons where there's room) holds the tools, never a palette drawn on
  the canvas; settings for the selection go in an `.inspector`, hidden when nothing is selected. Proper windows:
  DocumentGroup with a window per document, tabs, full screen, and a focus mode that hides the toolbar and inspector.
- On iPhone: the canvas goes edge to edge; tools in a bottom toolbar, settings for the selection in a sheet with
  detents (an inspector on iPad), and a tap on empty canvas hides the chrome. DocumentGroup for documents.

Undo for everything, autosave, export; every gesture (drag, resize, pinch) also has a command or button. No art: the
user's work is the only thing to look at.

## Utility

A clipboard history, automations, a folder watcher: works while you do other things. Quiet: a notification only when
something needs the user.

- On a Mac it lives in the menu bar (LampMenuBar) with a Settings window, and has no main window unless it has
  something to show. When it has one main thing to turn on and off (pause syncing, keep awake, watch the folder), a
  click on the icon does it, the icon shows the state with two clearly different symbols, and a right-click shows the
  menu (LampMenuBar's switch). Otherwise a click shows a menu (LampMenuBar(menu:)). Prefer a menu, with toggles as
  checkmarks, to a panel; a panel only for what a menu can't do (a search field over a long history, a preview, a
  slider you watch while dragging).
- On iPhone it does its work through App Intents (Shortcuts and Siri) and the share sheet wherever it can, and the
  app itself is one screen: its settings and what it did recently.

## Game or toy

Played rather than used: fully custom, with no standard chrome while playing; pause, settings and scores are standard
SwiftUI. 2D games as the 2D rule says, 3D ones in a Mac app with the scene-3d skill where it's offered, SwiftUI
animation for the simplest. Sprites, characters and backgrounds are art from `make_art`, all in one style, with sound
(and haptics on iPhone). Scores are kept on the device.

Sound: a short effect (under a second) for each thing the player does or meets, and music only when it suits, quiet
(0.3 to 0.4) under effects at 0.6 to 0.8. Files the person gave go in Assets/ (.wav, .m4a or .mp3) and play with an
`AVAudioPlayer(contentsOf: LampAssets.url(name)!)` made once and `prepareToPlay()`ed, a few of them for an effect that
overlaps itself; music is one looping (`numberOfLoops = -1`). With no files, make effects in code: one `AVAudioEngine`
started at launch with an `AVAudioPlayerNode`, and each effect a few hundredths of a second of a wave written once into
an `AVAudioPCMBuffer`, with soft ends so it doesn't click. On iPhone set the session to `.ambient`, so the silent switch
mutes the game and the person's own music keeps playing. Settings or the pause menu turn sound and music on and off.
