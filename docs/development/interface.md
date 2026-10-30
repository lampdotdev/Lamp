# Interface

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

Lamp's screens drift as features land: each adds its own explanation, warning or status, and an earlier
tidy-up is undone. Before adding to any of them (Settings, the welcome, the chat and its cards, a first build's
parts), check:

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
- **A card's buttons are one size**: the size Allow and Don't Allow are (`.cardButtons()`), on every card,
  the main one prominent; never the small size, which in the wand's narrow panel was too slight to find.
  Where they don't fit beside a card's words they go under them (`ChatLook.OfferCard`).
- **One set of colors.** The desk, the welcome and the chat draw from `Paper` (LampSidebarKit): ink on warm paper, as
  on lamp.dev, and cream ink on night paper when the Mac is dark (nothing forces either look), and the six stripes only for what's Lamp's own (the welcome's band, a remix's line to its original).
  A new screen takes its colors and its two buttons (`PaperButtonStyle`) from there, never the system's accent.
  The welcome's hello is a SceneKit stage behind its words (`WelcomeScene`; SceneKit, as Lamp still runs on macOS 14):
  the stripes come down a wall and along the floor, three starters float over them as thin rounded slabs that lean a
  little toward the pointer, the words coming in with them, and Get Started moves the camera right as the next step slides in,
  the slabs fading and the stripes kept at the frame's left. With Reduce Motion it's all there at once and still.
- **Same words for the same thing**, in every screen, Help and errors. Product names come from one place
  (`Engine.title`: "ChatGPT", "Claude": what people call them, not the coding tools' names), never a literal.

### The gallery

Lamp Dev has a gallery (Window → Gallery, ⌥⇧⌘G; `Gallery.swift`): each of the chat's cards in every state it
can be in, and whole chats, drawn from made-up values at the chat's widest and narrowest, light and dark. A whole
chat is the shared screen itself (`ChatScreen`, `Gallery.screen`), given a state made from made-up lines the way Lamp
makes one for a wish (`SidebarServer.lines`), so a first build, an approval, a new wish's intro or the bar's Play
look there as they do beside an app and in Lamp's panel. A card is drawn by a view that takes plain values
(`AskCardView`), and what reads `Store` only finds those values and passes them in, so the gallery shows exactly what
people see. Keep it that way: a new card, a new
state of one (a layout, a shape saved by an earlier Lamp, a button that shows only sometimes) or a fix to how one
lays out gets its entry in `Gallery.entries` in the same change, and is looked at there before the PR. A card
that reads `Store` in its drawing can't be listed: split it first.

### Settings

Each tab has one job: **Building**, how Lamp builds apps; **Apps**, what apps use while they run; **AI
Providers**, the four providers in one list, with their sign-ins, key and downloads (other tabs' menus
end in "Configure providers…", which leads here); **Memory**, what Lamp remembers and whether it does, and whether usage counts go to the Lamp team; **Experimental**, what the Lamp team is still working on, a tab that is there only while there is an experiment to show (`ExperimentalSettings.hasAny`; now publishing games as web pages, in Lamp Dev only).
Lay out with the shared pieces in `Setup.swift`, and extend one rather than lay out by hand:
`SettingsCheckboxes` (on/off is a checkbox, box first, never a switch), `.underCheckbox()`,
`.checkboxNote(…)`, `NotReadyBadge`, `NotReadyRow`, `CapabilityNote` (the gray why-and-fix under Not Ready),
`ImageModelRow`, and `.settingsPane()` at the end of each tab. A PR that adds to Settings says which tab, and why the option needs to exist at all.

### The app's info panel

The info panel (Wish Info, ⓘ in the chat's bar: `InfoPanel`, in the chat's place, from the rows of
`AppInfoView.sections`) shows facts about one app; it chooses nothing. What
belongs: what the app has cost, what answers its AI (from `AppAI.resolve`, so it's what really answers),
how Lamp builds it, and where it lives. What doesn't: menus, switches, explanations, upgrade offers, or
anything that's the same for every app and already in Settings.

- **Credits first.** A wish built on someone else's work starts with Credits: what it's based on and its license,
  what else it uses, and the wishes it was remixed from (`AppInfoView.creditsSection`), with one button to the page of
  the work it's based on. A wish with none has no such section. Its buttons act on where the wish came from: Check for
  Updates… (Update from the Original for a starter's copy, which follows the starter this Lamp ships rather than its
  repository), and Start Over for a wish changed since it arrived (its "Your copy" row says so).
- **Read-only.** A thing that can be changed is changed in Settings: each section ends in one small button
  that opens the tab where it's chosen ("Configure Providers…", "Building Settings…"). The only exception is
  undoing what an app was left with by an earlier Lamp ("Use Settings' Choices", shown only when there is
  something to undo).
- **Facts, not notes.** A row is a label and its value. Nothing answers: `NotReadyBadge` as the value, with
  no sentence under it; the fix is in Settings, one button away. No footers or captions.
- **Fit the width.** Rows are a grouped form's labeled values, in a chat as narrow as 320 points. Keep values
  short (`AppInfoView.short`), so most rows fit on one line there.
- **Current.** Lamp makes the rows again with every state it sends while the panel is open, and sends one when
  Settings, a key or the app's own choices change (`SidebarServer.start`), so a value never outlives what it
  describes.

