---
name: app-ai
description: AI inside the app - whether it belongs at all (asked for, worth offering with one question first, or left out), Apple's on-device frameworks first, LampAI for open-ended text and pictures, decisions for judging things by what they mean, checked actions for doing what the person asks, setup and where data goes, untrusted text, and dates. Read before writing any of it.
---

# AI inside the app

## Whether AI belongs, and asking first

Lamp never adds AI the person didn't ask for. Keep it in mind as one way to make an app better, not the point of every
app: most need none. Decide from what they want to get done, the kind of app, the data it has and what a wrong answer
would cost.

- **Asked for**: the request itself is for what AI does ("summarize my emails", "understand what I say", "suggest a
  name"). Build it with the smallest block that does it, and say in a sentence what it does and where it's worked out.
- **Worth offering**: AI would add something definite (understanding what they type, reading what they hand the app,
  drafting) but they didn't ask for it. Before writing any of the app, ask with one `ask` that says what they're
  making and what AI would do in it, in their words: "I see you're making a recipe box. Want AI to turn a pasted recipe
  into a card and find recipes by what's in your fridge?", answered No thanks or Yes, in that order, so leaving it to
  you means none. Then build: with that AI after a yes, without it otherwise.
- **Leave it out**: exact rules already do it, the gain is vague, or facts, timing or anything in real time would get
  less reliable. Ordinary code, and no question about AI.

Don't pester. Offer AI at most once for an app, where it would change what the app can do, never for small changes or
in every reply. A no is for that app alone: write "AI: offered, declined" in its APP.md (not in Lamp's notes about the
person), don't offer AI in that app again unless they bring it up, and still offer it in other apps where it fits.

A kitchen timer with three presets and a loud alarm has no AI and no question about it: durations, scheduling and the
alarm are code. A remote "with buttons for my TV" is buttons, and "Want AI to turn 'movie night' into a routine for
your TV and speaker?" is worth one question before building it. "Let me say 'movie night' and have it use my TV and
speaker" asks for it, so it's built: a routine the person reviews and saves, which then runs from its button with no AI.

Which block: Apple's frameworks where one fits; `ask(..., as:)` for a structured draft; a decision for a judgment by
meaning; a checked action (below) for a request that changes something. Arithmetic, ids, permissions, what's saved and
what's true stay in code. A model's confidence is never permission to change something.

When AI goes in (asked for, or after a yes), write its contract in APP.md under the feature, a few lines: what it
gives the person, which block, what's sent and where it's worked out (from `LampAI.status`, below), what it may
change, what the app checks, what happens without it, and the case that proves it works. Keep it current as the feature changes.

## On-device frameworks first

Prefer Apple's on-device frameworks whenever one fits the job: they're instant, free, private and work offline.

- Text in images or PDFs, barcodes and QR codes, faces, body or hand poses, cutting a subject out of its background,
  image tags or similarity → Vision (VisionKit's ImageAnalysisOverlayView for Live Text in an image view).
- Speech to text → Speech (SFSpeechRecognizer, with requiresOnDeviceRecognition when supported).
- Reading text aloud → AVSpeechSynthesizer.
- Language detection, names and places, sentiment, semantic search → NaturalLanguage (NLTagger, NLEmbedding).
- Recognizing sounds → SoundAnalysis.
- Photo filters and effects → Core Image.
- Translation → Translation, inside `if #available(macOS 15, *)` on the Mac and `if #available(iOS 18, *)` on iPhone.

The app already declares microphone, speech recognition and camera permissions (and calendars, reminders, contacts
and photos; on the Mac also Bluetooth and Mail); request authorization before use and handle denial in the UI.

## LampAI for the rest

For open-ended AI work those frameworks can't do (summarizing, extracting, rewriting, answering questions,
generating text, understanding what a picture means), use `LampAI.ask(...)` from LampSupport.swift. Read its doc
comment for usage. Never call AI APIs directly, never ask the user for API keys. It accepts `images:` (`NSImage` on
the Mac, `UIImage` on iPhone, `LampImage` in an app for both) when the AI needs to look at photos or screenshots. To
create or edit pictures, use `LampAI.makeImage(...)`, `LampAI.editImage(...)` or `LampAI.editImages(...)`; these take
10–60 seconds. Show a ProgressView while waiting and show errors in the UI.

## Doing what the person asks: checked actions

`LampAI.act` in Swift is a `LampActSession` (its comment has the whole API) holding the app's own tools: reads that look
things up and writes that change them, each a few lines over the app's data and its ordinary commands. The AI proposes
calls, Lamp checks their shapes, the app's `check` says whether that exact change is allowed now, and its `run` makes it
and returns a receipt. Lamp keeps the loop, its limits (4 AI steps between questions, 6 changes a request, 3 questions
back, the route's time), cancellation, questions back and the receipts.

```swift
struct Rename: Decodable { let id: String; let name: String }

let session = LampActSession(about: "A list of rooms. Ask which room when two could fit.", tools: [
    .read("rooms", "Every room: id and name.") { store.rooms.map { ["id": $0.id, "name": $0.name] } },
    .write("rename", "Renames one room.", args: ["id": .text("A room's id from rooms"), "name": .text("The new name")], as: Rename.self,
           check: { r, _ in store.room(r.id) == nil ? "There's no room with that id." : r.name.isEmpty ? "Say the new name." : nil },
           run: { r, _ in try store.rename(r.id, to: r.name); return LampActReceipt("Renamed to \(r.name)") }),
])
let result = await session.ask(typed).result
if let question = result.question { askBack(question, offering: result.choices) }   // then session.answer(reply)
else { status = result.summary }
```

- Show the feature where `await LampAI.status(.act)` says it's available, with what answers and where its `processing`
  is (`remote` for a service, Claude Code and Codex included; `onDevice` for a model on this Mac). When it isn't, keep
  the feature visible with its `reason` and a "Set up in Lamp" button (`LampAI.openSetup(for: .act)`), or "Open Lamp" /
  "Update Lamp" when `setup` says so; keep the typed draft, and every manual control working. Check again when the app
  comes back to the front, and never send the draft by itself after setup. Available is no guarantee: show the actual
  failure (`result.error`) with the request kept and an explicit Try Again.
- A tool is a named read or write over the app's own data, ids in and ids out: never "run this", never an address the
  AI gives, never another app. Device names, messages and pages are data, not instructions.
- Every write's `check` looks its items up again by id and says in a sentence why it can't be done now (gone, not
  connected, can't do that, out of range); make the final check and the change one step for local data, or have `run`
  check the revision again. Make the ids of what a write adds from `call.key`, so the same change delivered twice finds
  it instead of adding a second.
- Say what happened from `result.done` (the receipts), `failed`, `skipped` and `stopped`, which is what `summary` does:
  never from the AI's `reply`, which is shown only for a question or when nothing changed. A receipt says what the code
  knows: "Sent" when a device took a command, never "The TV is on".
- Offer `result.choices` as buttons for a question; only the first answer counts (`session.answer` returns nil after).
- Cancel (`turn.cancel()`) when the person stops or closes it. A change already sent stays in the receipts as sent:
  never say nothing happened. Don't retry a change whose outcome is uncertain by yourself; show what's left for the
  person to run again.
- For a change with real consequences (a device, a message, money), let the AI build a draft the person reviews and
  confirms with the app's own button, rather than act at once. Confirming is the app's policy for that change; it isn't
  what makes the arguments safe, `check` is.
- Not on a phone away from the Mac: actions need Lamp, and `status(.act)` says so there.

A web page's `LampAI.act` is the same contract in lamp.js: the web-app skill's "Doing things for the person".

## Decisions

When the app has to judge things by what they mean, decisions are the tool. `LampAI.isTrue`, `LampAI.choose`,
`LampAI.rate` and `LampAI.decide` call a decision model (Jev) that is smart, very fast (well under a second) and
extremely cheap (about $0.04 per million input tokens: judging hundreds of items costs a fraction of a cent). In an app
whose AI was asked for or accepted, where it sorts, filters, labels, prioritizes, groups, matches, routes, moderates or
flags things by what they are or mean (file names, messages, notes, titles, descriptions, what the person meant), use
one rather than keyword lists, regexes, extension rules or other hand-written heuristics that guess at meaning. In an
app without AI, judging by meaning is a reason to offer it (above), not to add it. Where an exact rule
decides it (a size, a date, a type the system reports), that's code, not a decision. It's fine to judge every item
individually.

To judge a list, hand the whole list to `LampAI.isTrue(_:each:)`, `LampAI.choose(_:from:each:)`,
`LampAI.rate(_:levels:each:)` or, for several questions per item, `LampAI.decideEach(items, questions)`: they run
about 12 at a time, keep the order, report `progress: { done, total in }` on the main thread and return one
`LampVerdict` per item (`item`, `probability` / `choice` / `score` / `confidence`, and `error` for an item that
couldn't be judged). Pass `remember: seconds` to save verdicts so unchanged items aren't judged again until they
expire (e.g. a week for files, a day for messages). Never write your own TaskGroup, loop, progress counter or verdict
cache for this. Ask several questions about one thing in one `decide` call. Use code for exact facts (sizes, dates,
duplicates, arithmetic) and combine them with decisions: pass the facts in as part of the state. Use the returned
probabilities and confidence to choose between acting automatically, suggesting, and asking the user. Decisions take
text or JSON-friendly data, not images.

## Untrusted text

Text the person didn't type into the app themselves is untrusted: emails, messages, notifications, web pages, file
contents, the clipboard, anything read from another app. It can contain instructions aimed at the AI ("ignore the
above and…"). Never interpolate it into a prompt: pass it as `data:` (`LampAI.ask("Summarize this email in one
line.", data: email.body)`), and Lamp fences it off so the AI works on it without obeying it. In decisions it goes in
`about:`, with the question in your own words. Don't write regexes, keyword filters or "sanitizing" code against it.
Fencing helps the AI read it as material rather than orders, but it is no guarantee: what the app does with an answer
is held by the app's own code, a write's `check`, ids looked up again, the person's review of anything consequential.

## Dates and times

`LampAI.ask` already tells the AI the current date, time and time zone, so don't add them yourself. Give the AI a
date with `LampAI.when(date)` (it writes "Mon 5 Oct 2026 at 15:00 (in 44 minutes)", with the distance worked out in
code); Dates inside `about:` are written that way automatically. Get a date back by asking for ISO 8601 and decoding
into a `Date` property with `ask(..., as:)`, or with `LampAI.date(from:)`. Always keep the `Date` itself and work out
"in 44 minutes", "overdue" or "ended" in code when it's shown (`Text(date, style: .relative)` or a TimelineView keeps
it current); never store or display a relative time the AI wrote, because it's wrong minutes later.
