# Home HQ by voice: a design for review

Status: proposal, nothing built. Written against `origin/main` at 487f21e2. Second draft, after review; (b) chosen, specified in [act.md](act.md).

The goal: someone says "What do we need before school?", "Add milk" or "Mark the dishes done" into their phone, Home HQ
does it with its own data, the TV and every other copy of the screen show the change, and the phone answers out loud,
saying only what really happened.

Four parts, in this order: **actions** (Home HQ's changes, callable and safe), **the loop** (read, decide, act,
observe), **voice** (hearing and speaking on the phone), and **where the loop lives**: inside Home HQ or as a small
piece of Lamp. The last one is a choice to make (see "Two ways to build the loop").

## What's there today

- **Home HQ is a screen**: one web page (`Resources/Starters/homehq/Web/`), shown on the Mac, iPhone and iPad inside
  Lamp's common app around a page (`Resources/GameKit/apple/LampPage.swift`), and on TVs, Android and the Xbox in their
  own hosts. Every copy keeps the family's data the same through the wish's shared collections (`Web/js/sync.js`:
  `people`, `chores`, `groceries`, `events`, `ticks`, `stars`, …), merged item by item, last write wins per item, with
  no version on an item. A change made on any copy reaches the TV with no new plumbing: change `DATA`, call
  `App.emit('data')`.
- **The changes live inside click handlers.** Adding a grocery (`shopping.js` `add`), ticking a chore and giving its
  stars (`tasks.js` `complete`), adding an event (`calendar.js`, the New event sheet) each mix the data change with DOM
  work, timers and toasts. Nothing else can call them.
- **`LampAI` for pages** (`DeviceSupport.webJS`, written as `Web/lamp.js`): `ask(prompt, {data, system, json, model})`,
  `choose`, `decide`, `decideEach` and pictures. Each call gets one whole answer back: **no streaming, no tool calling,
  no conversation, no way to cancel a call in flight**.
  - `json: true` gets a JSON-only instruction. The gateway re-asks once when the reply doesn't parse
    (`AppAI.complete`, `Sources/Lamp/Gateway.swift:524`).
  - A `schema` in the request body is dropped (`Store.appRequest`), though `AppAI.complete` can already send OpenRouter
    a `response_format` schema.
  - Lamp's gateway on the Mac answers every call. Away from the Mac's Wi‑Fi, or with Lamp closed, the call fails with
    "Couldn't reach Lamp on your Mac".
- **Which model answers** is the app's own choice (`AppModels.load(project).text`), then Settings, then OpenRouter
  Sonnet when there's a key, or the builder's sign-in.
- **No speech for pages.** lamp.js has none, and the page's web view grants no microphone. Native speech works in three
  starters:
  - Universal Remote (`VoiceListener.swift`): tap to talk, on-device `SFSpeechRecognizer`, ends after 1.3 s of silence.
  - Wedding Words (`Speech.swift`): push-to-talk and `AVSpeechSynthesizer`.
  - Transcriber: `SpeechAnalyzer`, continuous, Mac only.

  Every generated Apple app already carries the microphone and speech-recognition usage descriptions.
- **Phone pages opened from a QR code** are plain `http://<Mac's LAN IP>:478xx/`, so a phone's browser won't open the mic
  there (`getUserMedia` needs a secure context).
- **`LampNative.call(name, args)`** reaches the app's own `Sources/Native.swift` on the Mac, iPhone and iPad. Home HQ
  already uses it for calendars and photos.
  - It's request and answer only: Swift can't push to the page.
  - `LampNative.available` only says a bridge exists, not that a given call is registered. A call that isn't registered
    rejects.

## Where it runs: Home HQ's own page, on the copy that heard you

The phone is **Home HQ's own iPhone copy** (the same page, already laid out for a phone). The loop runs in that page,
where `DATA` lives.

- One implementation of every rule: the page already knows that stars follow a tick, that ticks are per day, how an
  example stops being one, and which aisle an item goes in. A separate native iPhone app would have to copy all of that
  in Swift.
- The TV updates through the sync that's already there.
- The mic is native, through `LampNative` and `Native.swift`.
- Installing it costs the same as a native iPhone app (Xcode, a team, the free account's 7 days and 3 apps), and the
  iPhone is already one of Home HQ's places.
- The Mac copy gets the same voice, which is how most of it is tried before a phone.

Turned down:

- **A QR phone page**: it can't hear over HTTP.
- **A native iPhone app in the wish**: it would duplicate the rules. It's the right home later for Siri, since a
  screen's build makes no App Intents.
- **The phone relaying text to the Mac's copy**: an extra hop and an election of which copy answers, for no gain.

## Actions: checked against fresh data before anything changes

New file `Web/js/actions.js`, loaded after `data.js` and before the views. It holds the only code that changes the
household's data on request. The views' buttons call the same functions and keep only their DOM work.

### Reads

Reads change nothing and come back as small JSON the loop shows the model:

| Read | Gives |
| --- | --- |
| `people()` | id, name, kid or grown-up or pet, stars |
| `events({ from, to, people? })` | every event in a date range (Home HQ's own and the shared calendar's), each with id, title, start, end, who, place, and whether Home HQ can change it (`cal` events can't) |
| `chores({ part?, who?, day? })` | the chores of a part of the day (morning, after school, evening, or all), each with id, title, who, stars, done today and by whom |
| `groceries({ open? })` | id, name, aisle, quantity, store, done |
| `today()` | the date, time, time zone, part of the day, the weather line and what's next: enough for "before school" in one step |

### Writes

`addGrocery`, `checkGrocery`, `uncheckGrocery`, `setGroceryQty`, `completeChore`, `uncompleteChore`, `addEvent`.

There is no delete or clear in v1. Clearing the list and removing events stay on the screen, where the Undo toast is.

### How every write runs

Every write runs in three steps:

1. **Look up fresh, by id.** The write takes ids, never names or positions. It finds its item again in `DATA` at that
   moment, because sync may have rebuilt the arrays since the model saw them (`take()` replaces `D.groceries` and
   `D.chores`).
2. **Check, all before any change.** Every write in a step is checked before any of them runs. If one fails the check,
   none runs, and the reasons go back to the model as what it observed. The checks:
   - The id exists and isn't `gone`.
   - The person exists. A pet can't do a chore or attend an event.
   - The chore isn't already done today, or already undone.
   - The grocery item is still open.
   - `addEvent` has a title, a start in the future and no more than a year ahead, a length between 5 minutes and 24
     hours, and only the household's people.
   - The quantity is between 1 and 99.
   - An `addGrocery` whose name matches an open item becomes "already on the list" (or raises the quantity when one was
     asked for). It never makes a second row.
3. **Apply, then report what's there.** The write changes `DATA`, calls `App.emit('data')`, reads the item back, and
   returns `{ ok, id, now }`, where `now` is the item as it is after the change. A write never reports success on its
   own say-so.

### Repeats don't duplicate

Every turn has an id (`t` + time + random). A write that makes something new gets an id built from the turn and the
step (`v<turn>-<n>`). Running the same write twice therefore puts the same item, and the shared collections merge it
into one, even across copies. Each write also gets a key, the turn plus the write and its arguments. The turn keeps
these keys, so a step the model repeats after observing comes back "already done" and doesn't run again. Retrying a
failed turn (the "Try again" button, below) reuses its turn id, so whatever got through the first time isn't done
twice.

### Undo only if nothing changed since

Each write keeps what the item looked like before and after. "Undo" (said, or tapped on the sheet) undoes the last turn's
writes in reverse order, each one only if its item, looked up fresh, still matches what that write left. An item that has
changed since (someone ticked it off on the TV, or another phone changed the quantity) is left alone, and the reply says
so: "I put the eggs back, but someone already bought the milk." Undo needs no model call.

## The loop: read, decide, act, observe

```
turn(request):
  observe = today()                                      # always given
  for step in 1..4:                                      # at most 4 model calls
    plan = model(request, history, observe)              # one of:
      { "read":  [ {name, args} … ] }                    #   look something up
      { "act":   [ {name, args} … ] }                    #   change something (at most 6 writes in a turn)
      { "reply": "…", "ask": false }                     #   finished, or a question back (ask: true)
    if read:  observe += results;            continue
    if act:   observe += check-then-apply results (above); continue
    if reply: break
  speak(receipt(writes) + reply)
```

- **Deciding never writes.** Only a step the code has checked writes, and only what the household's data allows at
  that moment.
- **The model sees results before it says anything is done.** After an `act`, the next step observes `{ ok, now }` or
  the reason for each write.
- **What's spoken about writes is built by the code from the results, not by the model.** For example: "Added milk.
  Marked the dishes done for Maya." When something failed, the receipt says what worked and what didn't, in that
  order: "Added milk. I couldn't add soccer on Friday: there's already Soccer practice then." The model's `reply` adds
  the answer to a question, or a question back, never a claim that something was done. A partial success is spoken as
  partial.
- **Limits**: 4 model calls, 6 writes and 25 seconds per turn. When it hits one, it stops and speaks the receipt so far
  plus "I stopped there."
- **Typical turns**:
  - "Add milk": act, then a reply from the receipt. One model call when the code ends the turn after a clean act with
    nothing left to answer, two otherwise.
  - "What do we need before school?": usually one call, answered from `today()`, or two with a `chores` read.
- **What the screens show**: the copy that heard you shows the words, then each step ("Looking at the calendar…",
  "Adding milk…"), then the receipt and Undo. The other copies just change, as when someone taps.

### Questions back: dates, people, duplicates

The system text sets these rules. The checks enforce what they can.

- **Dates and times** are resolved against `today()` (the page's date and time zone):
  - "Friday" means the next Friday, today included only if it's still ahead.
  - "Tonight" is after 5 PM today. "This weekend" is the coming Saturday and Sunday.
  - A time with no AM or PM is read the way a family means it (7 to 11 is morning, 1 to 6 is afternoon). Otherwise it
    asks.
  - An event with no time asks "What time?", unless "all day" was said.
  - A date in the past, or one Home HQ can't place, asks rather than guesses.
- **People**:
  - A name means a person in `people()`. "The kids" are the people with stars, and "everyone" is all the humans.
  - "I" and "me" ask who, since a phone isn't a person.
  - A name not in the family asks.
  - The person who gets stars for an Anyone chore asks "Who did it?".
- **Duplicate names**: two chores or items that both fit ("Dishes" in the morning and the evening, "Milk" at two
  stores) ask, with the difference: "The morning dishes or the evening ones?" It prefers the current part of the day
  only when the other one is already done.
- **The calendar**: additions go to **Home HQ's own calendar**, as the New event sheet does, never to Apple's or
  Google's calendars. The spoken receipt says "on Home HQ". An event from the family's shared calendar shows in reads
  but can't be changed: "That's on your shared calendar, so change it there."
- **History**: the last three exchanges of this copy, so "Maya" answers "Who did it?". A question back is a new turn
  with the same history.

### Outside text

Event titles, notes and item names, including those from the family's shared calendar, go to the model as fenced
outside text, as `LampAI.ask`'s `data` already does. None of them can make a write that the checks wouldn't allow
anyway, and there is no delete to be talked into.

## Two ways to build the loop

`LampAI.ask` returning a JSON plan stands in for tool calling, which Lamp doesn't offer the apps it makes. Either way,
the actions, the checks, the turn ids, undo and the voice are Home HQ's. Lamp can't know a household's rules. What
differs is who runs the loop and talks to the model.

### (a) The JSON plan, inside Home HQ

`Web/js/agent.js` builds the system text from the read and write list, calls `LampAI.ask(…, { json: true })` once per
step, checks the plan's shape itself, and runs the loop above.

- **Lamp changes**: none. It ships as a starter change, and existing copies take it on their next build.
- **What it costs**:
  - The protocol lives only in the prompt. A step can come back the wrong shape, so the page checks every field and
    treats a bad plan as a failed step. The gateway only re-asks for JSON that doesn't parse at all.
  - Each step sends the whole context again.
  - There's no streaming, so the reply is spoken only after the last step.
  - The next app that wants this copies `agent.js`.
- **Time**: about 2 to 3 days for actions, the loop and the checks, plus voice (below).

### (b) A small `LampAI.act` in Lamp first

`LampAI.act(request, { reads, writes, context, history, limits })` in lamp.js, with a new `/ai/act` gateway route that
runs the model side of the loop:

- It uses real tool calling on routes that have it (OpenRouter).
- It falls back to a JSON plan with a schema on routes that don't (Claude Code, Codex, the models on this Mac).

The page still runs each read and write itself, between steps. `act` hands them to the page and passes back what the
page observed.

- **Lamp changes**: lamp.js, which goes into every page and must stay ES5 for the TVs' browsers; the gateway route and
  `Store.appRequest`; the prompt rule for pages (`TVTemplate.webAI`) and the `app-ai` skill; the docs. Then the same in
  Swift for native apps, or a note that it's only for pages for now.
- **What it costs**:
  - Every text route needs either tool calling or the fallback, and needs testing.
  - Home HQ can't use it until a Lamp release is out.
  - The interface gets fixed before one app has shown what it needs.
- **What it gives**: a protocol the model is held to, and one place for limits, step reporting and later streaming.
  Every page and app gets "talk to it" without copying Home HQ.
- **Time**: about 4 to 6 days, plus waiting for a release, before Home HQ's part starts.

**Chosen: (b).** Its API, gateway route, routes and rules are in [act.md](act.md).

### Recommendation (before the choice)

**(a), with `agent.js` shaped like `act`**: the same reads and writes table, the same step results, the same limits.
Lifting it into Lamp afterwards is then a move, not a redesign, and v1 tells us what `act` must do before Lamp commits
to it. Choose (b) instead if a second app wants a voice agent soon.

## Voice

Three calls in Home HQ's `Sources/Native.swift`, built from Universal Remote's listener and Wedding Words' speech:

- **`voice`** answers `{ listen, speak, onDevice, permission }`, where `permission` is `granted`, `denied` or
  `undetermined`. It's the real capability check. The mic button shows only when this call answers and `listen` is
  true, which needs a speech recognizer for the language with on-device recognition. On a TV, Android or Lamp's preview
  the call rejects, and so does an older build that never registered it, so the button doesn't show there. `denied`
  shows the typed box with a line on turning the mic on in Settings.
- **`listen`** starts on-device recognition, given the people's names, the chores and the list as contextual words. It
  resolves with `{ text, ended }`, where `ended` is `silence` (after 1.3 s), `stopped`, `cancelled`, `interrupted` or
  `nothing` (no speech in 6 s).
- **`stop {cancel}`** ends listening. With `cancel`, the words are thrown away.
- **`speak {text}`** resolves when done or stopped. It never overlaps listening.

v1 needs on-device recognition. Where there isn't any, it's the typed box only, so the household's words never leave the
devices except as text to the model.

### The lifecycle of a turn

`idle → listening → thinking → (acting ↔ thinking) → speaking → idle`, or `speaking → listening` when the reply asks
back.

| What happens | When it happens | Result |
| --- | --- | --- |
| Tap the mic | listening | Stop listening, then use the words |
| Tap ✕ | listening | Cancel. Nothing is sent |
| Tap ✕ | thinking | Cancel the turn. The model's answer, when it comes, is dropped and acts on nothing |
| Tap ✕ | acting | The writes of the current step finish (they're local and take milliseconds). No further steps run. The receipt is shown and Undo is offered |
| Tap ✕ or the mic | speaking | Stop speaking |
| The phone locks or the app goes to the background | any time | The native side ends listening (`interrupted`) and stops speaking: an audio interruption, or the app resigning active. The page, on `visibilitychange` to hidden, cancels a turn that hasn't acted yet |
| The app comes back with an unfinished turn | after a lock or background | No step is resumed in the background. The sheet shows "Didn't finish: add milk", with what was done and **Try again**, which reuses the turn's id so nothing is done twice |
| An answer arrives late | after the turn was cancelled, timed out (25 s) or replaced by a new one | Every model answer carries its turn id and step. One that isn't for the live turn's current step is dropped. It never writes |
| Can't reach Lamp | any step | "I can't reach Lamp on the Mac." Whatever was already done is in the receipt |

## Milestones

0. **Phone to TV, first.** Before any model: build Home HQ with `actions.js` and a typed test box for one write
   (`addGrocery`) on the iPhone. Show it on a TV place (a Samsung or LG TV, or the TV preview when no TV is at hand).
   Measure: tap on the phone, then milk on the TV, and how long that takes. This proves the iPhone build with the extra
   `Native.swift` calls, the wish sync between the phone and the TV, and the new ids. About half a day, plus the phone's
   setup.
1. **Actions and checks** for all the reads and writes, with the views moved onto them.
2. **The loop**, typed, on the Mac copy.
3. **Voice** (`voice`, `listen`, `stop`, `speak`) and the lifecycle, on the Mac, then the iPhone.
4. **The acceptance run** (below).

## Acceptance: writes go safely

A scripted run in an isolated copy against the example family, through the typed box and the real model, plus checks
that fake the model's answers to test what the model can't be relied on to produce.

**The gate. All of these must hold in every run:**

1. **Nothing unasked.** No write that the request didn't ask for. Reads and questions write nothing.
2. **Nothing duplicated.** The same request twice, a repeated step and a Try again after a timeout each leave one item.
3. **Nothing on stale data.** Another copy deletes the item, ticks the chore or changes the list between the model's
   read and the write. The write is refused or left alone, and the receipt says so.
4. **What's said is what's there.** After every turn, each spoken "done" matches the shared collections read back
   on another copy. A partial success says which part failed.
5. **Undo is safe.** It undoes only items unchanged since, and says which ones it left.
6. **Cancelled means cancelled.** Cancel, lock, a late answer and a timeout never write after the cancel.
7. **Calendar writes stay in Home HQ.** Nothing reaches Apple's or Google's calendars.
8. **The limits hold.** No turn makes more than 4 model calls or 6 writes.

**Reported, not gated:**

- How often the right action was chosen, over a fixed list of requests (including ones it can't do yet, like "move
  soccer to five", which must say so).
- Time from the end of speech to the first spoken word.
- Model calls per turn.

These decide whether a faster model, streaming or (b) comes next.

## What Lamp could take on later

Whichever of (a) or (b) is chosen:

1. **`LampVoice` in Lamp's page host** (`LampPage.swift`, plus lamp.js): `voice`, `listen`, `speak` for any page,
   answered by the app around the page, plus a way for Swift to push partial words to the page.
2. **A `schema` passed through `/ai`**, which `AppAI.complete` already supports.
3. **A "quick" answer tier** (`model: 'quick'`) that Lamp maps to the fastest model the person's setup has.
4. **Streaming the spoken part**, once the gateway can stream.

Each touches lamp.js or LampSupport, which go to every app, so each is its own change with its own rule in the prompts.

## Open questions

- **Model for the trial**: set Home HQ to a fast OpenRouter model, or measure on the default first?
- **Away from home**: the page's `LampAI` fails off the Mac's Wi‑Fi. Is voice at home enough for v1?
- **On-device recognition only**: right for a household's words, but it rules out phones and languages without it.
- **Asking back vs doing the likely thing**: v1 asks for dates, people and duplicate names. A family may prefer the
  likely thing with Undo for groceries.
- **Not yet checked**: that a screen's Mac and iPhone builds carry the microphone and speech usage descriptions
  (GameKit's `{{USAGE}}`), and that WKWebView fires `visibilitychange` when the iPhone locks.
