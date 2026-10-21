# Release notes

What people read in the update window and on the GitHub release. One section per version, newest first,
written for the people who use Lamp: what they can do now, what works better. No PR numbers, handles or
file names. The release workflow takes the section for the tag being released; a version without one gets a
plain "Lamp x.y.z" line.

## 0.16.0

- A new app opens beside its chat as soon as it's started and takes shape there in passes, the layout first, so
  you watch it being built instead of waiting for the end.
- While a change is built, the open app glows softly at its edges, and a band of light crosses it as the change
  goes in. Changes go in faster, and an app that has to restart comes back sooner.
- Lamp asks before restarting an app you have open: a Reload button in its title bar and in the chat puts the
  change in when you're ready.
- The agent describes each step in its own words, and tells you what you can see now rather than what it wrote.
- Drag wishes on the desk into any order, or onto the trash to delete them. A wish being built glows and says
  what it's doing under its name.
- Hot Shelf is a lit studio shelf of real bottles. A starter's suggested changes now show the first time you
  open it, even after an update.
- Approving the agent's commands takes about half the time, and the approval card puts the decision first.
- More changes go into an open app without restarting it, and the ones that can't say why in plainer words.

## 0.15.1

- A new case added to an enum goes into the open app more reliably: everything that reads the enum, including
  printing and saving, sees the new case, lists built from it are built again, and a change that code still
  running couldn't take reopens the app with a sentence saying why.
- More from Lamp's list can be read on a Mac in dark mode, and the wand's flame shows on its blue glass.

## 0.15.0

- Far more changes go into an open app without restarting it: a new method, computed property or stored
  property, a new case in an enum, a new default for an argument, a changed constant, a changed typealias, and
  what an extension adds from Objective-C. When a change can't go in that way, the chat says why in a sentence
  and the app shows a Reload button where it was, which puts the change in when you're ready; Undo, a restore and
  Rebuild & Open wait for it the same way.
- Before a change goes into an app, Lamp keeps a copy of the app's data from just before it, so a change that
  spoils what the app saved can be put right.
- Every app Lamp builds is drawn with Liquid Glass on macOS Tahoe, and the Reload button is glass too.
- The chat draws the agent's tables, headings, lists, code blocks and quotes, and its text can be selected.
- While the agent works, its steps are one line that says what it's doing now and opens to the rest, in Lamp's
  window and beside the app; what it writes on the way stays as a message. A build that runs long says so, and
  the agent names each command in its own words.
- Approvals ask only for what reaches beyond the app: a command that works on the app itself, its files, builds
  and tests, runs without a card.

## 0.14.0

- Change an app while you use it: the wand in its title bar opens its chat beside the window, and most changes
  go into the open app without it restarting, so what you were looking at stays put.
- Point at part of an app, a button or a spot in a game, and it goes into your message as a picture.
- Lamp opens on your wishes, and starts from what would make your day easier or more fun rather than from an
  app. A vague wish gets a good first attempt instead of a round of questions.
- No more choosing Mac or iPhone: Lamp works out where a wish belongs. An app can be for the Mac and the iPhone
  at once, with iCloud keeping its data the same on every device.
- iPhone apps can have home screen widgets, Live Activities and an Apple Watch app with complications, and keep
  working while they're closed.
- Mac widgets' buttons work. Apps' actions show up in Siri, Shortcuts and Spotlight, apps can take things in
  from the Share menu, and every Mac app has File ▸ Share….
- New building blocks: Apple Health, Photos, location, weather, music, the home, 3D scenes and maps. Apps
  connect to Notion, Linear, Todoist, Jira, monday.com, Home Assistant and more, signing in through the
  service itself.
- Send Now hands waiting messages to the agent while it works, and Undo Last Change sits under the latest
  change.
- Safer builds: they run in the app's own sandbox, and the agent's commands can't change your Applications
  folder, Homebrew or Xcode.
- A rebuild waits while an app asks about unsaved work, and leaves it open if you say so. Rebuilding no longer
  asks for your keychain password, and deleting an app takes its data to the Trash too.

## 0.13.0

- Building with your Claude or ChatGPT subscription no longer needs their apps or a command-line install:
  choose the agent and Lamp fetches its own copy, checked against the maker's signature, and keeps it up to
  date. A Claude Code or Codex already on your Mac is used as it is, with its sign-in.
- The welcome asks what you wish your Mac did, and a wish written on lamp.dev arrives in Lamp without
  pasting. The starter ideas are real situations instead of app categories.
- Duplicate an app to try a variation: the copy has the same code, history and icon on a new colour,
  with an empty chat and its own data.
- Your apps appear in Finder's Applications folder, and they open the files they're for: drop a file on an
  app's icon, or choose it under Open With.
- When an app uses your other apps, you can watch it happen: a glow follows the window in use and a cursor
  shows each step, with approval beside the action and a Stop button. It's on by default with a Claude Code
  or ChatGPT sign-in or an OpenRouter key.
- Permission screens have one place to drag the app from, and Open System Settings always brings the
  panel back.
- The build card no longer says Ready over an app that couldn't be installed or opened.

## 0.12.0

- Mac apps can have a desktop widget. Ask for one and the agent builds it into the app; add it from the
  desktop's Edit Widgets as you would any other.
- New apps look like their kind. Before writing a line, the agent decides whether it's making a tool, a
  companion, a collection, a dashboard, a canvas, a utility or a game, and designs for that: a water
  reminder no longer comes out looking like a database.
- The agent can paint pictures into an app, in the same style as its icon, and sees what it painted. What
  it costs counts towards the app, like the icon.
- Lamp remembers. Its notes about you and about each app are on for everyone now, with the switch in
  Settings → Memory; it was the last experiment, so the Experimental tab is gone until the next one.
- Fewer approval cards: a command that steps into one of the app's own folders and back isn't treated as
  leaving it, Lamp's own git work runs under the same sandbox as the agent's, and Claude Code reads its
  own saved output without asking.
- Built apps are signed with Lamp's certificate on macOS 26 as well, so macOS keeps an app's permissions
  across changes; an app that moves from an ad hoc signature to Lamp's is told its permissions will be
  asked for once more.
- A shared Mac app arrives with a note on how to open it and a description written for the person receiving
  it, and the review of a shared app no longer passes
  one it only partly read.
- The App menu has one New Icon, drawn by whatever Settings says draws icons, and a failed icon says in
  plain words what went wrong.

## 0.11.1

- Before an app goes on your own iPhone or iPad, Lamp checks that an Apple Account is signed in to Xcode
  and that your team is chosen, and tells you what's missing; one signed-in team is chosen for you. Help
  and the setup window say up front that a free Apple Account is enough.
- Lamp works with Xcode 27, which shows simulators in Device Hub rather than the Simulator app: the setup
  check looks for either, and the agent's looks and taps find the iPhone's screen there too.
- When an app is ready on the simulator, the simulator comes to the front.
- Looking at an iPhone app, the agent also reads the screen as text beside its picture: every control and
  piece of text, what it holds and where to tap it, so small print and switch states aren't guesses.

## 0.11.0

- The agent's shell commands run confined to the app: its folder, the system and developer tools, caches,
  temporary folders and the network, and nothing else on your Mac. A command that reaches elsewhere is
  simply refused by macOS, so Lamp no longer has to read commands to guess where they look, and the
  approval card is about what a command does. For anything outside, the agent uses its file tools, which
  ask you. With Codex, the whole of Codex runs confined that way.
- iPhone and iPad apps are for everyone, no longer an experiment. Choose Mac, iPhone or iPad when you start
  an app, your very first one included, and the starter ideas follow what you chose. Lamp tries the app in a
  simulator on your Mac and, with Xcode and your Apple Account, puts it on your own iPhone or iPad.
- The Apple team that signs apps for your phone is now in Settings → Building, and the models an app uses
  on your phone away from your Mac are in Settings → Apps. Both appear once you have an iPhone or iPad app.
- Help has a new iPhone and iPad Apps section.

## 0.10.8

- One answer to what answers your apps. Lamp works out, in one place, what handles an app's text, decisions
  and pictures, here and away on a phone, and how well. When an app needs something nothing here can do, a
  card in its chat offers the ways to set it up: a key typed in place, a download, a sign-in, or Image
  Playground for the icon. Settings → AI Providers shows what answers your apps, and the agent is told what
  the app has when it finishes a request.
- Settings, tidied: Experimental is its own tab (Remember how I like things, and Build iOS apps with the
  Apple team, the away-from-this-Mac models and the setup check under it); Providers is AI Providers; menus
  list only what works now, with Not Ready beside a choice that can't be used.
- Shared apps: the review shows the app's own icon and description; opening one you already have offers
  Update or Keep Both; one opened during setup or the welcome is kept, builds with its progress shown, and
  its review opens once setup is done.
- The chat stays where you scrolled while the agent works, and follows the end again when you scroll back
  down or send a message.
- Stop pressed while sign-ins are being checked keeps the agent from starting; a sign-in Lamp last found
  signed out is checked again before it's used.

## 0.10.7

- The Keychain prompt at launch is gone for good: a key item that another tool put there can't be replaced
  by Lamp, so Lamp keeps that key in its own file (readable by your account only) and stops asking the
  Keychain for it.
- Running an iPhone or iPad app no longer flashes the setup window open and shut: it shows only when a
  check takes a while.
- A detail line's Show Full Output appears only when there's more to show.

## 0.10.6

- What you attach in the chat stays on your Mac. An app's own files (a logo, a data file) live in its new
  `Assets` folder, the only folder bundled inside the app and shared with it; the agent copies an attachment
  there when the app should use it. Apps that already use an attachment get it copied over at their next build.
- Making an iPhone or iPad app no longer crashes Lamp when the setup window appears.
- The Keychain stops asking for Lamp's key at every launch: a key item that was put there by another tool is
  made Lamp's own after the first read.
- A picture picked in Image Playground shows on the app in the chat at once, with a word that it goes on
  the app when the current turn ends.
- A long chat shows its end first, and earlier messages come in as you scroll up to them.

## 0.10.5

- Pictures no longer fall back to a ChatGPT Codex sign-in that happens to be on the Mac: Codex draws them only
  when it's what builds your apps or answers inside them. Otherwise, with no OpenRouter key and no picture
  model on this Mac, Lamp asks for one.
- A chat can no longer leave Lamp stuck during a turn: every row shown is laid out, and a long chat shows its
  end first, with earlier messages a scroll away.
- An app's icon artwork shows in the chat the moment it's picked, rather than at the end of the build.
- Making a new app while an earlier new app was still working sent the message to the earlier app. Each app
  now has its own identity, kept through renames, so a fresh app's first message is its own.

## 0.10.4

- Lamp remembers, as an experiment you switch on in Settings → Building: it keeps short notes on how you
  like things, so a new app starts out in your style, and on what you decided about each app and what you
  turned down, so it isn't offered again. The notes carry over when you switch the agent or model, and the
  AI opens them only when a request needs them. A Memory tab lists them, to read, change or clear.
- When a key or sign-in is refused, or an account is out of credit, Lamp names the one that was used. It
  used to name whatever builds your apps, so an OpenRouter key that didn't work could be reported as a
  problem with ChatGPT Codex or Claude Code.
- An app's icon can be made in Image Playground, on a Mac that has it: from the app's right-click menu, and
  offered when nothing else can draw.
- Settings checks an OpenRouter key with OpenRouter before saving it, so a mistyped key is caught at once
  rather than failing later as a build or a picture. When OpenRouter can't be reached, you can save anyway.
- Settings → Experimental: the iPhone & iPad setup check sits under its notes.

## 0.10.3

- A new app's first build ends with the app ready for you: the agent looks once to be sure it opens, then
  asks whether you'd like it to test the app or change something first, instead of clicking around in it
  while you're trying it. For later changes it still tries them out before saying they work.
- With a model on this Mac chosen for text, Lamp's own quick calls (an app's name and parts, the suggested
  next message, version titles) use it too, rather than going to OpenRouter.

## 0.10.2

- Pictures are made with Nano Banana 2 again unless you pick another: Nano Banana 2.1 stays on the list, but its
  provider has been turning requests away.

## 0.10.1

- No more Keychain password prompts: a key that was put in the Keychain by something other than Lamp made
  macOS ask for your login password at every read. Lamp now makes such a key its own after the first read,
  and reads keys once at launch, in the background, rather than while drawing a view; that also ends a crash
  when the prompt appeared as an app was being created.
- Attaching files: the chat waits for the file picker to close before updating the attachments.

## 0.10.0

- New apps start by choosing Mac, iPhone or iPad (with iOS apps on). Apps on your own iPhone or iPad work
  away from your Mac: while the Mac is reachable their AI goes through Lamp as before, and elsewhere they use
  your OpenRouter key themselves, kept in the phone's Keychain since they last saw Lamp. Settings → Apps has
  "iOS apps away from this Mac": the OpenRouter models a phone app uses for text, pictures and decisions when
  it can't reach the Mac, and an app's own panel has the same choices.
- Putting an app on a phone says what's happening and what went wrong: it waits for the phone to confirm
  the launch (quickly now), explains install failures, and offers Retry; the iPhone setup in Settings shows
  the missing step and its next action.
- Settings is reorganised. Providers shows what's on this Mac (Native Mac AI, Ollama, LM Studio, and your
  Claude Code and Codex sign-ins) apart from the providers you've added a key for, and says on each row what
  it's doing. Building has one Text generation menu, the models under what runs them (Claude Code, Codex,
  OpenRouter, a model on this Mac…), and its own Image generation choice for icon artwork. Apps has Text
  generation (every way an app's AI can be answered, by name), Image generation for pictures inside apps, and
  the decision model. Wherever something needs an OpenRouter key, an Add a Key… button sits at the right,
  and the notes say plainly what happens without one.
- Decisions can be made on this Mac: H2O Lightning 4B, a free 2.5 GB decision model about as good as Jev,
  downloaded from Settings → Apps and run privately. OpenAI's Decisions API (Luna) is a choice too, with an
  OpenAI key, as is answering by text through whatever answers your apps. Jev preview is gone.
- Pictures are made with Nano Banana 2.1, Google's newest image model, unless you pick another.
- The welcome's agent step: picking Claude Code or ChatGPT is the choice; only a missing app or sign-in is
  asked for.
- The agent writes in the language your Mac is set to, and so do the apps it makes.
- The build card shows progress while the agent thinks, before its plan, and what's being worked on.

## 0.9.3

- Report a bug from Help: Lamp gathers what happened, shows you the report to check, and sends it through
  lamp.dev.
- The build script and package file of every app are Lamp's own again at each build, so nothing the agent
  writes into them can run around your approval.
- Opening a shared app: the check no longer warns about Lamp's own building blocks, and says which of your
  data an app hands to the AI.

## 0.9.2

- Apps can use your other apps whatever builds them: with a local model or your Claude Code or Codex
  sign-in as well as with an OpenRouter key. The person still approves every click and keystroke.
- With the ChatGPT app's Computer Use installed, that's what does the looking and clicking: real clicks and
  drags in the background, better reading of what's on screen, and nothing to install. CuaDriver stays as the
  fallback, and a switch in Settings → Apps chooses.
- The key Lamp hands its built-in agent is given out only to this Mac again.

## 0.9.1

- iPhone and iPad apps use more of the phone: the agent knows about the motion sensors, the camera and
  scanning, location, haptics, Face ID, Bluetooth, nearby phones, Health, NFC, Siri and Shortcuts, AR and
  music, and asks for each one properly. Apps that need Health, NFC, Siri or work in the background are
  signed for it. The agent says which parts need your phone rather than the simulator.

## 0.9.0

- Your iPhone or iPad apps on your own phone: with the new switch in Settings → Building → Experimental
  and your Apple account signed in to Xcode, plug your phone in: Try On pairs it with your Mac and lists
  it. Press Play and Lamp builds the app for your phone, signs it with your account and puts it there; its
  AI still goes through Lamp, over your Wi‑Fi.
- A new welcome: the first screen and the new-app screen are quieter, with a short film of the lamp, and
  the ideas to start from are fewer and broader, drawing on the Mac's own apps. Once you have an app of
  your own, a new app's chat offers six fresh ideas each time.
- Quick Look for the files in a chat: press Space on an attachment to see it.
- Versions stays open after an Undo that takes an app back to empty.
- Your keys live in the Keychain: a signed Lamp moves any left in its settings file there, and the agent
  no longer keeps a copy of its own.

## 0.8.0

- iPhone and iPad apps, as an experiment you switch on in Settings → Building: build an app and try it in
  the iPhone or iPad simulator on your Mac (needs Xcode), choosing the device beside the Play button. The
  agent sees the screen after each change and taps, types, scrolls and swipes on it to try what it made
  (allow Lamp under Accessibility in System Settings when it asks). The apps get the same icon and the
  same building blocks as Mac apps: saved data that survives every change, AI and quick decisions,
  behavior written while the app runs, text read out of photos and documents, drops, calendar, reminders,
  contacts and notifications. Putting the app on a real iPhone comes later.
- Change a message you already sent and send it again: a pencil on your message opens it for editing,
  and Escape puts it back.
- A long chat opens on its latest messages.
- Fewer needless approval cards: commands that only look like they reach outside the app's folder (such
  as sending output to nowhere, or writing a file inside the app) no longer ask.
- Installing the local-model tools says what actually went wrong, and Settings gives the picture model's
  real size (about 1.3 GB).

## 0.7.0

- Stop really stops: it ends everything the agent started, including a build in progress, and quitting
  Lamp while it's working asks first.
- Deleting an app while it's being built no longer brings it back.
- Claude Code asks before reading files outside an app's folder, like the other agents do, and follows the
  same "ask before running commands" setting. Every agent can now plan, delete files and work with an app's
  saved versions.
- A shared app's review shows what the app can do as a list, like an app's permissions in System Settings,
  with anything sensitive marked; opening such an app takes a deliberate click.
- Apps keep their saved data more reliably: a change that fails is undone as a whole, dates read back
  exactly, and a number that couldn't be saved before is kept now. A reply that quits the agent, a crash
  when recognizing text in a picture, and a crash when dropping several files at once are fixed.
- Mail in your apps: message dates are right in every time zone, and accounts whose inbox has another
  name are included.
- A question with a screenshot attached no longer rebuilds and relaunches the app, and an edit made
  while a build runs is picked up by the next one.
- Icons: the finished artwork no longer arrives in the middle of a build.
- Dictation no longer crashes on a Mac without a microphone; Copy App File has its ⇧⌘C shortcut in the
  Edit menu; app tiles and the welcome choices work from the keyboard.
- Release notes are written by hand, so this is what you read here.

## 0.6.3

- A new app shows "Describe an app…" until the first message.
- A new app's icon artwork starts as soon as its icon is designed, so the first version opens with its icon.
- Updates come from updates.lamp.dev.

## 0.6.2

- An app whose last window was closed comes back with one when opened again.

## 0.6.1

- "Ask before running commands" has a new default, Only when risky: routine, low-risk commands run without
  asking.

## 0.6.0

- Forge is now Lamp. Existing apps, keys and settings move over on first launch.
