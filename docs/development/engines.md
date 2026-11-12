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

- **Tools the agent calls** (`look_at_app`, `use_app`, `plan`, `delete_file`, `make_art`, `assets`, `offer_setup`, `make_app_for`, `remove_app`, `rename_app`, `use_icon_picture`, `connectors`, `lampify`, `shared_copy`, `suggested_changes`, `network_devices`, `device_integration`, `device_permission`, `ask`, `progress`, `write_wish`, `read_skill`, the version tools, the notes tools): their
  names, descriptions and schemas live once, in `Resources/lamp-tools.json`. The first run of a new wish's conversation on pi holds back the
  schemas a new web game on the Mac has no use for, with pi's own `deferred` exposure and `tool_search` behind a short
  rule (`Agent.deferredTools`, `deferredRule`), until `make_app_for` makes anything else. Such a run names no tools,
  since `--tools` is an allowlist that hides deferred tools from `tool_search`: what it starts with is the `defaultTools`
  of Lamp's pi settings (`Agent.deferringTools`, `PiCompaction.setDefaultTools`), and if those can't be read back it
  defers nothing. Every run that resumes a conversation names all its tools and sends every schema: pi 1.0.0 doesn't
  restore what `tool_search` loaded when a process starts with a selection of tools. Claude Code and Codex are served
  the whole list. pi runs a message's calls together unless one is sequential, as `look_at_app` and `use_app` are, so a
  message holding one runs in the order given, unrelated calls included; each one's description says to put it last. pi's extension
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
  engine (`look_at_app`, `use_app`, `plan`, `delete_file`, `offer_setup`, `make_app_for`, `remove_app`, `rename_app`, `use_icon_picture`, `connectors`, `lampify`, `shared_copy`, `network_devices`, `device_integration`, `device_permission`, `ask`, `progress`, `write_wish`, `read_skill`, the version tools and the notes tools), so their rules all live in
  `tryRules`. The file tools only Codex is given have theirs in `Agent.codexNote`.
- **Errors a change brought** (`LogErrors`, `Store.markLog`, `untoldLogErrors`): just before each change goes into an
  app (a live change, a game's page, an install) Lamp notes where the app's log was, and the turn's first mark notes
  every error the log and the launch before it already held. Errors logged after the latest change that were never
  logged before (a number in them aside) go back to the agent once, deduplicated, with the lines before each and capped
  in size, in the note every tool's answer carries beside a held change (`untoldNotes`, in `mcp` and `agentRequest`),
  so pi, Claude Code and Codex hear the same. `progress` first gives a step that just went in a moment to run
  (`letLogSettle`, under a second from when it began). The rule for them is one bullet of `Rules.finish`. The turn's end
  hands the agent what it never heard, and the errors of a window that never drew even when it did, as a fix round
  like a crash's; what's left after that is one plain line in the chat (`errorsLeftLine`). Nothing is read when the
  person keeps the log from the agent (`Privacy.sharesLog`), and this never looks at or tries the app.
- **What Lamp remembers** (`Memory`): two short sets of notes, about the person (`about-you.md` in the
  support folder) and about each app (`.lamp/notes.md`), each with a one-line summary. They must cost the
  person tokens only when used: the agent is told just the summaries and opens the notes with `read_notes`
  when it judges a request needs them; `save_notes` replaces a set. The summaries go at the end of the
  request, in `Agent.run`, before the engine's `case`, not in the system prompt: Claude Code and Codex keep
  the one a conversation began with when it is resumed, so anything that changes between turns has to ride
  with the request. `Memory.brief` adds them once per conversation and again only when the notes were
  changed by someone else, going by what `.lamp/notes-shown.json` says that engine's conversation last knew;
  most requests carry nothing. A conversation its engine has compacted is told again (pi's and Claude Code's parsers report
  `.compacted`; Codex doesn't say, so Lamp sees it in Codex's file after the run, and its conversations are told again every few requests besides), and the person can switch it off (`Memory.isOn`, on by default, the checkbox at the top of Settings → Memory): off, there are no notes tools, rule or summaries, and Settings neither reads nor lists the notes. On, Settings lists only the notes that hold something (`MemorySettings.listing`), with one "Nothing yet" row when none do; Add Notes starts a set Lamp hasn't, as a menu, or a button naming the one place left. The switch keeps the key it had as an experiment that was off by default (`experimentMemory`), so whoever chose then keeps their choice and only someone who never chose gets the default.
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
  beginning, an ended one included (`Store.forgetConversation`, `Conversation.setAside`), is given the chat from its start.
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
  A skill can also be made of sections of others (`sections` in its frontmatter, put in where its body says
  `{{sections}}`, `Skills.assembled`), so each section keeps one place: the narrow game skills a web game at home on the
  Mac uses (`game-feel`, `game-3d`, `game-physics`, `game-levels`, `game-art`, `game-live`, and `game-playtest`, opened only when the person asks to play or check it) are views of the `game`,
  `game-ui`, `2d-game` and `3d-game` skills that games elsewhere read whole. Such a game names the ones it needs with
  `make_app_for`'s `needs`, which every engine has from `lamp-tools.json`, and gets them with the guide; its code only
  hints at `game-3d`, `game-physics` and `2d-game` later, never by Lamp's runtime or the Phaser every one draws with.
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
  the screenshots and the art stay as they are for the person and the app. The copies are JPEG at 0.6
  (`Previews.agentQuality`). A screenshot's copy keeps its pixels, since `use_app`'s points are pixels in the picture
  at the scale it was taken, so a Mac window is taken at no more than 1024 px on its long side (`LampRuntime.scale(of:)` in
  LampSupport.swift), which still reads its words; art is shrunk to 1024 px. Lamp
  writes the copies unconfined, so their folder and file are checked like `Store.artDestination` checks art. Only the
  newest few pictures stay in what each engine sends: pi's extension (`keepsPicturesFew` in
  `lamp-tools.ts`) takes the older ones out, with pi's
  context edits (the session file keeps them), and when a request is refused as too big all the same it drops
  every picture and sends once more. Claude Code and Codex can't drop a picture, so Lamp does it in their own files
  before resuming them (`Conversation.keepPicturesFew`): once a conversation holds more than 12, all but the newest 6
  become a line saying a picture was taken out, in the engine's own spelling, the rest of the file left as it was.
  pi's extension goes by the same numbers (and a byte budget besides). In a batch, not each turn, for every engine,
  since each change to a conversation's beginning costs its cached copy at the provider.
- **How big a conversation grows** (`Conversation`): every engine sends its whole conversation with each request, so a
  wish worked on for days grows past what one request can carry (about 32 MB at Anthropic) long before a model with a
  million tokens fills its window and compacts. So every engine compacts at `Conversation.compactAt` (200k tokens):
  Claude Code by `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (it compacts a little under the window it's given), Codex by
  `model_auto_compact_token_limit`, and pi by a reserve for each model in `settings.json` in Lamp's pi folder
  (`PiCompaction`, from pi's `get_available_models`, asked again before a run only when pi or the files saying
  which models it has changed): pi compacts on its own at the
  window less `compaction.reserveTokens`. Never `ctx.compact` from Lamp's extension: pi's manual compaction aborts the
  running turn and doesn't carry on, while its automatic one runs between a turn's requests and the turn goes on. A
  model pi doesn't list keeps pi's own reserve. The reserve also raises the longest summary pi 1.0.0 may ask for, up
  to the model's own output limit. Claude Code's `compact_boundary` and pi's `compaction_end` are `.compacted`, and
  Codex's is found in its file after the run; nothing of it shows in the chat, and the notes are told again. A pi
  compaction that fails leaves the turn going, and pi tries again before the next request. Each run's size
  before and after (the context its last request took, the pictures still sent and their bytes, the file, how often it
  compacted) is a line in `conversations.log` in Lamp's logs folder (`Conversation.note`), as are pi's compactions
  starting, ending and failing, with how long they took. Lamp Dev takes
  `LAMP_COMPACT_TOKENS` from its own environment to try a compaction quickly (Claude Code takes no window under 100k;
  `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` lowers it further). When a request fails all the same in a way a smaller
  conversation would get past (`Conversation.isTooBigToSend`: refused for its size, the prompt too long, or the
  connection cut or the provider failing while a large conversation went out), Lamp sets that engine's conversation
  aside (`Conversation.setAside`: its id moves to `.lamp/set-aside`, the conversation stays where the engine keeps it,
  nothing is deleted), says so in the chat ("Started a fresh conversation for <wish>: the last one had grown too large
  to send") and sends the request once more in a fresh one, told the wish's APP.md (`Conversation.freshNote`) and the
  chat so far (`CatchUp`). If that fails too, the turn says so in plain words. Start Over sets every
  engine's conversation aside the same way ("Start Over" in the desk guide).
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
  A plain typed message stays in this line as ever, and a helper answers it at once, for every engine (`SideAnswer`, in
  one place with one launch and one reader per engine). There's no setting for it. Each run starts with no tools, in a
  private folder under a sandbox of its own (`Sandbox.sideProfile`) that can write only that folder, with an environment
  that's a short list and none of Lamp's routes or tokens, and 30 seconds in all; with no profile on disk it doesn't run,
  and whatever goes wrong leaves an ordinary queued message. Nothing goes into the engine's own history. How each does it:
  - **pi** forks a copy of the session (`--fork`), read as `AppFile` reads the app's files and refused when it's a link or
    has a second name, since the builder writes that folder. It has `--no-tools`, no extension, its own key ticket, a home
    folder and a settings folder of its own (`SideAnswer.piConfig`: Lamp's settings and the one provider's entry; pi locks
    what it reads by making a folder beside it, which the sandbox refuses in Lamp's). pi answers beside a call still running.
  - **Claude Code** forks by the transcript's whole path, which lets it run outside the app's folder (`--resume <path>
    --fork-session --no-session-persistence --tools ""`, with the isolating flags the builder has). Its `system/init` line
    must list no tools and no MCP servers before anything it says counts; a tool it asks for is a tool tried even before
    that line. It reads its sign-in from the Keychain, and answers on releases in `SideAnswer.testedClaude`. The same
    run answers for a suggested change's summary (`SuggestionSummaries`) started afresh instead of forked
    (`claudeFreshArguments`: no `--resume` or `--fork-session`, its whole system prompt by `--system-prompt`, no
    `--json-schema`, which Claude Code answers through a tool, and no conversation opened to its sandbox). One whole run of
    that launch is recorded in `Tests/Regression/Fixtures/claude-fresh-summary-run.jsonl`; `ClaudeSummaryRunTests` reads it
    and records another when `LAMP_RECORD_CLAUDE` names where to put it.
  - **Codex**'s fork can't be used: it inherits its parent's tools, and no flag removes them. So it's a fresh ephemeral call
    over the chat Lamp holds (`SideAnswer.chat`), in `testedCodexModel`. **This route is a workaround**: Codex has no way to
    start with no tools, so the list is emptied with feature switches, two settings nothing documents, and an edited copy of
    the model's own catalog entry (`codexArguments`, `codexCatalog`). It only runs on a version in `testedCodex`, exactly. To
    add a version, point that launch at a local stand-in for the provider and read the request it sends: `tools` empty
    and no `additional_tools` item in `input`; then run it for real, told to use its tools, and see no tool item. Codex can
    write only `installation_id`, and reads only that and `auth.json`, from its folder.

  Every engine's version is asked before each run, except pi's, which is inside Lamp. It's skipped for a model on this Mac,
  and for answers to cards, files, what was pointed at, requests sent again, a turn that has asked, paused or waits on an
  approval, and a second message while one is being answered. Five starts per builder's turn at most, however they end,
  and nothing is retried. An answer that fails rests that engine for two minutes. A tool that ran, which no launch allows,
  stops that version for good on this Mac and cancels every run of the engine still going, beside a turn or for a summary
  (`SideAnswer.stopAll`); none of their answers is shown (`SideAnswer.mayShow`), and a summary already back is checked
  again before it's kept. The answer is one whole
  message with no tool attempted, even a refused one, since a tool can act and then fail; Codex's is its last message. Sent
  again in the same words, a request keeps its answer and receipt (`SideAnswer.kept`). The answer goes up only if its message
  still waits beside the turn it was made for, stays with it (`QueuedMessage.side`, then `LogLine.sideReply`, never a line
  of the turn's, so `CatchUp`, folds and versions don't see it), and the message reaches the agent as ever with what was said,
  so it can't go ahead of its message. For Claude Code and Codex that's a labeled receipt (`SideAnswer.receipt`) in the
  request or Send Now's handover. For pi it's one record per handover (`SideAnswer.record`: the words when they go with it,
  each answer with the message it was to, Lamp's note, and the receipt as its stored text), which Lamp's extension shows the
  model as the person's words, then the answer as the model's own reply, then Lamp's note saying a helper wrote it, that it
  grants nothing, and to correct it if wrong (`answersAsItsOwn` in `lamp-tools.ts`, a `context` hook; pi's own record
  keeps it as Lamp's custom message). Send Now steers it as one custom message, so nothing reaches the model between its
  parts; a turn's own request carries it as `before_agent_start`'s message, again on a run that starts the conversation
  afresh (`SideAnswer.ownReply(_:given:afresh:)`). `sideAnswerOwnReply` set to false puts pi back on the receipt. The
  helper promises only what the agent can do itself, changing the app and what's in its folder; anything outside the
  folder it says will be asked about, never that it'll be done (`SideAnswer.prompt`). When its answer is all the message
  asks for (a question fully answered, or a reminder to keep going with the work under way) it ends with
  `SideAnswer.finishedTag`; anything else, a malformed tag, or an answer saved before the tag existed means the agent is
  needed (`SideAnswer.finished`). A line of nothing but such questions starts no turn: `startQueued` puts them in the chat
  with their answers (`Store.postFinished`: the chat is written to disk before the line is cleared, and one that can't be written keeps
  the line; a restore after a quit knows what's already posted by the message's saved id, never its words, so it posts
  nothing twice and the same question asked again still goes in), and the next request carries each with its answer as past context (`CatchUp`), until that engine has run. A
  line with anything else in it, a turn under way, Send Now and Reload are as ever. Every receipt and record also says
  that if nothing is left to do, the agent says nothing more. A queue holding an answer outlives a quit (`Store.keptAcrossRelaunch`) and then waits for the person, unless it's
  paused for Reload, whose Reload carries it on (`Store.heldAfterQuit`); a helper at work when Lamp quits isn't started again. A handover whose messages have all been answered tells the agent not to acknowledge them again
  (`Agent.midTurnNote(for:)`), so the person hears back once.
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
  optional, some models (Sonnet) never fill it in. A call without it all the same isn't refused, which would cost a
  request to the model: `prepareArguments` gives it empty words, and the step is "Running a command". pi's edit and write are replaced the same way (`withWords`), with the
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
  Settings → Apps, and dispatched by kind in `AppAI.dispatch`. The default
  (`AppAI.defaultRoute`) is the local model that builds apps when there is one, else Sonnet through
  OpenRouter with a key, else the builder's own sign-in. Settings → AI Providers lists each provider and
  sign-in with its state, not what it's used for: that's in the menus that choose it. Decisions
  (`AppAI.decisionModels`, `AppAI.decide`) go to Jev
  through OpenRouter, to a Jev-class model on this Mac (`LocalModels.decisionCatalog`, run on the
  llama-server (fetched when first needed, `LlamaInstall`); `decideLocally` does what the model's serving shim does: one forward pass per
  question, probabilities read off the label tokens at the "Answer:" slot), or by text through what answers
  apps (`decideByText`, told and read by `cli/app-ai.mjs`). A decision model is never offered for text or building (`LocalModels.isDecisionModel`).
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
  route's id, which the page sends back so the whole turn stays on one route. Nothing is kept between steps, so a step
  holds only what one request can: tool names and shapes (`reply` is Lamp's own), unique call ids, at most eight calls
  per answer checked against their shapes (a call that doesn't fit is asked for again once, then answered as a reply
  that says it couldn't), and a reply-only step once three are behind it. The turn's writes, its deadline and cancel are
  the page's: it runs reads together and writes one after another, each `check`ed right before it runs, stops at the
  deadline in every layer (the step's request, `send`'s retries) and drops an answer that comes after a cancel.
  What the model is told and how its answer is read and checked is in one place, `cli/app-ai.mjs`, which Lamp's app
  has do it through `LampCLI` (`actStep`, `actAsk`, `actRead`) and lamp's own answers use directly (`cli/ai.mjs`);
  `AppAct` keeps only the route, its time and asking it. Every text route answers: OpenRouter with tools,
  `require_parameters` and `tool_choice` "auto" ("none" for the reply-only step), so words without a call are the
  reply; Claude Code and Codex with one sealed run per step held to the step's JSON shape (`--json-schema`,
  `--output-schema`); a GGUF model through `response_format`; an MLX model with its server's tool calling where it has
  a parser for the model, else asked for the shape in words. A question back may carry `choices` from `reply` (two to
  four short plain-text answers, checked in app-ai.mjs and again in lamp.js); words without a call carry none.
  `LampAI.isAvailable('act')` asks `/ai/act` itself (`probe`), so it's true only when lamp.js has `act`, the app around
  the page lets the route through and the app's route can take it.
- **Claude Code and Codex answering apps** (`AppAI.viaEngine`): run by lamp's command line (`engineAnswer` in
  cli/calls.mjs, `complete` in cli/ai.mjs, which `lamp dev` and `lamp ai` use too), with the copy and its settings
  Lamp chose (`EngineInstall.path(for:)`, `EngineInstall.environment(for:)`). Every run is sealed: Claude Code
  `--restricted` with no tools at all, Codex read-only with its shell, pictures, web, apps and sub-agents off and no
  approvals. Pictures go with the request, in Claude Code's stream-json input and as Codex's `-i` attachments, never
  through a tool that reads files. The engine is never run with `BUN_BE_BUN`, which the runtime around lamp sets and
  would make Claude Code, itself built on Bun, act as Bun.
- **OpenRouter answering apps** (`AppAI.viaOpenRouter`, `AppAct.openRouterStep`): sent by lamp's command line
  (`openRouterText`, `openRouterChat`, cli/openrouter.mjs) with the person's key from Lamp's Keychain on the call's
  input, kept nowhere there; a provider's content-filter cut-off is asked again twice within the request's time, and
  each attempt's cost comes back to be recorded. `lamp dev` and `lamp ai` send the same way with `OPENROUTER_API_KEY`.
  Pictures made through OpenRouter and decisions through its decision model are still sent by Lamp's app.
- **Shared pages' AI** (`SharedPagesAI`, `Store.sharedPageAI`): a page shared on lamp.dev, played in a browser on the
  Mac, asks one port of the computer's own (`NEARBY` in lamp.js). Which pages are let in is lamp's command line's
  (cli/local-ai.mjs, also `lamp ai`); Lamp keeps its `sharedPages` call running and is asked only for the person's yes
  (a dialog) and the AI's answer, given as an app's request is with no app behind it (`appRequest(for: nil)`: Lamp's
  default choices, no cost recorded, no setup card). Not `/ai/computer`, nor anything of the agent's.
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


## The person's own agent through MCP (trial)

Besides the three engines Lamp runs, the person's own coding agent (Claude Code, Codex) can start Lamp as a local MCP
server and work on an app in a folder of its own (`OutsideServer`, `OutsideWork`). It isn't an engine:
Lamp starts no process for it and sees none of its commands, so its shell is under its own approvals, not
`/agent/approve`. What Lamp does for it (building, opening, putting a change in) keeps Lamp's own checks.

- **Setting it up.** The person asks their own agent to, in the Claude desktop app's Code tab or the ChatGPT desktop
  app's Codex, and the agent does it: `lamp-mcp --help` prints the steps for both clients with its own path
  (`setupSteps` in `Sources/LampMCP/main.swift`, the one place they're written), and `lamp-mcp --check` lists the tools.
  Each desktop app reads the same settings as its command line (`~/.claude.json`, `~/.codex/config.toml`), so the
  steps are one edit of that file, with the command line's own command after it. Nothing in Lamp's own screens offers
  this. The steps say what each desktop app's agent runs into: Claude Code's sandbox refuses a shell write to its
  settings and Auto mode refuses the edit outright, so the agent edits with its file tool after the person switches
  the session to Manual; a sandboxed shell may not start Lamp for `--check`; and the tools only appear in a session or
  chat started after the change.
- **Reaching Lamp.** The agent's client runs `lamp-mcp` from Lamp's Helpers over stdio. The helper carries each JSON-RPC line to this Lamp's socket and back; Lamp answers `initialize`, `tools/list` and
  every call. The socket is in a 0700 folder of the Lamp's own named by its bundle id (`OutsideKit`, which `Edition.name`
  reads), and each connection's peer must be the person's user. The first line each way is a handshake with
  `OutsideKit.protocolVersion`. Lamp not running is started from the helper's own bundle; a call under way when Lamp
  ends is answered `interrupted`.
- **Taking a folder on.** `open_project` asks the importer what the folder is (`RepoImport.layout`, the same answer
  `RepoImport.open` reads it by): an app in Lamp's format, a site (`StaticSite`, run as a web app), or what's missing
  for either, which is answered `not_importable` with those words. A packed shared file alone, a kind that doesn't open
  on the Mac, and a wish of more than one app are answered `not_importable` too. Adapting a folder Lamp can't read is not
  done here. What it can read goes through the same import review as any app that comes to Lamp (`Store.importApp`
  with an `OutsideImport`): the fixed checks, the AI's check when AI is set up, and the person's Build & Open, always as
  a new app and with no chat opened beside it. The review reads a copy of the very package open_project captured and
  checked (`OutsideImport.snapshot`), not the folder read again, so what's approved is what's built first; an edit made
  while the review was up is pending for the next apply. The call waits for that answer. A review that ended is never
  opened again for the same call (its Try Again does nothing once the agent was told), and a folder taken on is applied,
  never imported again, so a retried open_project makes no second app. Later applies are the agent's own work, as a chat's turns are, and aren't reviewed again.
- **An app with no icon.** Its icon is designed right after the review, before the first build, as a new app's is
  while its first request builds: designed after it, the icon is a change the open app can't take, and the next
  change of any kind would reopen the app.
- **Converting in place, or in a copy.** By default the folder is converted where it is: that's what the person's
  source control is for. A Lamp app needs nothing; a plain site gets Lamp's manifest for a site beside its page
  (`.lamp-wish/lamp-app.json` and `APP.md`, the very ones the review read), which makes it a laid-out site
  (`StaticSite`). The conversion is worked out before the review, which says what Build & Open will change in the
  folder (`Conversion.reviewLine`: the manifest added, or a copy made); it's written once, after Build & Open, never
  over a file that's there, and the answer names what was added. A copy is made only when the conversion would be disruptive (`OutsideWork.Conversion.disruptive`, the one
  place that decides): it would replace or remove meaningful existing files, substantially reorganize the project,
  replace its build or dependency setup, drop targets or features, break its own way of working, or overwrite
  uncommitted work. Adding a manifest or a few support files and small, reviewable edits stay in place. The copy is the
  whole folder, its git with it, beside the folder given (`<name>-lamp`), which may itself be a worktree checkout: a
  worktree's `.git` file is left out of the copy, which would otherwise claim the same checkout, and the answer says so; the answer gives its absolute path, why it was
  made, that the original is unchanged, and the steps the agent passes on to the person (`OutsideWork.switchSteps`: Claude Code's and
  ChatGPT's desktop apps first, which are the main clients, then one line for the command line's `--add-dir`), and later calls on the original are answered from the copy (`Adopted.copiedFrom`).
- **The folder and the workspace.** The folder stays the source and its git is the person's: Lamp writes in it only the
  conversion above.
  What builds and runs is the project in Lamp's apps folder the review made, so LiveReload's live copy, libraries and
  runtime folder stay where they always are. Each apply captures
  the folder as the import reads one (`RepoImport.open`), checks the bytes copied against the folder before and after,
  writes into the workspace only what differs (`OutsideWork.sync`: the code, its files, and its metadata by the
  import's own writers, `syncMetadata`: capabilities, description, credits and their licenses, the icon, put in only when the folder's
  own metadata changed since the last apply, `Adopted.metadata`, so Lamp's own work on its copy's icon isn't written
  over, and the app reopened, at every apply), then builds and installs as a look does, holding
  the project as Lamp's own work does (`Store.begin`). That hold is a `Turn` with no request and no agent, and what
  became of the change is read from its `outcomes`, as a look reads it; pulling the apply and its checks out of
  `Turn` into something of their own is still to do. Folders are known by real path, device and inode
  (`Outside/adopted.json`); a folder put in another's place is refused until `open_project` takes it on.
- **The mapping.** The folder's paths and the workspace's differ wherever the import moves files (a site's page goes
  into Web/, a laid-out site's `.lamp-wish/` to the top). `OutsideWork.Mapping`, made from the package and its layout
  once per capture, is the one way between them: each file the install puts in the app by its workspace path, with the
  package's copy and the folder's path it came from (none for a file the import writes itself, such as a plain site's
  APP.md). The capture's checks, the sync, the metadata digest (every file of the folder the mapping doesn't put in the
  app) and the paths answered to the agent all go through it. Its record is kept per folder (`Adopted.files`), so a file
  taken out of the folder is taken out of the workspace where the import put it, and Lamp's own files there stay.
- **Pictures.** What apply_change and look_at_app show is the app's window once it has drawn: a window just opened is
  pictured before its page paints, one even color (`GameKit.isBlank`), so it's pictured again for up to 15 seconds,
  and one still blank is said rather than sent (`outsidePictures`).
- **One at a time.** Every call on a folder waits for the one before it, whatever connection sent it
  (`outsideSerially`). An apply answers stale when the folder changed while it built. `operation_id` replays an apply
  that ran, for as long as Lamp runs; after Lamp starts again an apply waits for a `look_at_app` first.
  Files an apply wrote into the workspace are marked owed on disk until the change goes in (`Adopted.owed`), so the
  next apply puts them in, never answering unchanged, even after a cancel or Lamp starting again.
- **What the agent is told.** The server's `instructions` say how to work with Lamp; `open_project` adds, for the app's
  kind, the skills index Lamp's own engines get (`Skills.index`), less the skills about a Lamp tool it doesn't have
  (`OutsideWork.offeredOutside`: their description names `make_app_for`, `make_art`, `lampify` and the like), the skills whose rules every change keeps
  (`Skills.named`) and those the code already uses (`Skills.applying`). `read_skill` is the one from `lamp-tools.json`,
  answered by `Skills.read`. Library choices stay in the skills; nothing here names one. The agent's own instruction
  files in the folder are never written. Lamp's import review calls such a folder's description its own, not a sender's
  (`ImportReviewCard.ownFolder`). The agent uses the open app with `use_app` (`OutsideWork.useApp`), only when the
  person asks it to try the app: the actions and what the app does with them are Lamp's own engines' (`Store.useNow`,
  in plain sight under the person's Stop), held as an apply holds the app, with words of its own for what's about
  Lamp's chat. Once the person takes the app back, use_app is off for the folder until the agent's next apply (Lamp sees
  none of their messages), and an app that presses on the person's devices (`DevicePermissions.useNeedsDevice`) is
  used only on a device named in `device` that the person allowed Always on Lamp's card ("Allow once" lasts until
  their next chat message, which an outside agent's work isn't part of). `close_app` quits the app as Lamp's Stop does. `share_link` shares any of Lamp's apps by its folder (a desk app's
  own, not only one taken on) as the Share Link card does without its window: `WishLinkCards.prepare` fills the card
  as opening it does, what the call gives goes in place of the card's own, and `share` sends it; `preview` answers
  what it would send.
  A refusal for a folder Lamp doesn't have carries `taken_on: false`. An apply refused because Lamp started again carries `restarted` in its facts, so a client can look and
  apply again.
- **Sharing.** Both tools share only a known snapshot: the folder must read as it did at the last apply that went
  in, which wrote the workspace from that reading, and nothing written since may be owed (an apply that didn't build
  or was cancelled leaves files in the workspace the folder may no longer hold), or they refuse and ask for an apply. `export_app` makes the shared file as
  Share… does (`Sharing.askToShare`, then `Store.sharedFile`, with every check of `Sharing.export`) and answers its
  path in Lamp's own folder. `publish_link` opens the Share Link card (`WishLinkCards`) for the person and waits on it,
  holding the app so nothing is applied meanwhile. The card makes the link before the app's file goes up, so a failure
  after that is answered as a link that exists without this release, never as success or as nothing shared. The link's
  secret stays where Lamp keeps every link's, and changing or taking a link down stays on the card.
