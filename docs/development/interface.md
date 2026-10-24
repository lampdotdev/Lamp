# Interface

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

Lamp's screens drift as features land: each adds its own explanation, warning or status, and an earlier
tidy-up is undone. Before adding to any of them (Settings, the welcome, the chat and its cards, the build
card), check:

- **Is it a choice, an action, or the fix for one?** Screens are for doing, not explaining. Labels say what
  something does; a note is only for what the person must accept to decide (an install, a permission, a
  cost), in a sentence or two. No footers, captions, or badges summing up what something is used for.
- **Can it be used now?** A control appears once it does something. Until then, its place shows why not
  and the one thing that fixes it (Not Ready, a gray line, a Download or Sign In… button): no menu of
  models that can't run, no field or switch that won't take effect yet. A menu lists only what works now,
  and one with a single option is plain text. Disabled is for a moment's state in a standard control
  (Remove with nothing selected), not for something that needs setting up first.
- **Does it ever contradict itself?** What's shown is what Lamp does: a menu shows the choice actually
  used, even when the saved one can't be. When all is well, say nothing; a problem is one orange mark and
  one gray line with its fix. Never a choice on screen with words under it saying it won't work.
- **Is this its only home?** Show a thing where it's chosen or changed, and from anywhere else link there
  rather than repeat it: repeats drift from what Lamp actually does. An experiment and its settings live in
  Settings → Experimental, under its checkbox; a feature leaving Experimental takes its settings to the tab
  whose job they are.
- **Does structure carry the meaning?** Related things share a group. What depends on something sits
  indented under it and shows only while that's on. Details for the curious (paths, versions) go in `.help`.
- **A card's buttons are one size**: the size Allow and Don't Allow are (`.cardButtons()`), on every card in both
  chats, the main one prominent; never the small size, which in the wand's narrow panel was too slight to find.
  Where they don't fit beside a card's words they go under them (`ChatLook.OfferCard`).
- **Same words for the same thing**, in every screen, Help and errors. Product names come from one place
  (`Engine.title`: "ChatGPT", "Claude": what people call them, not the coding tools' names), never a literal.

### The gallery

Lamp Dev has a gallery (Window → Gallery, ⌥⇧⌘G; `Gallery.swift`): each of the chat's cards in every state it
can be in, drawn from made-up values at the chat's width and the wand panel's, light and dark. A card is drawn by
a view that takes plain values (`AskCardView`), and the view that reads `Store` only finds those
values and passes them in, so the gallery shows exactly what people see. Keep it that way: a new card, a new
state of one (a layout, a shape saved by an earlier Lamp, a button that shows only sometimes) or a fix to how one
lays out gets its entry in `Gallery.entries` in the same change, and is looked at there before the PR. A card
that reads `Store` in its drawing can't be listed: split it first.

### Settings

Each tab has one job: **Building**, how Lamp builds apps; **Apps**, what apps use while they run; **AI
Providers**, the four providers in one list, with their sign-ins, key and downloads (other tabs' menus
end in "Configure providers…", which leads here); **Memory**, what Lamp remembers and whether it does; **Experimental**, what the Lamp team is still working on, a tab that is there only while there is an experiment to show (`ExperimentalSettings.hasAny`; now Apps in Chrome, in Lamp Dev only).
Lay out with the shared pieces in `Setup.swift`, and extend one rather than lay out by hand:
`SettingsCheckboxes` (on/off is a checkbox, box first, never a switch), `.underCheckbox()`,
`.checkboxNote(…)`, `NotReadyBadge`, `NotReadyRow`, `CapabilityNote` (the gray why-and-fix under Not Ready),
`ImageModelRow`, and `.settingsPane()` at the end of each tab. A PR that adds to Settings says which tab, and why the option needs to exist at all.

### The app's info panel

The info panel (`AppInfoView`, ⓘ in an app's toolbar) shows facts about one app; it chooses nothing. What
belongs: what the app has cost, what answers its AI (from `AppAI.resolve`, so it's what really answers),
how Lamp builds it, and where it lives. What doesn't: menus, switches, explanations, upgrade offers, or
anything that's the same for every app and already in Settings.

- **Read-only.** A thing that can be changed is changed in Settings: each section ends in one small button
  that opens the tab where it's chosen ("Configure Providers…", "Building Settings…"). The only exception is
  undoing what an app was left with by an earlier Lamp ("Use Settings' Choices", shown only when there is
  something to undo).
- **Facts, not notes.** A row is a label and its value. Nothing answers: `NotReadyBadge` as the value, with
  no sentence under it; the fix is in Settings, one button away. No footers or captions.
- **Fit the width.** Rows are `InfoRow`: the value beside its label when it fits, else under it, both
  left-aligned. Keep values short (`AppInfoView.short`), and keep the panel's width (`inspectorColumnWidth`)
  wide enough that most rows fit on one line.
- **Current.** The panel observes whatever its rows read (Settings, keys, the app's own choices, the models
  on this Mac), so a value never outlives what it describes.

