# `LampAI.act`: an agent loop for the apps Lamp makes

Status: built for pages, with OpenRouter answering. This is option (b) of [the Home HQ voice design](README.md): a small
piece of Lamp first, with Home HQ's agent on top of it.

## What it is

An app's page hands `LampAI.act` a request in the person's words, the reads and writes it offers, and what the model
should know. `act` loops until the model gives a reply or a limit stops it:

1. The model picks calls.
2. The page checks and runs them.
3. The model sees the results.

The page always runs its own tools and keeps the turn. Lamp's gateway only talks to the model, one step per request,
and keeps nothing between steps.

**What's in this change**

- Pages only (`Web/lamp.js`): screens, web games, web apps and TV apps on the Mac, iPhone, iPad, Android, Samsung, LG
  and the Xbox.
- OpenRouter is the only route that answers. Every other route says plainly that it can't, yet.

**Not in it**: native apps (LampSupport.swift), the Roku, a phone away from the Mac's Wi‑Fi, and the other text routes
(see "Routes").

## Who holds what

The gateway is stateless, so it can only enforce what a single request shows. Everything that spans a whole turn
belongs to the page.

| Guarantee | Held by | How |
| --- | --- | --- |
| Tools' names and argument shapes | Gateway | Checked on every request. At most 24 tools. `reply` is Lamp's own. |
| Calls the model returns fit their tool | Gateway | Each call is checked against its tool's shape. A bad answer is asked for once more with the reason, then returned as a reply that says it couldn't. The page never sees a call that doesn't fit. |
| At most 8 calls per answer | Gateway | Applies to every route. |
| Earlier call ids are unique | Gateway | A duplicate id gets a 400. The model's calls get ids of Lamp's own (`s<step>c<n>`). |
| A reply-only step after three steps | Gateway and page | A request with three steps behind it (`maxSteps - 1`) is answered with a reply only: `tool_choice: "none"`, and any call refused. A fourth is a 400. The page also sends `final` on that step. |
| One route for the whole turn | Gateway, from the page | The first answer carries the route's id. The page sends it back on every later step. A route that can't answer any more gets a 409, never a quiet switch. |
| Writes per turn (6), the deadline (25 s), cancel | Page | Each step's request carries only the seconds left. The gateway turns that into one absolute deadline for the step, shared by every attempt it makes. |
| A write checked right before it runs | Page | See "The loop". |
| Repeats | Page and app | See "Repeats". |

## What an app declares

```js
var turn = LampAI.act('Add milk', {
  about: 'Home HQ, a family dashboard: …',          // the app, its rules for asking back
  context: { people: [ … ], today: '2026-10-28' },   // small; sent as outside text
  tools: {
    groceries:  { about: 'The shopping list', reads: true, args: { all: { type: 'boolean', optional: true } },
                  run: function (args, call) { … } },
    addGrocery: { about: 'Put something on the list',
                  args: { name: { type: 'string' }, qty: { type: 'integer', min: 1, max: 99, optional: true } },
                  check: function (args, call) { return null; /* or why not, as a sentence */ },
                  run:   function (args, call) { … /* the item as it is after */ } }
  },
  history: [ { said: 'Who did it?', heard: 'Maya' } ],   // the app keeps it; the last 3 are sent
  limits: { steps: 4, writes: 6, seconds: 25 },          // the defaults, which are also the maximums
  turn: 'optional, to retry a turn',
  onStep: function (s) { /* { kind, name, args } before a call; with result after a write */ }
});
turn.result.then(function (r) { r.reply; r.ask; r.done; r.failed; r.skipped; r.reads; r.stopped; r.error; });
turn.cancel();
```

- **Argument shape**:
  - `type` is one of `string`, `integer`, `number`, `boolean`, `date` (YYYY-MM-DD), `datetime` (ISO 8601 with
    offset) or `list`.
  - The other keys are `oneOf` (strings), `min`, `max`, `optional`, `about` and `of` (a list's item shape).
  - No other keys are allowed, so every route can take every shape.
- **Reads and writes**: `reads: true` marks a read. Anything else is a write.
- **`run(args, call)`**: `call` has `turn`, `step`, the call's `id`, and, for a write, `key` (below).
- **What goes back to the model**: a result is at most 4 KB of JSON, cut with a note. `throw LampAI.refuse('…')`, or any
  thrown error, fails the call, and the model hears why.
- **What comes back to the app**: `result` never rejects. `done`, `failed` and `skipped` are what the page ran, never
  the model's own account. A `done` entry carries `partly` when `run` said its change only partly went through.

## The loop (lamp.js)

1. **A step**: one `/ai/act` request carrying the request, the tools' shapes, the context, the history, every earlier
   call with its result, the route once known, and the seconds left.
2. **Reads** in a step run together.
3. **Writes** then run one after another, in the model's order. Right before each one:
   - The turn isn't cancelled or over.
   - The call names a declared tool, with nothing undeclared and nothing required missing. The gateway has already
     checked the shapes.
   - It isn't a repeat (below).
   - The turn has writes left.
   - Its `check` passes, run then, after the writes before it.

   A write that fails any of these is in `failed`. The writes after it in that step aren't run: they're in `skipped`,
   and the model is told they were skipped.
4. **The next step** carries every call's result: `ok` with a `value`, or `error`, or `skipped`.
5. **Done** when the answer is a reply, or a limit stops it: `stopped` is `steps`, `time`, `cancelled`, `unreachable`
   or `error`, with what was done so far.

### One deadline, every layer

The turn's deadline (25 s at most) is set when it starts, and every layer works to it:

- The page stops the turn there.
- Each step's request is given only the time left. That's the XHR's timeout, and the relay through the app around the
  page is told it too.
- lamp.js's `send` doesn't start another try after the deadline. It still retries the next way to the Mac, and once
  more after three seconds, when a try fails or times out, but only while time is left. So one step can reach the
  gateway more than once. That's safe, because a step only asks the model and changes nothing.
- The gateway turns the seconds it's given into one deadline for the step. A call asked for again and each content-filter retry, with its wait, get only what's left. None starts with less than a second left (a 504).
- The page reads the clock itself (`Date.now()` against the deadline) before it takes an answer and right before each read, each check and each write. It doesn't rely only on the deadline's timer, which can run late when a slow write carries the turn past the deadline.

The Mac's app around a page waits up to 240 s on its own request to Lamp. An answer that comes after the deadline is
dropped by the page and runs nothing.

### Cancel

`turn.cancel()` ends the turn at once: `result` resolves with `stopped: 'cancelled'` and what was done. The page
checks for a cancel, and the clock, before every read and every write runs, so a step already under way runs nothing more. A write
that has already started finishes, since writes are the app's own and quick. Whatever arrives afterwards, an answer
or a result, is dropped.

### Repeats

What holds, and nothing more is promised:

- **The same write, with the same arguments, in the same turn, while this copy of the page is open, runs once.** A
  later ask gets the first result back, marked `repeat: true`. The same holds for a turn tried again with `turn:` set
  to the same id.
- **`call.key` is stable** for the same turn, tool and arguments. An app that makes the ids of what it adds from the
  key, or keeps the key on the change, finds that change when the same request comes again: after a reload, or on
  another copy that has synced it. That's what makes a retry safe across reloads, and it's the app's to do.
- **Nothing promises exactly once.** For example, a write that ran just before the page closed, and whose result never
  reached the model, can be asked for again in a new turn with a new key. The app's own `check` (for instance, "already
  on the list") is what catches it.

## The gateway: `POST /ai/act`

`Store.appRequest` branches on `/ai/act` before its prompt check, because a step has no `prompt`. The token, the app's
model choice and the cost record are the same as for `/ai`. The route is listed in `handleAI`'s paths.

**Request**

```json
{ "request": "…", "about": "…", "now": "lamp.js's present()", "context": {},
  "tools": [ { "name": "addGrocery", "about": "…", "reads": false, "args": {} } ],
  "history": [ { "said": "…", "heard": "…" } ],
  "steps": [ { "calls": [ { "id": "s1c1", "name": "groceries", "args": {} } ], "results": [ { "id": "s1c1", "ok": true, "value": [] } ] } ],
  "route": "sonnet", "seconds": 21, "final": false }
```

**Answer**: `{ "calls": [ … ], "route": "sonnet" }` or `{ "reply": "…", "ask": false, "route": "sonnet" }`.
`{ "probe": true }` answers `{ "act": true|false, "route": …, "why": … }`.

**Checks** (a 400 with a sentence, unless noted):

- The body is at most 256 KB (413 when larger).
- There's a request and 1 to 24 tools.
- Tool names match `^[a-zA-Z][a-zA-Z0-9_]{0,40}$`, aren't `reply`, and aren't used twice.
- Argument shapes use only the keys above.
- At most 3 steps are behind the request, each with 1 to 8 calls, and all call ids are unique.

**What the model is told**: the app's `about`, then Lamp's rules:

- Look before acting, and use ids as given.
- Change only what was asked, and ask back when unclear.
- Reads may batch; writes run in order, each checked.
- Never say something was done unless its result says so.
- Finish with `reply`, in short sentences that can be spoken.

`context` and every result go in fenced as outside text, the same way `ask`'s `data` does.

## Routes

| Route | What a step does |
| --- | --- |
| **OpenRouter** (`.openRouter`, the default with a key) | Real tool calling. `provider.require_parameters: true`, so only providers that take the tools and `tool_choice` as sent are used. `tool_choice` is `"auto"`, or `"none"` for the reply-only step. Recorded for Sonnet 5.5 on 2026-10-27: `"required"`, and naming a tool, find no provider ("No endpoints found that support the provided 'tool_choice' value"). The Anthropic models offered for apps take only `"auto"` and `"none"`. Lamp's `reply` tool is offered, but can't be required, so an answer of words without a call is the reply, and whether it asks something is read from its final question mark. **That's a workaround** for the missing `"required"`. |
| **Claude Code, Codex** (`.engine`) | **Unsupported for now**: a 501 saying so, and `isAvailable('act')` is false. When added, they reuse the existing `--json-schema` and `--output-schema` paths in `AppAI.viaEngine` through `AppAI.complete(…, schema:, via:)`, with a plan schema of calls (each call's `args` a JSON string checked against its tool) or a reply. Each step pays an engine's start-up. |
| **A GGUF model on this Mac** (llama-server) | Unsupported for now. When added: the same plan through `response_format: json_schema`, which `viaOpenAICompatible` already sends. |
| **An MLX model** (mlx_lm.server) | Unsupported. It has no `response_format`. It would need a labeled JSON-prompt fallback checked the same way, or it stays unsupported. |
| **pi** | No route, as for any app text. |
| **A phone away from the Mac** (`LampDirect`) | Not offered. Pages never use it. |

## Available means all three

`LampAI.isAvailable('act')` posts `{ probe: true }` to `/ai/act` itself, so it's true only when all three hold:

1. **The SDK has it**: this lamp.js has `act`. An older one has no `'act'` and answers false.
2. **The host lets the route through**: the app around the page lists `/ai/act` (`LampPageGateway.routes` in
   `LampPage.swift`, `LampPageGateway.kt` in `GameAndroid.swift`, the TV preview's list). An older host answers 404
   "Not found", which is false, whatever the gateway behind it could do.
3. **The route can take it**: the gateway answers `act: true` only for an OpenRouter route with a key, after setup.

Samsung and LG TVs and the Xbox already pass any `/ai` path. Lamp's own files in a page's app are hashed into its
kit version (`GameKit`), so a page built by an older Lamp is rebuilt with the new host.

## Rules and docs

- `TVTemplate.webAI`, the rule every page's agent reads, gets one sentence: use `LampAI.act` and read "Doing things
  for the person" in the web-app skill first.
- The `web-app` skill's "Doing things for the person" is the one recipe:
  - Show the feature only where it's available, and keep the buttons.
  - Small reads and writes; a `check` on each write that looks the item up fresh by id.
  - Ids from `call.key`.
  - Say what happened from `done`, `failed` and `skipped`, never from `reply`.
  - Undo only what's unchanged since.
  - `onStep`, and cancel when the page is closed or hidden.
- The `app-ai` skill gets one line: `act` is for pages only for now.
- `act`'s comment in lamp.js gives its shapes.
- `docs/development/engines.md` ("An app's own agent loop") and `devices.md` (the hosts' route list).

## Tested

- `AppActTests` (Swift) runs real OpenRouter answers recorded on 2026-10-27 through the gateway's parser. It also
  feeds answers the model can't be relied on to produce: calls that don't fit, `reply` among other calls, over the
  cap, after the last step. It covers the reserved and duplicate names and ids, and the OpenRouter body
  (`require_parameters`, `"auto"` and `"none"`, the fence).
- `ActLoopTests` (lamp.js in JavaScriptCore, with a stand-in for Lamp):
  - Reads run first; each write is checked right before it runs.
  - A failed write skips the ones after it.
  - A repeat, or a retried turn, runs once.
  - The write limit and the reply-only fourth step hold.
  - Nothing runs after a cancel or the deadline.
  - The route is kept for the turn.
  - `isAvailable('act')` is false behind an old host or a route that can't take it.
