# Home HQ by voice: a design for review

Status: proposal, nothing built. Written against `origin/main` at 52799211.

The goal: someone says "What do we need before school?", "Add milk" or "Mark the dishes done" into their phone, Home HQ
does it with its own data, the TV and every other copy of the screen show the change, and the phone answers out loud.

This is three problems, taken in this order:

1. **Actions**: Home HQ's changes are something an agent can call, not only buttons.
2. **The agent**: something turns a sentence into those calls and a short reply.
3. **Voice**: getting the sentence from a phone, and speaking the reply.

## What's there today (the facts this rests on)

- **Home HQ is a screen**: one web page (`Resources/Starters/homehq/Web/`), shown on the Mac, iPhone and iPad inside
  Lamp's common app around a page (`LampPage.swift`), and on TVs, Android and the Xbox in their own hosts. Every copy
  keeps the family's data the same through the wish's shared collections (`Web/js/sync.js`: `people`, `chores`,
  `groceries`, `events`, `ticks`, `stars`, …), merged item by item. **A change made on any copy reaches the TV with no
  new plumbing**: change `DATA`, call `App.emit('data')`.
- **The changes live inside click handlers.** Adding a grocery (`shopping.js` `add`), ticking a chore and giving its
  stars (`tasks.js` `complete`), adding an event (`calendar.js`, the New event sheet) each mix the data change with DOM
  work, timers and toasts. Nothing else can call them.
- **`LampAI` for pages** (`DeviceSupport.webJS`, written as `Web/lamp.js`): `ask(prompt, {data, system, json, model})`,
  `choose`/`decide`/`decideEach`, pictures. One whole answer per call: **no streaming, no tool calling, no
  conversation**. `json: true` only parses the reply; a `schema` in the body is dropped (`Store.appRequest`).
  Everything is answered by Lamp's gateway on the Mac. A copy away from the Mac's Wi‑Fi, or with Lamp closed, gets
  "Couldn't reach Lamp on your Mac".
- **Which model answers** is the app's own choice (`AppModels.load(project).text`), then Settings, then OpenRouter
  Sonnet when there's a key, or the builder's sign-in.
- **No speech for pages.** lamp.js has none; the page's web view grants no microphone. Native speech already works in
  three starters: Universal Remote (`VoiceListener.swift`: tap to talk, `SFSpeechRecognizer` on-device, ends on 1.3 s
  of silence, then `LampAI.decide`/`ask`), Wedding Words (`Speech.swift`: push-to-talk plus `AVSpeechSynthesizer`, the
  closest to "speak, think, speak back"), Transcriber (`SpeechAnalyzer`, continuous, Mac). Every generated Apple app
  already carries the microphone and speech-recognition reasons.
- **Phone pages from a QR code** are plain `http://<Mac's LAN IP>:478xx/`, served only while an app is on a TV or in
  the TV preview, talking over `ws://` to `LampRelay`. A browser won't open the mic there (`getUserMedia` needs a
  secure context). Lamp has no HTTPS for them.
- **`LampNative.call(name, args)`** reaches the app's own `Sources/Native.swift` on the Mac, iPhone and iPad (Home HQ
  already uses it for calendars and photos). It's request and answer only: Swift can't push to the page except through
  the wish.

## Decision 1: the agent runs in Home HQ's own page, on the copy that heard you

The phone is **Home HQ's own iPhone copy** (the same page, already laid out for a phone), not a separate iPhone app or
a QR page.

Why:

- **One implementation of every action.** The page already knows how stars follow a tick, that ticks are per day, how
  an example stops being an example, which aisle an item goes in. A native iPhone app writing the shared collections
  itself would have to copy all of that in Swift and keep it in step. Running the agent where `DATA` lives means an
  action is a function call.
- **The TV updates for free**: the action calls `App.emit('data')`, sync puts the items, every copy redraws.
- **The mic is native**: the iPhone copy has `LampNative`, so speech goes through Swift (as in Wedding Words), not the
  web view.
- **It costs the same to install** as a native iPhone app (Xcode, a team, the free account's 7 days and 3 apps), and
  Home HQ on the iPhone is already one of its places.
- **The Mac copy gets voice too**, the same way, which is how v1 is tried without a phone.

Turned down:

- *QR phone page*: no mic over HTTP. Giving Lamp HTTPS on the LAN (a local CA, a cert the phone trusts) is a large,
  separate project. A QR page could still *speak* (`speechSynthesis` isn't gated) but can't hear.
- *Native iPhone app in the wish*: duplicates the actions (above). It's the right home later for Siri ("Add milk to
  Home HQ" as an App Intent), since a screen's build doesn't make intents.
- *Agent on the Mac, phone only relays text* (a `requests` collection the Mac copy claims and answers): adds a hop and
  a "which copy answers" election, and the AI call goes to the Mac anyway. Worth it only if the phone's page can't run
  the agent, and it can.

## Decision 2: actions are one layer the views and the agent both call

New file `Web/js/actions.js`, loaded after `data.js` and before the views. Each action changes `DATA`, calls
`App.emit('data')`, and returns what it did and how to undo it. The views' click handlers call the same functions and
keep only their DOM work (rows, timers, toasts).

```js
App.actions = {
  addGrocery:   { about: 'Put something on the shopping list',
                  args: { name: 'string', qty: 'number?', store: 'string?', note: 'string?' },
                  run: function (a) { /* catalog name and aisle, then aisleByAI as today; an open item of the same
                                         name gets its quantity raised instead of a second row */ } },
  checkGrocery: { about: 'Tick an item off the list', args: { id: 'string' }, run: … },
  completeChore:{ about: 'Mark a chore done today; `by` is who did it (needed for an Anyone chore that earns stars)',
                  args: { id: 'string', by: 'string?' }, run: … },
  undoChore:    { … },
  addEvent:     { about: 'Add an event to the family calendar shown on Home HQ',
                  args: { title: 'string', start: 'ISO date', minutes: 'number?', people: '[person id]?' }, run: … }
};
// run returns { said: 'Added milk to Dairy', undo: function () { … } } or throws a plain sentence ("There's no chore
// called dishes").
```

Reads aren't actions in v1. The agent is given a compact state with the request (below), because Home HQ's data for
"today and tomorrow" is small. That keeps v1 to one model call per sentence.

Ids, not names, go in args: the model picks from the state's ids, so "the dishes" becomes `chore:"c7"`, and an id that
isn't there fails loudly. Calendar writes go to Home HQ's own events, as the New event sheet does today. The
family's real calendar (EventKit) stays read-only.

## Decision 3: one call per sentence, a plan back as JSON

```
page  ── LampAI.ask(request, { system, data: state, json: true }) ──▶  Lamp gateway  ──▶  model
      ◀── { "say": "…", "do": [ { "action": "addGrocery", "args": { … } } ], "ask": false } ──
```

- **system**: what Home HQ is, the actions (generated from `App.actions`' `about` and `args`), the rules: use ids from
  the state, never invent a person, ask back when a chore or person is unclear, `say` is one or two short spoken
  sentences with no lists or emoji.
- **data** (fenced as outside text, as `ask` already does): today's and tomorrow's events (title, time, who, place),
  this part of the day's chores with done/who/stars, the open shopping list, the weather line, the people, and the
  last three exchanges (for "who did it?" → "Maya").
- **reply**: `say` is spoken; `do` is run in order; `ask: true` means the phone listens again straight after
  speaking. An action that throws stops the rest, and its sentence replaces `say`.
- **"Undo"** said next undoes the last batch (the `undo`s returned), with no model call.
- **What the screens show**: the copy that heard you shows the transcript and the reply in a sheet. The others just
  change, as when someone taps.

Question 1 ("What do we need before school?") is a read: no `do`, a `say` built from the morning's events, chores and
the weather advice already on Today.

## Decision 4: voice through `Native.swift`, tap to talk

Three calls in Home HQ's `Sources/Native.swift`, built from Universal Remote's listener and Wedding Words' speech:

- `listen` → starts on-device recognition (`SFSpeechRecognizer`, `requiresOnDeviceRecognition` when supported;
  `SpeechAnalyzer` where available), resolves with the final text after 1.3 s of silence or a `stop`. Contextual
  strings: the people's names, the chores, the list.
- `stop` → ends listening early (the button tapped again).
- `speak {text}` → `AVSpeechSynthesizer`, resolves when done. Listening never starts while it speaks.

The page shows a mic button only where `LampNative.available` and `listen` exist (Mac, iPhone, iPad): on the rail,
and big at the bottom of the phone layout. Tap, talk, see the words, hear the reply. No wake word, no always-on mic.

## What Lamp itself needs (to make this reusable)

v1 needs **none** of these: it is Home HQ's own code on today's `LampAI.ask`. They're the pieces to lift out once v1
shows it's worth it, so the next app gets "talk to it" without copying Home HQ:

1. **`LampVoice` in Lamp's page host** (`LampPage.swift`, plus lamp.js): `LampVoice.listen()`, `.speak(text)`,
   `.available`, answered by the app around the page as `lampGateway` is, so a page needs no `Native.swift` and no
   compile. With it, a way for Swift to push partial words to the page (today only the wish can). The Swift side as
   `LampVoice` in `LampSupport.swift` for native apps, replacing the copies in the starters.
2. **`LampAI.act(request, { actions, state, history })`** in lamp.js and LampSupport: the prompt above, args checked
   against the declared shapes, actions run, undo kept, `{ say, done, ask }` back. Home HQ's `actions.js` becomes its
   input. A second round when an action returns data the model asked for gives real tool use without the gateway
   learning tool calling.
3. **A `schema` passed through `/ai`** (`Store.appRequest` drops it today, while `AppAI.complete` already sends
   OpenRouter `response_format`), so `act` gets valid JSON every time instead of parsing hope.
4. **A "quick" answer tier** an app can ask for (`model: 'quick'`), mapped by Lamp to the fastest model the person's
   setup has. A voice turn wants about a second of thinking, not Sonnet's several. Which model that is, is Lamp's
   choice and the person's in Settings, not the page's.
5. **Streaming the spoken part** (`ask` with `onText`): speak the first sentence while the rest arrives. Needs the
   gateway to stream (it sends one fixed-length answer now). Last, because it only pays off once 1–4 are in.

Each touches lamp.js, which goes to every page, and LampSupport, which goes to every app, so each is its own change
with its own rule in the prompts (`TVTemplate.webAI` and the `app-ai` skill), not part of the Home HQ change.

## The smallest first version worth trying

Home HQ only, no Lamp changes, the Mac copy first:

1. `actions.js` with `addGrocery`, `checkGrocery`, `completeChore`, `addEvent`; `shopping.js`, `tasks.js` and
   `calendar.js` call it.
2. The agent: state, prompt, one `LampAI.ask(json:true)`, run, undo.
3. `listen`/`stop`/`speak` in `Native.swift`; the mic button and the transcript sheet.
4. A typed box in the same sheet (same agent, no mic), so it can be tried and checked where a mic can't be used.

Then the same build on an iPhone as Home HQ's iPhone place. Roughly two days for 1–4 and the checks, plus the phone.

**How we'll know it's worth more**: a fixed list of about 20 sentences against the example family ("add milk", "add two
milks and eggs", "mark the dishes done", "Otto fed Biscuit", "what's on after school", "move soccer to five" (it can't
yet, and should say so), "who's at the dentist"), each with the actions it should produce. Run against the real
model, record what each produced and how long it took from tap to first word. Keep it if most are right and the time
is short enough to talk to. The results decide whether 3–5 above come next.

## Open questions for review

- **Model for v1**: the app's own model choice already exists. Set Home HQ to a fast OpenRouter model for the trial, or
  measure on the default first?
- **Phone away from home**: the page's `LampAI` fails off the Mac's Wi‑Fi. The iPhone's own-key fallback
  (`LampDirect`) is Swift-only. Is "voice works at home" enough for v1? (We think yes: the TV is at home.)
- **Mic in the page's host**: v1 goes through `Native.swift`, so it doesn't depend on WebKit's media capture in
  `LampPage`. Not yet checked: that a screen's Mac and iPhone builds get the microphone and speech reasons (GameKit's
  `{{USAGE}}`), and that the page's mic button shows only where `listen` is registered.
- **Who's talking**: v1 doesn't know who holds the phone, so "I did the dishes" asks who. A copy could remember its
  person (`App.me()` is a device). Later.
- **Ambiguity vs speed**: always asking back when unsure costs a turn. Is "do the likely thing and offer Undo" better
  for a family? v1 asks only for stars (who did an Anyone chore) and for a chore it can't match.
