# `LampAI.act`: an agent loop for the apps Lamp makes

Status: proposal, nothing built. Written against `origin/main` at 487f21e2. It's option (b) of
[the Home HQ voice design](README.md), the one chosen: a small piece of Lamp first, then Home HQ's agent on top of it.

## What it is

An app's page hands `LampAI.act` a request in the person's words, the reads and writes it offers, and what the model
should know. `act` runs a short loop until the model gives a reply, or a limit stops it:

1. The model picks calls.
2. The page checks and runs them.
3. The model sees the results.

The page always runs its own tools. Lamp's gateway only ever talks to the model, one step at a time, and keeps no
state between steps.

Scope of the first change:

- **Pages only** (`Web/lamp.js`: screens, web games, web apps and TV apps on the Mac, iPhone, iPad, Android, Samsung,
  LG and the Xbox).
- **Not yet**: native apps (LampSupport.swift), the Roku (BrightScript), and a phone away from the Mac's Wi‑Fi.

Those are listed under "Later" at the end.

## What an app declares

```js
var turn = LampAI.act('Add milk and mark the dishes done', {
  // What the app is, for the model, in the app's own words (goes before Lamp's own rules).
  about: 'Home HQ, a family dashboard: the day, the calendar, chores and the shopping list.',

  // What the model should know at the start, small. Outside text, fenced as LampAI.ask's `data` is.
  context: { today: '…', people: [ … ] },

  tools: {
    chores: {
      about: 'The chores of a part of the day, with who, stars and whether each is done today.',
      reads: true,
      args: { part: { type: 'string', oneOf: ['morning', 'afterSchool', 'evening', 'all'], optional: true } },
      run: function (args) { return App.read.chores(args); }        // a value, or a Promise of one
    },
    completeChore: {
      about: 'Mark a chore done today. `by` is who did it: needed for an Anyone chore that earns stars.',
      args: { id: { type: 'string' }, by: { type: 'string', optional: true } },
      check: function (args) { return App.check.completeChore(args); },  // null when fine, else a sentence
      run: function (args, call) { return App.act.completeChore(args, call); }
    }
  },

  history: [ { said: 'Who did the dishes?', heard: 'Maya' } ],   // the app keeps it; at most the last 3
  limits: { steps: 4, writes: 6, seconds: 25 },                // these are the defaults and also the maximums
  turn: 'optional id, to retry a turn without repeating its writes',
  model: 'optional, as in LampAI.ask',
  onStep: function (step) { /* { kind: 'read' | 'write', name, args } before it runs; { …, result } after */ }
});

turn.result.then(function (r) { … });
turn.cancel();
```

### A tool

- **`about`**: one line for the model, saying what it does and when to use it.
- **`args`**: a small schema that's easy to write in ES5. Lamp turns it into JSON Schema for the model, and also
  checks every call against it before the page sees the call.
  - `type` is one of `string`, `integer`, `number`, `boolean`, `date` (`YYYY-MM-DD`), `datetime` (ISO 8601 with
    offset), or `list` with `of`.
  - `oneOf` gives the allowed values. `min` and `max` bound numbers and list lengths. `optional` marks an argument that
    can be left out. `about` adds a line for the model.
  - No other keys, so every route can take every schema. Arguments not declared are refused.
- **`reads: true`** marks a tool that changes nothing. Every other tool is a write. Writes count against
  `limits.writes`, and their results are what `done` and `failed` report.
- **`check(args)`**: writes only, optional. It runs for **every** write of a step before **any** of them runs. When
  any check returns a sentence, no write of that step runs, and each sentence goes back to the model as that call's
  result. This is how an app checks a write against its data at that moment.
- **`run(args, call)`** does the work and returns a value, which goes back to the model as JSON (at most 4 KB, cut
  with a note when longer). Throwing `LampAI.refuse('sentence')` or any error is a failed call; the message goes back
  to the model. `call` carries:
  - `call.turn`: the turn's id.
  - `call.key`: stable for the same turn, tool and arguments, so an app can build ids for what it makes and retries
    don't duplicate it.
  - `call.step`: the step number.

### What comes back

`turn.result` resolves, and never rejects, with:

```js
{
  turn: 't…',
  reply: 'Maya has piano at 3:45.',   // the model's last words, or '' when it stopped early
  ask: false,                         // true: the reply is a question back; the app listens or waits again
  done:   [ { name, args, result } ],          // writes that ran and returned
  failed: [ { name, args, reason } ],          // writes refused by check, by run, or by Lamp's own checks
  reads:  [ { name, args } ],
  stopped: null,   // or 'steps' | 'writes' | 'time' | 'cancelled' | 'unreachable' | 'error'
  error: ''        // the message, when stopped is 'unreachable' or 'error'
}
```

`done` and `failed` come from what the page ran, never from the model. An app saying "Added milk" builds it from
`done`. The rule for pages (below) tells the agent so, and tells it never to speak the model's `reply` as proof that
something happened.

### What lamp.js does in the loop

- **Steps.** Each step is one `/ai/act` request carrying everything so far: the request, the context, the tools, and
  every earlier call with its result. The gateway answers with calls to make or a reply.
- **Checks, before anything runs:**
  - The call names a tool that exists and its arguments fit the declared shape. A call that doesn't fit fails with a
    sentence the model sees, and doesn't count as a write.
  - The step stays within `limits.writes`. Writes over the limit are refused as "Over this turn's limit" and nothing
    of that step runs.
  - Each write's `check` passes, all of them before any `run` (above).
- **Order.** The calls of a step run in the order the model gave. A step that mixes reads and writes runs the reads
  first.
- **Repeats.** The same write with the same arguments in the same turn doesn't run again: it gets its first result
  back, marked `repeat: true`. With `turn` passed in again (a "Try again"), the writes that already ran in that turn are
  repeats too, while this copy of the page still remembers them. After a reload it's the app's `call.key` ids that keep
  a retry from duplicating anything.
- **Limits.**
  - `steps` counts calls to the model. The last allowed step is asked for a reply only, with no tools.
  - `seconds` is the whole turn. On time, the turn stops between steps, and a model answer that comes after it is
    dropped.
- **Cancel.** `turn.cancel()` stops the turn between steps. A write already running finishes, since an app's writes
  are local and quick. Any answer for this turn that arrives after the cancel is dropped and runs nothing.
  `result` then says `stopped: 'cancelled'` with what was done.
- **Failures.** Can't reach Lamp, or the model fails: the turn stops, with `stopped: 'unreachable'` or `'error'` and
  everything done so far. One step never runs twice because of a network retry. lamp.js's existing three-second
  retry, which only happens when the request never reached Lamp, is the one exception.

## The gateway route: `POST /ai/act`

### Request

```json
{
  "request": "Add milk and mark the dishes done",
  "about": "Home HQ, a family dashboard: …",
  "context": { … },
  "tools": [ { "name": "completeChore", "about": "…", "reads": false, "args": { … } } ],
  "history": [ { "said": "…", "heard": "…" } ],
  "steps": [ { "calls": [ { "id": "c1", "name": "chores", "args": { … } } ],
               "results": [ { "id": "c1", "ok": true, "value": { … } } ] } ],
  "final": false,
  "model": "optional"
}
```

### Answer

```json
{ "calls": [ { "id": "c2", "name": "completeChore", "args": { "id": "c7", "by": "maya" } } ] }
```

or

```json
{ "reply": "Done.", "ask": false }
```

With `final: true`, the answer is always a reply.

### What the route does

- **Where it lives.** `Store.appRequest`, beside `/ai` and `/ai/decide`, with the same token, the same per-app model
  choice (`AppModels.load(project).text`) and the same cost record. It's added to `handleAI`'s list of paths.
- **Checks before any model call:**
  - At most 24 tools, with names matching `^[a-zA-Z][a-zA-Z0-9_]{0,40}$`.
  - Argument shapes use only the keys above.
  - At most 6 steps of history.
  - The request body is at most 256 KB.
  - Anything else is a 400 with a sentence.
- **Outside text stays outside.** `context`, every result `value` and `history` go to the model fenced as outside
  text, using the same fence and rules as `ask`'s `data`. The request is the person's own words; the rules still say
  it can't widen what the tools allow.
- **What the model is told.** `about`, then Lamp's own rules:
  - Use the tools, and use ids from what was read.
  - Ask back rather than guess.
  - Reply in one or two short sentences that can be spoken, without lists or emoji.
  - Never say something was done unless its result says so.
  - Stop once the request is met.

  The app's `about` can't take these rules away; it comes before them.
- **Calls it hands back are checked first.** Each call the model returns is checked against its tool's shape. A bad
  one is asked for again once, with the reason, as `ask` already does for bad JSON. If it's still bad, the answer is a
  reply saying it couldn't do that, and the page sees no call.
- **No state.** Every request carries everything so far, so any host can send it, nothing is held between steps, and
  a lost request loses nothing. The cost is the context sent again each step. For the turns a home assistant runs
  (4 steps of small JSON) that's a few thousand tokens.
- **Limits.** The gateway holds its own copy: with `steps` already at 4, it answers as if `final` were true. A page
  can't run past the limits by leaving the page's own checks out.

## Tool calling, or a fallback, per text route

`AppAI.dispatch` picks the route as it does for `ask`. `act` adds one function per kind of route, all ending in the
same answer shape.

| Route (`TextRoute.kind`) | How a step is asked | Notes |
| --- | --- | --- |
| **OpenRouter** (`.openRouter`, the default with a key) | **Real tool calling.** Each tool becomes an OpenAI-style function, plus Lamp's own `reply` function (`text`, `ask`). `tool_choice: "required"`, so every answer is either calls or a `reply` call. Earlier steps go back as assistant `tool_calls` and `tool` messages. With `final`, `tool_choice` names `reply`. | Every model offered for apps' text through OpenRouter (Lamp's Anthropic list) takes tools. A model that answers with prose and no call is asked once more, the same as a bad call. The content-filter retry in `viaOpenRouter` applies too. |
| **Claude Code** (`.engine(.claude, …)`, a sign-in) | **A JSON plan held to a schema.** One `-p` run per step, `--json-schema` with the plan's shape (below), and the tools and earlier steps written into the prompt. | A run has no way to call back into the page in the middle, so it plans one step at a time. Each step pays the start-up of a run (several seconds; not yet measured), too slow to talk to. The pages rule says so, and so does Settings' note on this route for apps that use `act`. |
| **Codex** (`.engine(.codex, …)`) | The same JSON plan, `--output-schema`. | Same cost as Claude Code. |
| **A model on this Mac** (`.localModel`, llama-server with `--jinja`, or mlx_lm.server) | The same JSON plan, as `response_format: json_schema`, which `viaOpenAICompatible` already sends. | llama-server can take OpenAI tools. Measure that before switching this route to it, since small models follow a schema more reliably than they pick tools. |
| **pi** (`.engine(.pi, …)`) | No route, as today: "needs text". | |
| **The phone away** (`LampDirect`) | Not offered: "Doing things for you needs this device to reach Lamp on the Mac." | Pages never used it anyway. |

### The plan's schema (every fallback)

```json
{ "type": "object", "additionalProperties": false, "required": ["calls", "reply", "ask"],
  "properties": {
    "calls": { "type": "array", "maxItems": 8, "items": { "type": "object", "additionalProperties": false,
               "required": ["name", "args"],
               "properties": { "name": { "type": "string", "enum": ["…the tool names…"] },
                               "args": { "type": "string", "description": "The arguments as a JSON object" } } } },
    "reply": { "type": "string" },
    "ask":   { "type": "boolean" } } }
```

- `args` is a JSON string, so one strict schema fits every tool. The gateway parses it and checks it against the tool's
  own shape, as above.
- `calls` must be empty for the answer to be a reply.
- With `final`, `calls` gets `maxItems: 0`.

Both kinds of route meet in one Swift type, `AppAI.ActStep` (calls or a reply). Lamp's tests can then feed either one
recorded answers, the same way.

## The hosts: letting `/ai/act` through

Each host lets only the AI routes through to Lamp. `/ai/act` goes on each list in the same change:

| Host | Where its list is |
| --- | --- |
| Mac, iPhone and iPad app around a page | `LampPageGateway.routes`, `Resources/GameKit/apple/LampPage.swift:82` |
| Android and Android TV | `routes`, `GameAndroid.swift:188` (`LampPageGateway.kt`) |
| Lamp's TV preview | `TVPreview.swift:290` |
| The gateway | `Store.handleAI`'s `paths` |
| Samsung and LG TVs | Already sends any path to the Mac's addresses, with CORS |
| The Xbox | Already lets any `/ai` path through (`lamp_web_host.cpp:332`) |

Apps already installed get the new host on their next build, the same way a change to `LampPage.swift` reaches
them today. Bump whatever tells Lamp an installed page's host is out of date, so `act` isn't refused on an old one.
Until then, `LampAI.isAvailable('act')` answers false there. It's a new capability for `/ai/status`:

- True when text can answer and the route isn't pi.
- `'act'` is a new value for `isAvailable`, not a new tier in Settings.

## The rules for pages, and the docs

### The prompt

`TVTemplate.webAI` (the rule every page's agent reads) gets one sentence that points to the skill:

> `LampAI.act(request, { tools, … })` lets the person ask the app to do things in their own words. Read
> "Doing things for the person" in the web-app skill before using it.

### The `web-app` skill (`Resources/skills/web-app/SKILL.md`)

A new section, "Doing things for the person". This is the one place the recipe lives:

- Declare small reads and writes over the app's own data, with ids in and ids out. There's no "do anything" tool.
- Every write has a `check` against the data as it is then. It looks its item up fresh by id, and it makes new items'
  ids from `call.key`.
- Say what happened from `done` and `failed`, never from `reply`.
- Undo only what's unchanged since.
- Cancel the turn when the page is hidden.
- Show each step while it runs (`onStep`).
- Check `isAvailable('act')` and keep the app's buttons for everything.
- Nothing destructive in the first version of an app's tools without an Undo the person can see.

### Other guidance

- **The `app-ai` skill**, for native apps: one line saying that `act` is for pages for now, and that a native app
  doing this follows the web-app section's rules with `LampAI.ask(…, as:)`. It doesn't teach the loop twice.
- **lamp.js's own comment** on `act`: what's above, the way `ask`'s comment documents `ask`. The rule tells the agent
  to read it.

### Docs for people working on Lamp

- **`docs/development/engines.md`**, under "What answers apps": `/ai/act`, the table of routes above, that the gateway
  keeps no state, and where its limits live.
- **`docs/development/devices.md`**, in "What a page can reach" and the Android paragraph: `/ai/act` is among the AI
  routes the hosts let through.

### Before opening the PR

- Run `git grep` for `/ai/decide`, `routes`, `webAI` and `LampAI.isAvailable`, so that every list and rule that names
  the AI routes says the same.
- Check that the README's list of what generated apps get still matches.

## How it's checked before Home HQ uses it

- **Recorded answers.** For OpenRouter and the JSON plan alike, real answers recorded once with their date are fed to
  `AppAI.ActStep`'s parsers. Covered: a call, a bad call, prose with no call, a reply, and `final`.
- **lamp.js's loop, in the TV preview, with a made-up app.** These are also faked model answers, testing what a model
  can't be relied on to produce:
  - Checks run before any write.
  - A refused write stops its whole step.
  - Repeats and `turn` retries.
  - Each limit.
  - Cancel, and a late answer, never run anything.
  - `done` and `failed` match what ran.
- **Live, on OpenRouter and on one model on this Mac**: a dozen requests against a made-up app, recording calls per
  turn and the time per step. Claude Code and Codex get one turn each, to show they work and to measure how slow they
  are.
- **The engines rule doesn't apply.** `act` isn't a tool for the building agent, so no change to `lamp-tools.json` or
  `Agent.run`. The PR says that.

## Later

- **The same in LampSupport.swift for native apps**, as `LampAI.act(request, tools:)` with Swift closures and the same
  route.
- **Away from the Mac**: `LampDirect` running the OpenRouter version of a step with the phone's own key.
- **Streaming the reply**, once the gateway can stream.
- **A quicker model tier for voice**, Lamp's choice, not the page's.
- **Tool calling on llama-server**, if the measurements say small models do better with it.
