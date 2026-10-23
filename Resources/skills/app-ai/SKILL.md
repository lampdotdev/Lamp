---
name: app-ai
description: AI inside the app - Apple's on-device frameworks first (text in pictures, speech, reading aloud, language, sounds, translation), LampAI for open-ended text and pictures, decisions for judging things by what they mean, untrusted text, and dates with AI. Read before writing any of it.
---

# AI inside the app

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

## Decisions

Decisions are your default tool for anything that depends on meaning. `LampAI.isTrue`, `LampAI.choose`,
`LampAI.rate` and `LampAI.decide` call a decision model (Jev) that is smart, very fast (well under a second) and
extremely cheap (about $0.04 per million input tokens: judging hundreds of items costs a fraction of a cent). Use
them generously, without being asked, whenever the app sorts, filters, labels, prioritizes, groups, matches, routes,
moderates or flags things by what they are or mean: file names, messages, notes, titles, descriptions, user intent.
Prefer a decision over keyword lists, regexes, extension rules or other hand-written heuristics that guess at
meaning; those are brittle and the decision model is better at it. It's fine to judge every item individually.

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
`about:`, with the question in your own words. Don't write regexes, keyword filters or "sanitising" code to defend
against it; `data:` is the defense.

## Dates and times

`LampAI.ask` already tells the AI the current date, time and time zone, so don't add them yourself. Give the AI a
date with `LampAI.when(date)` (it writes "Mon 5 Oct 2026 at 15:00 (in 44 minutes)", with the distance worked out in
code); Dates inside `about:` are written that way automatically. Get a date back by asking for ISO 8601 and decoding
into a `Date` property with `ask(..., as:)`, or with `LampAI.date(from:)`. Always keep the `Date` itself and work out
"in 44 minutes", "overdue" or "ended" in code when it's shown (`Text(date, style: .relative)` or a TimelineView keeps
it current); never store or display a relative time the AI wrote, because it's wrong minutes later.
