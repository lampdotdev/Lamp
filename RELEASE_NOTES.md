# Release notes

What people read in the update window and on the GitHub release. One section per version, newest first,
written for the people who use Lamp: what they can do now, what works better. No PR numbers, handles or
file names. The release workflow takes the section for the tag being released; a version without one gets a
plain "Lamp x.y.z" line.

## Unreleased

- Pictures are made with Nano Banana 2.1, Google's newest image model, unless you pick another in Settings → AI.
- Apps on your own iPhone or iPad work away from your Mac: while the Mac is reachable their AI goes through
  Lamp as before, and elsewhere they use your OpenRouter key themselves, kept in the phone's Keychain since
  they last saw Lamp.

## Unreleased

- Settings → Providers now shows what's on this Mac (Native Mac AI, Ollama, LM Studio, and your Claude
  Code and Codex sign-ins) apart from the providers you've added a key for, and says on each row what it's
  doing: building apps, answering inside them, making pictures, deciding. A note says a key can go with an
  app to your iPhone while a sign-in can't.
- "Inside your apps" lists every way an app's AI can be answered, by name: OpenRouter's models, your Claude
  Code or Codex sign-in, or a model on this Mac. An app built with a model on this Mac keeps using it even
  once you add a key.
- With iOS apps on, Settings → Apps has "Away from this Mac": which OpenRouter model an app on your phone
  uses when it can't reach the Mac, and a plain word (with the way to a key) when there's no key for it. An
  app's own panel has the same choice.

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
  behaviour written while the app runs, text read out of photos and documents, drops, calendar, reminders,
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
  when recognising text in a picture, and a crash when dropping several files at once are fixed.
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
