# Agent engines

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

## Keep the agent harnesses in step

Lamp drives three coding agents, chosen in Settings → Building: **pi** (bundled), **Claude Code** and
**Codex**. They are set up in `Sources/Lamp/Engines.swift` (`Agent.run`), one `case` per engine, and
the output of each is read by its own parser there (`parseClaude`, `parseCodex`, and pi's in
`Agent.parseLine`). When the Mac already has Claude Code or Codex (on the person's PATH, or inside the Claude or
ChatGPT app), Lamp runs that copy with the person's own sign-in and folder (~/.claude, ~/.codex), so nobody who
already uses one downloads or signs in again; Lamp's runs are kept apart from their setup by their flags
(`--restricted`, `--ignore-user-config`, …). Only when there is none does Lamp download its own (`EngineInstall`),
checked (the vendor's checksum and Developer ID team) and updated daily, with its own folder for sign-in and
state (`EngineInstall.environment`: `CLAUDE_CONFIG_DIR`, `CODEX_HOME`). Which copy is used is decided in one
place, `EngineInstall.path(for:)`: every place that runs one takes its path from there and merges
`EngineInstall.environment`, and reads the engine's state from `EngineInstall.configFolder`. Never look for a copy
anywhere else. `updates/api/engines.js` can hold Lamp's own copy back to a version.

A capability given to one engine must be given to all of them that can take it, in the same change:

- **Tools the agent calls** (`look_at_app`, `use_app`, `plan`, `delete_file`, `make_art`, `assets`, `offer_setup`, `make_app_for`, `remove_app`, `rename_app`, `connectors`, `lampify`, `network_devices`, `device_integration`, `device_permission`, `ask`, `progress`, `write_wish`, `read_skill`, the version tools, the notes tools): their
  names, descriptions and schemas live once, in `Resources/lamp-tools.json`. pi's extension
  (`Resources/lamp-tools.ts`) reads it for its definitions and holds only the `execute` bodies; Lamp's MCP
  endpoint (`Store.mcpTools`, `/mcp` on the gateway) serves it to Claude Code and Codex. A new tool is an
  entry there, an `execute` in the extension, its name in pi's `--tools` list (`Agent.tools`) and Claude Code's
  allowed tools (`Agent.run`), and a `case` in `Store.mcp`. The devices `make_app_for` takes are the table's words:
  `{{PLACES}}` in its description, what each device can run, is filled from the table of devices (`Places.forAgent`)
  as the tools are served (`Store.toolsJSON`), which the endpoint serves and pi's extension reads from `Store.toolsFile`.
  Codex has no file tools of its own, so the endpoint also gives it `read`, `ls`, `find` and `grep`
  (`FileTools`, listed when the URL carries `files=1`): they mirror pi's built-in ones, and each call is
  checked by `Privacy.verdict` like pi's. Don't let a Codex shell command skip approval because it looks
  like a read.
- **Rules in the system prompt** (`Agent.systemPrompt`, `Agent.tryRules`): every tool is available to every
  engine (`look_at_app`, `use_app`, `plan`, `delete_file`, `offer_setup`, `make_app_for`, `remove_app`, `rename_app`, `connectors`, `lampify`, `network_devices`, `device_integration`, `device_permission`, `ask`, `progress`, `write_wish`, `read_skill`, the version tools and the notes tools), so their rules all live in
  `tryRules`. The file tools only Codex is given have theirs in `Agent.codexNote`.
- **What Lamp remembers** (`Memory`): two short sets of notes, about the person (`about-you.md` in the
  support folder) and about each app (`.lamp/notes.md`), each with a one-line summary. They must cost the
  person tokens only when used: the agent is told just the summaries and opens the notes with `read_notes`
  when it judges a request needs them; `save_notes` replaces a set. The summaries go at the end of the
  request, in `Agent.run`, before the engine's `case`, not in the system prompt: Claude Code and Codex keep
  the one a conversation began with when it is resumed, so anything that changes between turns has to ride
  with the request. `Memory.brief` adds them once per conversation and again only when the notes were
  changed by someone else, going by what `.lamp/notes-shown.json` says that engine's conversation last knew;
  most requests carry nothing. A conversation its engine has compacted is told again (pi's and Claude Code's parsers report
  `.compacted`; Codex doesn't say, so its conversations are told again every few requests), and the person can switch it off (`Memory.isOn`, on by default, the checkbox at the top of Settings → Memory): off, there are no notes tools, rule or summaries, and Settings neither reads nor lists the notes. On, Settings lists only the notes that hold something (`MemorySettings.listing`), with one "Nothing yet" row when none do; Add Notes starts a set Lamp hasn't, as a menu, or a button naming the one place left. The switch keeps the key it had as an experiment that was off by default (`experimentMemory`), so whoever chose then keeps their choice and only someone who never chose gets the default.
  What is worth saving is said in `save_notes`'s description: every word there is paid for on every call.
  When to think of saving is said in the rule (`Agent.memoryRules`): at the end of each request, without waiting to be told to remember, and nothing when nothing lasting came up; an instruction for the one request (“don't test it”) is not a preference and isn't noted. No second call to a model decides it.
  A save that changes what the notes say leaves a receipt in the chat (`NoteReceipt`, a `.noted` line, logged in `Store.notes` for every engine): one line that opens to the lines added and removed, and Undo (`Store.undoNote`), which takes that save back out even when the notes have changed since. What was taken back is told to the agent with its next request (`Memory.tookBack`, beside the summaries), so the conversation that learned it doesn't note it again: each engine keeps its own conversation about an app, so each one is told (`Memory.Undone`). Undoing a later save never brings back a line taken back on an earlier receipt. An Undo that leaves notes neither as they were before the save nor as they are now gives them a summary made from their own lines (`NoteReceipt.summary(of:)`): the summary is all the agent is told, so it must be true of what is left.
- **Switching engines** (`CatchUp`): each engine keeps its own conversation for an app, and none can take
  another's, so the one the person switches to would resume its own older conversation, or start a new one, knowing
  nothing of what was said with the other. What it missed goes at the end of the request, in `Store.runAgent`: the
  chat's messages (the person's, the agent's and its questions; never steps, commands or tool output) from the first
  request sent after that engine's conversation last ran up to this turn's own (and through the turn so far for a
  repair Lamp asks for later in it, a build's errors or a crash, which sends no request), the newest kept when there
  are more than fit. When it last ran is read from what each engine already leaves (Claude Code's and Codex's conversation
  file, rewritten as each run starts; pi's session file), so no new record is kept; a conversation that is only now
  beginning, an ended one included (`Store.forgetConversation`), is given the chat from its start.
- **Skills** (`Skills`, `Resources/skills`): guidance only some requests need lives in a skill, not in the system
  prompt, so the prompt keeps what nearly every request uses. A skill is a folder with a `SKILL.md` in the Agent
  Skills format (a one-line `name` and `description` between `---` lines, then the instructions), copied into
  the bundle by build.sh. The prompt lists the skills it offers by name and description (`Skills.index`, offered
  by `Skills.offered` from each kind's `guidance.skills`, the way a rule is given only to the prompts it fits, after
  `Skills.everywhere`, which every prompt offers: how an app is made and on which devices, games, 3D in a page, web
  apps and phones as controllers are the agent's choice on any request, whatever the app is now), or names it in the one short rule that
  stands for it (`Skills.named`, each kind's `guidance.named`: the building blocks' calls, AI in the app, the person's accounts, App Intents, share
  extensions, Finder, scripting, iCloud), which costs the
  prompt a line instead of a rule and a line; and the agent opens one with
  `read_skill`, a tool like any other, so every engine reads skills the same way. Lamp answers from its own bundle,
  so a skill changed in an update reaches a conversation that began before it. Each engine can load skills of its own,
  and Lamp keeps that off where it can (pi's `--no-skills`; Claude Code's `--disable-slash-commands`, without which
  it loads its own skills for coding work; Codex's `skills.bundled.enabled=false` its own. Codex runs outside Lamp's sandbox, and
  it reads the person's own skills in `~/.agents/skills` at every start, which no setting of Codex's turns off): those are for other
  work, and the same file for every engine is one place to keep up to date. When an app's own code
  shows a skill applies (`Skills.applying`: it's new and still to be given its kind, it imports RealityKit, it uses OpenStreetMap data, it has a menu bar icon, a widget or a watch app, it uses the phone's hardware or Health, a TV app has a page for phones, its page runs on the game runtime or draws with three.js or Phaser, it imports SpriteKit, it uses one of those named skills' blocks or frameworks, or has a share extension), Lamp names it at
  the end of the request (`Skills.brief`), sent like `AIStatus.brief` through `RequestNote`: once per
  conversation, again when it changes or the conversation was compacted. What's remembered as told carries each
  skill's revision (`Skills.revision`, a hash of its instructions), so a conversation told of a skill before an
  update changed it is asked to open it again. A new skill is a folder there, its name
  in the `skills` or `named` of each kind whose prompt offers or names it, and, when an app's code can show it applies, a check in `Skills.applying`.
  So guidance that only matters for some apps (a game genre, a device feature, 3D design, phone controllers) goes
  in a skill, the way `phone-pages`, `iphone-hardware` and `apple-watch` did, never into the system prompt:
  every turn of every request reads the prompt, whether its app needs that or not. The prompt keeps at most a
  short rule that names the skill. A skill gives the agent reasons and examples to choose with, never a rule that
  chooses for it: what can't be judgment (what a device can run) is Lamp's to check, in code.
- **Pictures the agent is shown** (`look_at_app`, `use_app`, `make_art`, `assets` with `show`): the conversation is sent whole with
  every request, so its pictures add up until the provider refuses the request (Anthropic takes 30 MB of images
  in one; OpenRouter drops the connection at about 5 MB of body). Every engine is handed a JPEG copy
  (`Previews.forAgent`, under `.lamp/runtime/previews`, through `Store.agentPictures`), never the file itself, and
  as bytes Lamp read (`Store.pictureData`: pi's extension gets them with the answer, never a path to read):
  the screenshots and the art stay as they are for the person and the app. A screenshot's copy keeps its pixels,
  since `use_app`'s points are pixels in the picture at the scale it was taken; art is shrunk to 1280 px. Lamp
  writes the copies unconfined, so their folder and file are checked like `Store.artDestination` checks art. pi's extension (`keepsPicturesFew` in
  `lamp-tools.ts`) then takes the older pictures out of what the model is sent after each turn, with pi's
  context edits (the session file keeps them), and when a request is refused as too big all the same it drops
  every picture and sends once more. Claude Code and Codex compact on their own by tokens, which the small
  copies keep ahead of the byte limit. When a request is still refused (`Agent.isRequestTooLarge`), the turn
  says so in plain words and the conversation ends (`Store.forgetConversation`): the next request starts a
  fresh one rather than failing the same way.
- **Messages sent while the agent works**: they wait in line for the next turn as one group, and the person chooses
  whether it goes now. The group sits close together under one caption at its latest message, with Send Now (Send
  All Now for several) beside it (`ChatLook.QueuedRow`, `QueuedPlace`, in both chats; `Store.canSendNow`), which hands
  every waiting message, in the order they were sent, to the model in the turn that's running, after the tools it
  is running and before its next request (`Store.handOver`). pi's extension asks `/agent/steer` after each of pi's turns and hands such messages to pi's own
  steering (`sendUserMessage` with `deliverAs: "steer"`); Claude Code reads its request on its input
  (`--input-format stream-json`, `Store.steer`), which Lamp writes to while a tool runs and closes once Claude Code
  has answered. Claude Code runs with background commands off (`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS`), as pi has
  none: after answering it waits for one it started (a server) and takes another turn when that ends, so the turn never
  ended; one still there ten seconds after its answer is ended as Stop would end it (`Store.endAfterAnswer`). A message goes into the chat as it's handed over and is a request of the turn (its version,
  `LogLine.midTurn`) once the engine's output shows the model has it (pi's user `message_end`, Claude Code's
  `--replay-user-messages` echo); nothing more is handed over until then, and one the run ends without goes back to
  the front of the line. Send Now isn't offered while the group holds an answer to a card or a request sent again, while a
  wish is being found, or after the agent has asked. Codex is steered by a workaround: `codex exec` reads nothing once
  started, and `codex app-server`, which can steer, can't keep the person's own Codex settings out of Lamp's runs. So
  Lamp interrupts the run and resumes its conversation with the messages (`exec resume`, `Agent.carryOn`, the loop in
  `Store.runAgent`). The interrupt is Codex's own (SIGINT to the `codex` process, as Ctrl-C), which ends the turn,
  records it and exits, never SIGTERM, which loses what wasn't saved; it is sent only between the things Codex does
  (`AgentEvent.acting` from its `item.started`/`item.completed`), never during a command, an edit, a tool call or a
  search, nor while Lamp is answering a call from it (`Turn.answering`: an MCP tool, an approval, which can begin
  before Codex's output says so), and only once its model has been heard from in that run (`turn.started` comes
  before Codex has saved the request). A run that hasn't gone 20 seconds after the interrupt is ended as Stop would
  end it. What the model was thinking or writing at that moment is lost; a message is the turn's once the resumed
  run's model is heard from.
- **What Lamp shows the user** (`TurnProgress.activity`, `ToolCall`): tool names must be recognized in every
  engine's spelling. Claude Code calls MCP tools `mcp__lamp__<name>`; `Engines.plainName` strips that.
  Codex reports them as `mcp_tool_call` items. A turn has one activity (`TurnProgress.activity`, and since when,
  `activitySince`), and every place that shows it draws it with `ChatLook.ActivityText`: a first build's last part, the line
  under a change and the chat beside the app (`SidebarState.workingActivitySince`). How it reads as the wait goes on is `Activity.words`, in one place: while the model thinks, its
  phrases (never a bare "Thinking"; each think opens on one picked by when it began) turn over every 3.5
  seconds and grow more reassuring the longer it goes; a build says "Still building…"
  after 30 seconds and "Taking a little longer…" after 90, and putting a change into the open app "Still updating…"
  and "Taking a little longer…"; anything named ("Working on the interface") stays as it is.
  The agent's progress lines are messages above the activity and are left as they are. A shell command is named in
  the engine's own words, never guessed from its text (`AgentEvent.naming`): Claude Code's description of each Bash
  call (its parser, and its approval hook, which carries the same input; `Agent.claudeNote` asks for plain words),
  and for Codex the heading of the reasoning summary before it (`model_reasoning_summary`). The name is the activity
  while the command runs and the step's row in the chat (`LogLine.said`, `ChatLook.RanCommand`; consecutive commands
  under one name are one row, `ChatItem.items`); a command with no name stays "Did a bit of housekeeping". The name
  is that command's only: Claude Code's and pi's file work after it is a step of its own, and only a Codex heading,
  which says what the work after it is for, names that work too (`Store.stepName`). A step that was tried and didn't
  work says so after its words, "(failed)" (`LogLine.failed`, `LogLine.withOutcome`): each engine reports how a call
  ended by its id (`AgentEvent.ended`: pi's `tool_execution_end`, Claude Code's `tool_result`, Codex's `mcp_tool_call`
  and `file_change`, and its commands' status in `AgentEvent.ran`), and a command's row is the one marked, found by
  that id, which the approval carries (pi's extension sends it, Claude Code's hooks give `tool_use_id`; `LogLine.call`,
  `Store.failedRows`). A
  command a reviewer or classifier stopped is the same row, with "(not run)" beside it only once the row is opened, and
  one allowed on Lamp's card is a row like one that needed no card (`Store.approveCommand`); one the person declines leaves none. pi's bash takes only the
  command, so Lamp's extension replaces it, as pi's extension docs allow, with pi's own bash and a `description`
  (`bashWithDescription` in `lamp-tools.ts`), sent with the approval and read by pi's parser. It's required: left
  optional, some models (Sonnet) never fill it in. pi's edit and write are replaced the same way (`withWords`), with the
  `doing` Lamp's own tools have, so a file change is a step in the agent's words too. While Lamp itself works in a turn (a look's build, putting a change
  into the open app, reopening it) the activity says what Lamp is doing at each stage, so nothing it said earlier
  stays: the whole build that follows a change put into the open app is "Building…" (`Store.awaitLiveBuild`), and a
  look that reopens the app builds it whole without putting the change in first. While a look runs, what the
  engine's output says (its tool call starting, a streamed reply) doesn't change the activity (`Store.noteAgent`):
  every engine reports the call a moment after the look began, and its fixed word would cover each stage after it
  (building, installing, opening, looking at the app, watching it move); when the look ends it's "Thinking". No clock
  is shown beside the activity, in the chat or a first build's chapters: the turn's whole time is its "Worked for…".
- **A failed request is said once**, as the error card a run's failure makes (`Store.runAgent`,
  `Provider.friendlyError`), with the engine's own words in Agent Details. An engine's failure never reaches the chat
  as a message: Claude Code words one as a message from the model, marked with `error`, and its parser drops that line
  because the `result` line says the same; pi's and Codex's parsers have only their failure events to read.
- **Models**: each engine has its own model list and picker (`Builder.engineModel`); never default to Haiku.
  Lamp's providers are Claude Code, ChatGPT Codex, OpenRouter (pi builds through it; its key is the only one
  Lamp keeps, `Provider.keyProviders`) and Native Mac AI (`LocalModels`: Lamp's own model servers, never another
  app's such as Ollama). Don't add another provider without asking: fewer choices in setup was the point.
  Where an app's text AI goes is an `AppAI.TextRoute` (an OpenRouter model, the Claude Code or Codex sign-in,
  or a model on this Mac), listed by `AppAI.textRoutes` for the pickers in
  Settings → Apps (an app's info panel only shows what answers it), and dispatched by kind in `AppAI.dispatch`. The default
  (`AppAI.defaultRoute`) is the local model that builds apps when there is one, else Sonnet through
  OpenRouter with a key, else the builder's own sign-in. Settings → AI Providers lists each provider and
  sign-in with its state, not what it's used for: that's in the menus that choose it. Decisions
  (`AppAI.decisionModels`, `AppAI.decide`) go to Jev
  through OpenRouter, to a Jev-class model on this Mac (`LocalModels.decisionCatalog`, run on the
  bundled llama-server; `decideLocally` does what the model's serving shim does: one forward pass per
  question, probabilities read off the label tokens at the "Answer:" slot), or by text through what answers
  apps (`decideByText`). A decision model is never offered for text or building (`LocalModels.isDecisionModel`).
- **What answers apps, and offering better** (`Sources/Lamp/Capabilities.swift`): `AppAI.resolve(capability,
  for: app, in: .mac | .phoneAway)` is the one answer to "what answers text / decisions / pictures for this
  app, how well (`Resolution.Tier`: none, works, best), and what would make it better (`Upgrade`: a key, a
  download, a sign-in)". Settings → Apps' menus and Not Ready rows, the notes under an app's
  pickers, the sharing review, the keys a phone takes away (`keysForPhone`) and the agent's status line
  all read it; don't work any of that out again elsewhere. A failure for want of setup carries
  `AppAI.Failure.needs`; the gateway passes it to the app (`LampAI.Failure.needsSetup`, and
  `LampAI.isAvailable` asks `/ai/status`) and offers a setup card in the app's chat (`Store.offerSetup`,
  `SetupCard`, once per app and capability; "Not Now" keeps Lamp's own offers away from every app). The
  agent is told what the app has at the end of a request (`AIStatus.brief`, beside `Memory.brief` and sent
  the same way: once per conversation and when it changes) and raises the same card with `offer_setup`.
  Before adding a capability, a way to make one better, or a new offer, read `design/setup-card/README.md`:
  when an offer is worth making, how the card and Settings rows are built, and how to write their copy (for
  someone who has never heard of a key or a model, never naming providers, routes or APIs).
- **An app's own agent loop** (`LampAI.act` in Web/lamp.js, `/ai/act`, `Sources/Lamp/AppAct.swift`): the page
  runs its own tools and keeps the turn; each `/ai/act` request is one step carrying everything so far (the request,
  the tools' argument shapes, every earlier call with its result) and gets back the next calls or the reply, with the
  route's id, which the page sends back so the whole turn stays on one route. The gateway keeps nothing between steps,
  so it holds only what one request can: tool names and shapes (`reply` is Lamp's own), unique call ids, at most
  `AppAct.maxCalls` calls per answer checked against their shapes (a call that doesn't fit is asked for again once,
  then answered as a reply that says it couldn't), and a reply-only step once three are behind it. The turn's writes,
  its deadline and cancel are the page's: it runs reads together and writes one after another, each `check`ed right
  before it runs, stops at the deadline in every layer (the step's request, `send`'s retries) and drops an answer that
  comes after a cancel. Only OpenRouter answers: tools with `require_parameters` and `tool_choice` "auto" ("none" for
  the reply-only step), since the Anthropic models there take nothing stronger, so words without a call are the reply.
  A question back may carry `choices` from `reply` (two to four short plain-text answers, checked by `AppAct.choices`
  and again in lamp.js); words without a call carry none.
  Every other route answers 501 with a sentence saying so; Claude Code and Codex would take a JSON plan through their
  `--json-schema`/`--output-schema` paths, a GGUF model through `response_format`, and mlx_lm.server has neither.
  `LampAI.isAvailable('act')` asks `/ai/act` itself (`probe`), so it's true only when lamp.js has `act`, the app around
  the page lets the route through and the app's route can take it.
- **Hearing for apps** (`LampAI.hear` in Web/lamp.js, `/ai/hear`, `Sources/Lamp/AppHear.swift`): the page's host
  records (`LampVoice`, devices guide) and the page sends a WAV in base64; the gateway checks it is 16 kHz mono 16-bit
  PCM, 0.3 to 15 seconds, with exactly the header the hosts write and nothing more, before anything is paid for, then transcribes it with
  `elevenlabs/scribe-v2` through OpenRouter with `no_verbatim`, the key staying on the Mac and OpenRouter's reported
  `usage.cost` recorded as the app's. No key is a 501 with `needs: text`. lamp.js and the Android host try each way to
  the Mac once, not again after a moment, and each recording carries its id (`op`): the same recording arriving again
  at the same running Lamp within five minutes is transcribed and charged once (an in-memory answer per app). A timeout on the device may still have been paid for. `isAvailable('hear')` asks the
  route itself, as `act`'s does.
- **Using other apps** (`ComputerUse`): two drivers behind one `ComputerUse.Job`. When the ChatGPT app has
  its Computer Use plugin installed, Lamp drives that (`CodexComputerUse`: the `cua_repl` MCP server from
  `~/.codex/plugins/cache/openai-bundled/unified-computer-use/<newest>/.mcp.json`, one `js` tool in which the
  model writes JavaScript against `cua`; the server asks before each step through MCP elicitation, which
  `MCPClient` answers from `Job.decide`: reads go ahead, actions through the person's approval). It isn't a
  documented interface, so when it's missing, off (Settings → Apps), or won't start, CuaDriver's tools are used
  as before. A task goes along the route chosen for the app's text, when one was chosen; with none, along
  `AppAI.computerDefault`, which is not the text default: a Claude Code or Codex sign-in first, then one
  OpenRouter model (`AppAI.computerOpenRouterModel`), each picked by timing the same task, so change them by
  measuring again, not by taste. Through OpenRouter, Lamp runs the tool loop itself. Otherwise the task is one
  turn of a coding agent: pi gets the driver's tools through its
  extension (a tools file and `LAMP_COMPUTER_URL`, which posts each call to `/agent/computer`), Claude Code
  and Codex through `/mcp` with the task's own token (`Store.computerTasks`, never the build tools). The
  driver, approvals, element names and the task's limits (`ComputerUse.stepLimit`, `timeLimit`: every route
  ends there with a plain message, and what it spent is still recorded) live in `ComputerUse.Job` either
  way, so a change to what a task may do is made once.

Before opening a PR that touches any of this, check each engine's `case` in `Agent.run` and its parser,
and say in the PR description which engines you tried.

