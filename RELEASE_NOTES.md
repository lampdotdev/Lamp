# Release notes

What people read in the update window and on the GitHub release. One section per version, newest first,
written for the people who use Lamp: what they can do now, what works better. No PR numbers, handles or
file names. The release workflow takes the section for the tag being released; a version without one gets a
plain "Lamp x.y.z" line.

## Unreleased

- Lamp remembers, as an experiment you switch on in Settings → Building: it keeps short notes on how you
  like things, so a new app starts out in your style, and on what you decided about each app and what you
  turned down, so it isn't offered again. The notes carry over when you switch the agent or model, and the
  AI opens them only when a request needs them. A Memory tab lists them, to read, change or clear.
- When a key or sign-in is refused, or an account is out of credit, Lamp names the one that was used. It
  used to name whatever builds your apps, so an OpenRouter key that didn't work could be reported as a
  problem with ChatGPT Codex or Claude Code.

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
