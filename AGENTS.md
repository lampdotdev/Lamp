# Working on Lamp

Lamp is a Mac app that builds other Mac apps with an LLM agent. Read `README.md` for what it is and
`RELEASING.md` for how it ships. This file is for whoever (or whatever) edits the code.

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

- **Tools the agent calls** (`look_at_app`, `use_app`, `plan`, `delete_file`, `offer_setup`, `make_app_for`, `connectors`, `ask`, `progress`, `write_wish`, `read_skill`, the version tools, the notes tools): their
  names, descriptions and schemas live once, in `Resources/lamp-tools.json`. pi's extension
  (`Resources/lamp-tools.ts`) reads it for its definitions and holds only the `execute` bodies; Lamp's MCP
  endpoint (`Store.mcpTools`, `/mcp` on the gateway) serves it to Claude Code and Codex. A new tool is an
  entry there, an `execute` in the extension, its name in pi's `--tools` list (`Agent.tools`) and Claude Code's
  allowed tools (`Agent.run`), and a `case` in `Store.mcp`.
  Codex has no file tools of its own, so the endpoint also gives it `read`, `ls`, `find` and `grep`
  (`FileTools`, listed when the URL carries `files=1`): they mirror pi's built-in ones, and each call is
  checked by `Privacy.verdict` like pi's. Don't let a Codex shell command skip approval because it looks
  like a read.
- **Rules in the system prompt** (`Agent.systemPrompt`, `Agent.tryRules`): every tool is available to every
  engine (`look_at_app`, `use_app`, `plan`, `delete_file`, `offer_setup`, `make_app_for`, `connectors`, `ask`, `progress`, `write_wish`, `read_skill`, the version tools and the notes tools), so their rules all live in
  `tryRules`. The file tools only Codex is given have theirs in `Agent.codexNote`.
- **How the agent talks** (`Talk`, `TalkCards.swift`): in short sentences and in cards, not paragraphs, so building
  feels like a short wizard. A vague wish gets a good first attempt built from sensible guesses, not questions: the
  agent asks first only when one answer would make a different app (whether it's useful, what it needs to reach,
  what it costs, whether it acts outside the app), then one question, its lowest-impact answer first and the one
  taken when it's left to Lamp; an answer never grants access or approves an outside action (`Agent.Rules.ask`). Each piece of a card has a word limit (`Talk.Words`, the same numbers as the
  tools' descriptions), and a call over it is turned away for the agent to say shorter, whichever engine it is. Its
  pieces are tools: `ask` puts questions in the chat as a card answered by clicking, laid out as the agent
  chooses (`Talk.Layout`: one at a time, or all on one card; always in the chat, never a page of their own). What a
  request came to is the agent's last message, in a sentence or two (`Agent.Rules.finish`), under the line that says
  the app is ready or updated; a card for it said no more than that message did and hid what it said beyond it.
  While longer work goes on, the agent says how it's going with `progress`: a line of 12 words at most, shown at once
  in both chats as a message like any other, which stays one when the turn ends. A turn's steps belong to its one
  live line (`ChatLook.ActivityLine`, `ChatItem.live`, the sidebar's `SidebarState.workingSteps`), which says what
  it's doing now and changes in place. While the turn goes on the line is open, at the bottom under the steps done
  so far, oldest first, so what's done reads in order and what's going on now is always last (a command by the name
  the agent gave it, any other tool call in the words the line said while it ran, `LogLine.visible`, never its
  files); the step still going is the line itself and joins the list when the agent moves on (`ChatItem.live`), and a
  click folds the list; when the turn ends the line and its
  steps give way to "Worked for…" (`ChatItem.items`), folded, under the turn's last message, which opens to the same
  steps. Whatever the agent writes as messages on the way is
  treated the same, each shown as it's said and kept as it was (`LogLine.visible`), since models write such updates
  whether or not they're asked to use the tool: what the person has read never turns into a gray line among the
  steps or goes away. (A Lamp from before this folded them; `ChatLook.ProgressLine` and the status line marked with
  `ChatLook.progressSymbol` are still drawn for a sidebar talking to one.) A change to much of what an app already shows is built in passes
  (`lookRules`: the layout with placeholders, then the parts working, then the detail), each begun with a
  `progress` line and ended with `look_at_app`, which puts it into the open app, so the person watches the app
  take shape rather than waiting for the end; what's read only at launch is made right in the first pass, so later
  ones go in without reopening the app. A new app is built in passes too, the window's layout first. A new Mac app's
  scaffold ("Lamp is making this app.") is built and opened as its first turn starts, with the chat beside it
  (`Store.showEarly`, `Store.present`), so the person watches every pass go in; an iPhone app's simulator comes
  forward at the agent's first look. When no chat comes back beside the app after a pass reopens it (the reopen
  failed, it crashed, or the pass made it an app with no window), the chat goes back to Lamp's window
  (`MagicPanel.keepChatInSight`). The early build is settled before the turn lets go of the app, however it ends.
  Result cards saved by an earlier Lamp still read and aren't shown (`LogLine.visible`). A new app's build card folds
  to its first line (its name, Ready) once the turn is over, with no picture of the app. What each piece
  is for is in its tool's description; `Agent.talkRules` says only that a piece comes before prose. Neither
  tool waits for the person: it returns at once, the agent ends its reply, and a click is sent as the
  person's next message (`Store.answer`), so a click and a typed answer reach every engine the same way and
  the message box always answers a card (`Talk.open`). A click's message carries each question with its
  answer (`Talk.message`), for an engine that reads the conversation again later; the chat doesn't show it,
  since the card does (`LogLine.fromCard`, `Talk.shows`). An
  answer that has to wait in line, clicked or typed, folds its card at once and opens it again if it's taken
  back (`Talk.unqueue`). A clicked one waits as its folded card alone, taken back from there (`AskWaiting`), not as a
  waiting message too: that would show until it's sent and then go. Waiting for setup, it keeps its card across a relaunch (`QueuedMessage.saved`).
  `Talk.Ask` also reads the shape cards were first saved in (options as plain words, `chosen`, `dismissed`):
  a chat line that can't be read is skipped and the rest opens (`LogLine.readChat`), with the file as it was kept beside it as `chat.json.unreadable`, but that line is gone from the chat. While a card waits for its answer nothing above it changes height and the chat
  doesn't follow what's added below: a new app's card goes to its short form as the questions arrive, a
  second `ask` before the answer is turned away, and a one-at-a-time card is laid out for all its questions
  at once (`AskSteps`), so nothing moves under the pointer. Its answers are small tiles, a symbol and a line each, as the
  chips of a card with every question on it are: one under another below a card width that takes in the wand's
  panel at any size it opens at, in one row only on a wider card where each fits on a line (`TileRows`, and
  `ChipRow` the same way). A question left to Lamp is "Decide for me" (`TalkCard.youDecide`). Asking ends the turn: nothing is built or saved
  until the answer, and an agent that goes on to another step after `ask` is ended by Lamp, the way a
  runaway one is (`Store.endOnQuestions`), whichever engine it is. Once the card is answered the chat
  follows its end again (`ChatFollow.followThroughSettling`). Only the card that waits is drawn as a card: answered, it folds to a line with what was chosen, and a notes receipt is a line too, so one thing in the chat asks for attention at a time. A new piece is a tool there, its view, and a line in `talkRules`. The agent still
  doesn't ask about layout, colours or names (`Agent.Rules.ask`).
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
- **Skills** (`Skills`, `Resources/skills`): guidance only some requests need lives in a skill, not in the system
  prompt, so the prompt keeps what nearly every request uses. A skill is a folder with a `SKILL.md` in the Agent
  Skills format (a one-line `name` and `description` between `---` lines, then the instructions), copied into
  the bundle by build.sh. The prompt lists the skills it offers by name and description (`Skills.index`, offered
  by `Skills.offered` the way a rule is given only to the prompts it fits), and the agent opens one with
  `read_skill`, a tool like any other, so every engine reads skills the same way. Lamp answers from its own bundle,
  so a skill changed in an update reaches a conversation that began before it. Each engine can load skills of its own,
  and Lamp keeps that off where it can (pi's `--no-skills`; Claude Code's `--disable-slash-commands`, without which
  it loads its own skills for coding work; Codex's sandbox keeps the person's out of reach, and `skills.bundled.enabled=false` its own, which it would otherwise
  try to copy into its folder's `skills/.system` at every start, where the sandbox keeps it from writing): those are for other
  work, and the same file for every engine is one place to keep up to date. When an app's own code
  shows a skill applies (`Skills.applying`: it imports RealityKit, it uses OpenStreetMap data, it has a Chrome sidebar page), Lamp names it at
  the end of the request (`Skills.brief`), sent like `AIStatus.brief` through `RequestNote`: once per
  conversation, again when it changes or the conversation was compacted. What's remembered as told carries each
  skill's revision (`Skills.revision`, a hash of its instructions), so a conversation told of a skill before an
  update changed it is asked to open it again. A new skill is a folder there, its name
  in `Skills.offered`, and, when an app's code can show it applies, a check in `Skills.applying`.
- **Approvals and privacy**: shell commands go through `/agent/approve` for every engine (pi's extension,
  Claude Code's hooks, Codex's hooks); file access outside the app's folder is checked the same way.
  Under "Only when risky", Claude Code's own classifier (auto mode, `classifyAllShell`) decides its shell commands:
  Lamp's hook only hands each one back confined, with no decision (`format=claude-confine`), what the classifier asks
  about comes to Lamp's card through `PermissionRequest` with no check or rating of Lamp's, and a command that ran is
  said in the chat from `PostToolUse` and `PostToolUseFailure` (`format=claude-ran`). What the classifier refuses stays
  refused (the agent is told why, and the chat says "Not run:", `PermissionDenied`, `format=claude-refused`). pi and Codex keep
  Lamp's own check (`CommandRisk`).
  Claude Code's and pi's approved commands come back confined (`Sandbox`: `sandbox-exec` with a profile
  that opens the app's folder, the system, developer tools, caches, temp folders and the network, and
  closes the rest of the home folder and both Lamps' folders), so nothing reads a command's text to see
  where it looks. Codex's hook can't change a command and a sandbox can't be nested, so Codex itself runs
  inside the profile (`Sandbox.wrapEngine`, with the copy in use and its folder opened and Codex's own sandbox off) and its
  commands with it. SwiftPM's own sandbox can't start inside Lamp's, so a `swift` shim first on the path
  (`Sandbox.bin`) gives `swift build`/`test`/`run`/`package` `--disable-sandbox`; the compiler's helper for macros is
  the same, so Lamp's Xcode projects pass it `-disable-sandbox` too. Xcode's interface and asset compilers hand their
  work to helpers that stay running and are found through shared memory named `ib…`, whoever started them, so the
  profile closes that memory (and no other): a command starts helpers of its own, confined as it is. Nothing reads a command's text
  for paths any more; don't bring that back.
  A command may write at the app's folder's own name, so it can swap the folder for a link to anywhere, Lamp's
  folder included. The profile, the file checks (`Privacy.verdict`, pi's `checkFile` and `delete_file`, which take
  the folder from `LAMP_DIR`) and Lamp's own writes for the agent (`Store.deleteFile`, `artDestination`,
  `Previews.destination`) all take the app's folder as `LampProject.realDir`: the folders above it worked out, the
  folder itself by its name, never where it leads. Don't resolve `project.dir` itself to decide what's the app's.
  What Lamp reads there outside the sandbox and passes on goes through `AppFile`: each step of the path opened from
  the one before it, none of them a link, and only a plain file read. That's what reaches the agent (what the app
  printed, its screen as text, its answers to Lamp, its pictures and their copies, the app's notes and what was taken
  back from them, the note after a restore), what Lamp writes into the app's code or hands an engine (its secrets,
  `Template.ownSecret`, and the conversation ids), and what Lamp rewrites in place (the migration, a rename, the
  live layout), which would otherwise bring what a link leads to into the folder. A new such read belongs there. Lamp's own
  writes there around a build go through `AppFolder` on the same terms (see "Generated apps").
  The profile also closes Homebrew's folders (`/opt/homebrew`, `/usr/local`) for writing (reading and running
  what's there stays open): they're on the path of everything Lamp runs as itself, so a command could otherwise
  leave a program there for Lamp to run unconfined. The agent can't `brew install`. `/Applications` and the developer folder in use
  (`Sandbox.developerFolders`: `DEVELOPER_DIR` and xcode-select's choice, the whole Xcode wherever it is) are closed
  for writing the same way: an Xcode dragged there is the person's to write, and Lamp runs its tools as itself. A program Lamp runs outside
  the sandbox (in a `Shell.run` command, `signing-identity.sh`, Claude Code's hook) is named by its full path
  (`/usr/bin/codesign`), never found on the path. Apple's developer tools are the exception to `/usr/bin`: `xcrun`, `xcodebuild`,
  `git`, `swift` and the rest there are wrappers that find the real program through a cache in the temporary
  folder, which the sandbox leaves writable. So what Lamp runs of them as itself (`simctl`, `devicectl`, the phone's
  `xcodebuild`, the look at the person's git settings) is the real program in the developer folder in use
  (`DeveloperTools.path`), never the wrapper. Inside the sandbox the wrappers are fine.
  Lamp's own git (saving a version, Undo, restore, version names, the look for unsaved work) runs under the
  same sandbox, through `Versions.git` (`gitBlocking` where it can't await): the app's folder is the agent's
  to write, its `.git` included, and git runs the programs a repository names (hooks, filters, a signing
  program), so unconfined it would run whatever the agent left there. A new git call on an app's folder
  belongs in that helper, never in `Shell.run` directly. Lamp looks at an app while a turn saves it, so its git
  runs with `GIT_OPTIONAL_LOCKS=0` (a look never takes the index's lock), and a save goes through
  `Versions.commitAll`, which tries again when it is shut out and tells a save that failed from one with
  nothing to save; a turn whose save failed says so in the chat. The one exception is the helper's own look at the
  person's Mac-wide git settings (`Versions.personalFiles`), which the sandbox closes: it reads files the agent
  can't write, runs no program, and opens to Lamp's git only the files those settings name, never a folder
  and never anything in Lamp's own folders. Nothing in an app's history is checked, cleaned or
  refused, and the agent may use git on it as it likes. On Lamp's own runs signing, hooks and the
  file-watcher command are off (`Versions.environment`): the sandbox closes the person's keys, and a hook
  could only stall a save.
  Undo Last Change also sits under the latest change in both chats (`UndoOffer`, `ChatLook.UndoChange`): it is
  `Store.undo`, given the version it was shown for and refusing when the app has moved on. It shows only when that
  Undo would take back just this change, and when the older code can still read what the newer saves: the compiler's
  layout of each type with coding keys (`LiveReload.layout` with raw values) is compared by the keys and values
  actually written: a removed, renamed or retyped required field, a retyped optional one, or an enum value the older
  code doesn't know hides it. Undo puts back code, never data. Data is copied, though: before a change goes into a Mac app, by reopening it
  or live, Lamp copies its LampStore database into its Backups folder, named after the version that wrote it
  (`DataSnapshots`, beside the app's own once-a-launch copies).
- **Pictures the agent is shown** (`look_at_app`, `use_app`, `make_art`): the conversation is sent whole with
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
  has answered. A message goes into the chat as it's handed over and is a request of the turn (its version,
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
- **What Lamp shows the user** (`BuildCard.activity`, `ToolCall`): tool names must be recognised in every
  engine's spelling. Claude Code calls MCP tools `mcp__lamp__<name>`; `Engines.plainName` strips that.
  Codex reports them as `mcp_tool_call` items. A turn has one activity (`TurnProgress.activity`, and since when,
  `activitySince`), and every place that shows it draws it with `ChatLook.ActivityText`: the build card, the line
  under a change, the chat beside the app (`SidebarState.workingActivitySince`) and the cover while the app reopens
  (`CoverNote`). How it reads as the wait goes on is `Activity.words`, in one place: while the model thinks, its
  phrases (never a bare "Thinking"; each think opens on one picked by when it began) turn over every 3.5
  seconds and grow more reassuring the longer it goes; a build says "Still building…"
  after 30 seconds and "Taking a little longer…" after 90, and putting a change into the open app "Still updating…"
  and "Taking a little longer…"; anything named ("Working on the interface") stays as it is.
  The agent's progress lines are messages above the activity and are left as they are. A shell command is named in
  the engine's own words, never guessed from its text (`AgentEvent.naming`): Claude Code's description of each Bash
  call (its parser, and its approval hook, which carries the same input; `Agent.claudeNote` asks for plain words),
  and for Codex the heading of the reasoning summary before it (`model_reasoning_summary`). The name is the activity
  while the command runs and the step's row in the chat (`LogLine.said`, `ChatLook.RanCommand`; consecutive commands
  under one name are one row, `ChatItem.items`); a command with no name stays "Did a bit of housekeeping". pi's bash takes only the
  command, so Lamp's extension replaces it, as pi's extension docs allow, with pi's own bash and a `description`
  (`bashWithDescription` in `lamp-tools.ts`), sent with the approval and read by pi's parser. It's required: left
  optional, some models (Sonnet) never fill it in. While Lamp itself works in a turn (a look's build, putting a change
  into the open app, reopening it) the activity says what Lamp is doing at each stage, so nothing it said earlier
  stays: the whole build that follows a change put into the open app is "Building…" (`Store.awaitLiveBuild`), and a
  look that reopens the app builds it whole without putting the change in first. While a look runs, what the
  engine's output says (its tool call starting, a streamed reply) doesn't change the activity (`Store.noteAgent`):
  every engine reports the call a moment after the look began, and its fixed word would cover each stage after it
  (building, installing, opening, looking at the app, watching it move); when the look ends it's "Thinking". No clock
  is shown beside the activity, in the chat, the build card or the cover: the turn's whole time is its "Worked for…".
- **Models**: each engine has its own model list and picker (`Builder.engineModel`); never default to Haiku.
  Where an app's text AI goes is an `AppAI.TextRoute` (an OpenRouter model, the Claude Code or Codex sign-in,
  pi with its key provider, or a model on this Mac), listed by `AppAI.textRoutes` for the pickers in
  Settings → Apps (an app's info panel only shows what answers it), and dispatched by kind in `AppAI.dispatch`. The default
  (`AppAI.defaultRoute`) is the local model that builds apps when there is one, else Sonnet through
  OpenRouter with a key, else the builder's own sign-in. Settings → AI Providers lists each provider and
  sign-in with its state, not what it's used for: that's in the menus that choose it. Decisions
  (`AppAI.decisionModels`, `AppAI.decide`) go to Jev
  through OpenRouter or TypeSafe, to OpenAI's Decisions API (`decideViaOpenAI`, the same questions in its
  predicate/choice/score shape), to a Jev-class model on this Mac (`LocalModels.decisionCatalog`, run on the
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

## The desk

Lamp's window opens on the desk (`WishDesk`, `Desk.swift`): the person's wishes as icons, first, since using one and
changing it is where most wishes start, and under them the one place to make a new one. A click's hint says it
opens to use and change (`DeskIcon`). Wishes are dragged into the order the person wants (`DeskArrangement`, kept by
instance so a rename keeps a wish's place; name order until the first drag, and a new wish goes at the end after it);
while one is dragged, a trash beside Settings in the toolbar deletes what's let go on it (`DeskTrash`), as the Dock's
Trash does (`WishDrag`). Everything someone makes with Lamp is a **wish** in what they read; a wish may
be made of an app, a widget, a menu bar item, a watch app, so "app" stays where it means that piece. A wish is
typed in the bar, or said with the talk button beside it (`TalkButton`, moving with `Dictation.level`); either
way it goes to a new wish's chat and is sent from there (`Store.wish`, `sendWhenShown`), so it passes the same
setup checks as anything typed in a chat. A click on a wish (or Return, or Open on its menu) opens it to use and
change at once (`Store.open(fromDesk:)`): a Mac app with windows opens with
its chat beside it (`Store.change`, below; a notification's click goes the same way, `Store.openChat`); a wish that opens no window is used (`Store.use`), and one still coming
true, or waiting on an answer, opens its chat. Change… on its menu changes it the same way, or in Lamp's window. Under each icon is only its
name: a spinner or a dot says what's going on with it, and VoiceOver also hears where it lives (`WishPlace`, read
from its files). While the pointer is on a wish, its picture and what it is take the place where a new wish is made
(`WishStage`), which steps back and fades. When it's used where nothing comes
forward (the menu bar, a widget, the background, the person's own phone) the desk says so in `WishHUD`, a
large translucent square like macOS's old volume display. Its chat has a back button (⌘[) to the desk.

"Help me find one" (`Store.findWish`) is the site's wizard in the app, held in the ordinary chat: a new wish
marked `finding` whose first request is `Agent.findingRequest`. The agent asks about the person's days in
`ask` cards (`Agent.findRules`), never about apps, and ends by writing the wish into the message box with
`write_wish`, word by word as a wish from the site arrives (`Store.writeIn`), for the person to change and
send. Until that message, nothing is named, scaffolded, built or saved (`startQueued`, `turn`): the wish it
becomes may be an iPhone app, which a scaffold already written as a Mac app would rule out. The message that
isn't an answer to a card names it like any first request and ends `finding`.

A new person's desk isn't empty: Lamp comes with twelve wishes (`Starters`, from `Resources/Starters`), working
apps to use as they are and to change into their own, which shows what Lamp does better than a question about
what to make. So the welcome is the hello and setup, and ends on the desk (a wish from the site is still made
once setup is done). They're copied once, on the first launch, each saved as its first version ("From Lamp"),
and from then on they're the person's: a later Lamp with other starters gives those only to new people. As soon
as Apple's tools are there they're built one by one out of sight (`Store.prepareStarters`), with nothing in
their chats; nothing on the desk shows it; one clicked before its build is done spins, says it's opening, and opens when it's
ready (`openWhenReady`). A
starter opens with its chat beside it the first time (`MagicPanel.startWithChat`, the hand-off a new app gets after
its first build); one that opens no window has its chat opened in Lamp the first time it's used. The chat opens on
Lamp's own card (`Starters.card`, an `ask` marked `offer`): the starter's line and its three changes, each sent as
the first request when clicked, with the message box answering it too. Nothing waits on it (`Talk.waiting`), so the
desk doesn't say it has a question and using it still opens it. Each
folder holds the app's code, APP.md (which the agent reads first, so it knows the app it's changing), icon.json
(its design), the icon drawn from it in icon/ with its artwork, drawn once the way an app's is: layers of glass
(icon/art.json, `GlassIcons`) or, for a game, a painting (icon/art.png). The artwork goes where an app keeps its icon's,
since Lamp draws none for a starter on the person's Mac, which would offer to set up pictures in its chat;
`StarterIconsTests` draws the icons again, with Xcode set up for the Liquid Glass one, and the artwork again with
`LAMP_PAINT_STARTER_ART=1` and a key), so the desk
shows them at once and Lamp draws one again only once its icon.json changes (`Starters.hasShippedIcon`),
preview.png, a picture of its window that the desk shows while the pointer is on the icon,
with the app's about.json line beside it in large type, 90 characters at most (`WishStage`, `WishDesk.describedIn`; every
Mac app saves a fresh one at each launch, `LampRuntime.preview`, and Lamp takes one of the simulator for an iPhone
app, both at `Runtime.previewURL`), and starter.md, Lamp's own: the wish's name and what its chat offers to change first, a line and three changes, each
with its tile's symbol (`- drop: Add a water counter`): changes the app doesn't do already, that the agent can make in
one request with no key, account or pictures to draw. They
are Mac apps that need no key or account, use the AI the person builds with when they use any, and come with
example content they can clear. After changing LampSupport.swift, `scripts/check-starters.sh` type-checks them.

Starters not on the desk (never added, or deleted since; `Starters.missing`) are offered at its end as one dashed
tile, Starter wishes (`MoreFromLamp`): up to four of their icons and how many there are, and a click lists them with
an Add each. Add puts that one back (`Store.put(starter:)`, through `Store.add(starter:)`, the one way a starter is put
on the desk, which the first launch uses too), saved and built out of sight like the first launch's. The tile goes
once every one is there.

**A starter added or changed in how it looks ships a new preview.png in the same change** (`StartersTests` fails
without one). Take it from the app itself, not a mock-up: open the starter's build in Lamp Dev with its chat closed,
and once its window has settled its `.lamp/runtime/preview.png` is the picture (the app writes it at each launch,
without Lamp's chat). Shrink it to at most 800 px on the long side (`sips -Z 800`) and copy it to
`Resources/Starters/<folder>/preview.png`. Look at it before committing: example content only, nothing from the Mac
it was taken on (names, folders, accounts). A starter that opens no window (the menu bar) is pictured with its
panel open.

**Turning an app made with Lamp into a starter.** The app's folder is under `~/Library/Application Support/Lamp
Dev/Apps/<folder>` (or `Lamp/Apps` for the installed Lamp). Into a new `Resources/Starters/<folder>`:

1. Copy its `Sources` without `LampSupport.swift` (and `LampScene.swift`), `Widget/` without `LampWidgetSupport.swift`,
   `Share/` without `LampShareSupport.swift`, `Assets/`, `capabilities.json` when it has one, `icon.json` and `about.json`. Never `build.sh`, `Package.swift`, `.lamp/`,
   `Attachments/` or anything else Lamp writes.
2. Read the code for what only works for its maker or only for now: a date written in (a deadline, a year) goes
   relative to the first launch and is saved then, so the app means something whenever Lamp was installed; a global
   shortcut mustn't take one the system or common apps use (⌘⇧G is Go to Folder everywhere); a key,
   an account or the maker's own files and names have no place in it. Content is example content the person can
   change or clear.
3. Write `APP.md` for the agent that changes it, in the shape the other starters' have (`Kind:`, what it does,
   Code, Data, Easy to change), from the code as it is, not the app's own APP.md.
4. Write `starter.md`: `name`, `offer` ("Make <name> yours") and three tweaks of at most six words, each with an SF
   Symbol. They're changes the app doesn't already make, that the agent can make in one request with no key,
   account or pictures to draw.
5. Take `preview.png` as above (the app's own `.lamp/runtime/preview.png` is the picture when it shows only example
   content), paint and draw the icon with `LAMP_RENDER_STARTER_ICONS=<folder> LAMP_PAINT_STARTER_ART=1
   OPENROUTER_API_KEY=… swift test --filter StarterIconsTests` and look at the artwork it picked, then run
   `scripts/check-starters.sh <folder>` and `swift test --filter StartersTests`, and update the count of wishes above.

## Two Lamps on one Mac

A build from source is **Lamp Dev**, a separate app from the Lamp people install: its own name and icon (an
orange DEV banner), bundle id (`dev.lamp.host.dev`), folders (`~/Library/Application Support/Lamp Dev`,
`~/Applications/Lamp Dev Apps`, `~/Library/Logs/Lamp Dev`), gateway and model-server ports, URL scheme
(`lamp-dev://`) and Keychain entries, and no self-updating. `Sources/Lamp/Edition.swift` is the one place
these come from, read off the bundle id that `build.sh` writes (`FLAVOR=dev` by default; `release.sh` passes
`FLAVOR=release`). Anything new that names Lamp on disk or on the network goes through `Edition`, and the
generated apps get it from their Info.plist: Lamp writes what an app is told about itself and Lamp (its folder name,
its secrets, Lamp's ports, scheme and folders: `Template.installValues`) into every copy it installs
(`Store.setInstallValues`, and the phone project's Info.plist), and LampSupport reads it at launch (`LampInstall`).
None of it is compiled in, so a compiled app is the same for every install. The app-signing keychain is shared on purpose, so apps keep their permissions whichever
Lamp rebuilds them. `scripts/dev-data.sh` copies your apps, keys, settings and the agent's sign-ins from the
installed Lamp into Lamp Dev, so the development build has something to work on. A build from a checkout under
`.claude/worktrees/` is an instance of its own, "Lamp Dev <worktree>" (`scripts/instance.sh`, which `LAMP_INSTANCE`
overrides; empty makes the plain Lamp Dev): its bundle id ends in the name, and `Edition.instance` gives it its own
folders, four ports from a hash of the name, URL scheme and prefixes, so builds from two worktrees run at once without
sharing a desk, a gateway or Launch Services' idea of which is which. `fresh-start.sh` and `dev-data.sh` work on this
checkout's instance. The agent's sandbox closes every Lamp's folder (`Edition.lampFolderNames`), instances included. The Chrome experiment's native host is the one thing instances share: the extension names it, and Chrome keeps one registration per name, so the instance that connected last owns it. To see what someone with a bare Mac
sees, `LAMP_PRETEND_MISSING` (`Pretend`, Lamp Dev only) makes Lamp's own checks miss the Command Line Tools,
Xcode, the person's own Claude Code and Codex or tools from the PATH; a new check for something a fresh Mac lacks goes through it too.

## iPhone apps

Nobody picks what a new app runs on. The first request's naming call (`AppName.suggest`) also lists the devices it
runs on (`mac`, `iphone` for iPhone and iPad; `Platform(devices:)`) and whether the person said so; `Store.chooseKind` takes that before anything is
written: a kind the person didn't say only when this Mac can build it now (`PhoneTools.checked`: Xcode, and a team for
both), else a Mac app with a line in the chat offering the setup (`IPhoneSetupLine`: once it's done, the app is asked to be made for the iPhone, through the agent), and one they said either way (the build says what's missing). A line in the chat says so for
anything but a Mac app. The starter ideas mix Mac and iPhone ones (`Ideas.mixed`). Later, "make it work on my
iPhone too" is the agent's `make_app_for` (`Store.convert`), given every device the app runs on from then on (a
new kind of device is one more name in `Platform(devices:)` and the tool's schema; "watch" brings the iPhone with it,
and the answer tells the agent to add or remove `Watch/` with the watch rule): it checks this Mac can build the new kind (opening the
setup steps if not), quits every copy, changes the kind in meta.json, rewrites Lamp's own files, copies the Mac
settings (UserDefaults) to a new signed id, and answers with the rules for the new kind, which stay in the
conversation; the agent then adapts the code. A Mac app's data doesn't move: LampSupport keeps it under the app's
plain id (`{{DATAID}}`, `Edition.appBundlePrefix` and the folder name) whatever it's signed as, and moves it there
once from a folder named after its signed id. New App makes a draft, a folder with only `.lamp/meta.json`
(`Template.draft`), so its kind and name are just that file; the scaffold is written and committed when it first
builds (`Store.materialize`, in the first turn after naming and in `run`), and `LampProject.scaffolded` tells the two apart. An iOS app is one app for both devices, as Apple has it; **Try On** (in the toolbar and the app's right-click menu) picks which simulator it opens in (`LampProject.family`, iPhone to begin with), or one simulator by name under Choose Simulator (`LampProject.simulator`, kept in `meta.json`; the list is `Simulator.choices`), for what only some models have, such as the Dynamic Island. Lamp's own pick of the family is used when the chosen one is no longer installed, and `look_at_app` tells the agent which simulator the app is open on. It runs in the iPhone or iPad simulator on this Mac (`LampProject.platform == .iphone`,
kept in `meta.json` and through renames). It needs Xcode, not just the Command Line Tools. Lamp's choice of Xcode stays in its own
process (`DEVELOPER_DIR`, which its shells, the engines, simctl and devicectl inherit; xcode-select is never changed): the one
chosen in setup (Use Xcode), else, when xcode-select names the Command Line Tools, one Lamp finds by itself at launch
(`PhoneTools.installedXcode`): only in /Applications, through every link (the bundle, its developer folder and each
tool Lamp runs from it), since Lamp runs its tools as itself and the agent
can't write there, and only once its agreements are accepted, or every build would fail. Builds then use Xcode's toolchain
too, and `Shell.compatibleSDK` goes by `DEVELOPER_DIR` before xcode-select. `Simulator`
(`Sources/Lamp/Simulator.swift`) picks a booted or available iPhone with `simctl`, installs the built bundle,
launches it with its output going to the app's log, and photographs the screen for `look_at_app`. The
scaffold is a Swift package built for the simulator SDK by its own `build.sh` (no Xcode project, no signing
beyond ad hoc). It gets the same `LampSupport.swift` as a Mac app: the library is one source with the Mac-only
blocks (windows, `LampDriver`, `LampComputer`, folders and shortcuts, the clipboard, Mail, permissions, the menu
bar) under `#if os(macOS)`, `LampImage` standing for NSImage or UIImage, and the rest (`LampStore`, `LampAI`
and decisions, `LampScript`, `LampText`, drops, calendar, reminders, contacts, notifications, `LampAssets`)
shared. Type-check it for both SDKs after editing (`swiftc -typecheck`, once with `-target
arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path)`). The system prompt is
assembled from `Agent.Rules`: one rule per block, a `mac…`/`iPhone…` pair where the two kinds differ, so a new
block is described to both in one place. Before a launch, `Store.finishSimulatorBundle` does for the flat iOS
bundle what `deploy` does for a Mac one: usage descriptions, the icon (cut from `.lamp/AppIcon-square.png`,
which `Icons.write` makes from the same tile as the Mac icon) and the chat's attachments, then an ad hoc signature.
Every iOS app carries every usage description (`Template.iosUsageDescriptions`, one list for the scaffold's
build.sh, `finishSimulatorBundle` and the phone's Info.plist), so the agent only requests authorization.
The simulator's build takes its entitlements (Health, iCloud, push) from a section of the binary, as Xcode puts
them: `writeOwnedFiles` writes `.lamp/entitlements.plist` and the iPhone build.sh links it in with `-sectcreate`;
the bundle's ad hoc signature claims none, since the simulator refuses to launch an app whose signature claims a
restricted entitlement without a provisioning profile.
What needs more, the agent declares in `capabilities.json` at the app's root (`Template.Capabilities`:
healthkit, nfc, siri, backgroundModes): Lamp turns it into an entitlements plist for the simulator's ad hoc
signature and the phone project's `App.entitlements`, which Xcode's automatic signing registers, and
`UIBackgroundModes` in Info.plist. `LampMotion` (iOS only, under `#if os(iOS)`) wraps Core Motion. The
prompt's `iPhoneHardware` rule lists what a phone has and what the simulator can't do.
`use_app` drives the simulator from outside the app (`Simulator.Driver`): the Simulator app shows the
iPhone's whole accessibility tree to the Mac, so Lamp finds what's under a point and presses it, sets a
field's text, and sends real mouse events for swipes, scrolls and long presses. Pictures are made at point
size, so a pixel in them is a point on the screen. The same tree, read whole, is the screen as text that
`look_at_app` and `use_app` return beside the picture (`Driver.screenText`: one line per control or piece of
text, with a short id, its name, what it holds and the point to tap it). An action names what it's for by
`target`, an id or exact name from that list (`Driver.find`), and is carried out at the thing's middle; x and y
are for what the list doesn't have. A Mac app does the same for itself (see "Generated apps" below), and the two
lists share one format: `Driver.text` here and `LampScreen.text` in LampSupport.swift are copies, held together
by `MacScreenTextTests`, so a change to one is a change to the other. The app showing the simulator is Simulator, or from Xcode 27 Device Hub
(`Simulator.viewers`), which shows one device at a time: Lamp chooses the device in its list
(`Driver.choose`) and finds the screen a few layers down its window (`Driver.screenBoxes`: a group shaped like
the screen that Device Hub marks `iOSContentGroup`, an undocumented subrole; two candidates in different places
are refused). That needs Lamp to be allowed in System Settings → Privacy & Security → Accessibility; the first
`use_app` asks, by opening that page with a panel at the foot of the Settings window holding Lamp to drag into the
list (`SettingsGuide`; `LampPermissionGuide` in LampSupport is the same panel for a generated app's own permissions,
so a change to one is a change to the other). The panel is the one place to drag from, and asking again (the
next `use_app`, or the app's Open System Settings button) brings the page and the panel back in front. Where the
Settings window can't be found there is no panel: Lamp then makes macOS's own request, and a generated app's
permission screen shows the app to drag on itself (`LAMP_PERMISSIONS=nopanel` shows that screen). The driver runs on its own queue (`AccessibilityActor`), never the main thread, and no call to
the other app waits more than `Driver.patience`; when the screen can't be used, `Driver.Trouble` says which
reason it was, in words for the agent. Device Hub (checked on Xcode 27.0) doesn't pass on mouse or key events
posted to it, so there a scroll is the page scroll the iPhone's own elements offer, a row's swipe action is the
row's own named action, return is the on-screen keyboard's key, and a long press, a sideways swipe and escape
are refused with the reason rather than reported as done. Its list holds the devices added to it, not every
booted one, and it loses a device's display when the simulator restarts: both are told to the agent as they
are. `SimulatorLiveTests` runs the driver against a real window when `LAMP_LIVE_UDID` is set.

**On the person's own phone**: Try On also lists the iPhones and iPads the Mac can see (`Devices.list`, through
`devicectl`): paired ones to choose, and plugged-in ones that haven't trusted the Mac yet, which it offers
to pair (`Devices.pair`, `devicectl manage pair`, which puts the Trust prompt on the phone) before telling
the person about Developer Mode. `LampProject.device` remembers the chosen one. Play and the end of a turn then go through
`Store.installOnDevice`: `Devices.stage` puts together what Xcode builds from in Lamp's own folder
(`Devices.buildFolder`, under `Phone Builds`): `Template.writeDeviceProject` writes a small Xcode project there (one
app target over the package's Sources as a synchronized group, the icon in an asset catalog, the attachments as a
folder reference, a real Info.plist), and the app's Sources, Assets, Widget, Share and Watch are copied beside it, in
`app/`, by a command under the app's sandbox, links kept as links; the project reads that copy by full path
(`Template.reaching`). Xcode copies whatever a link leads to into the app, and on the phone the app can send what it
carries anywhere, so a build folder holding any link but Lamp's own to the widget's shared code is refused
(`Devices.LinkedFiles`). `Devices.build` builds it with `xcodebuild` in the app's sandbox, with only that folder opened
and signing off, so what Xcode does with the agent's code runs as the agent's commands would. Signing for the team in
Settings → Building (`Devices.team`, found from the Mac's Apple Development certificates) happens only as Lamp, on a
copy in a folder the build can't write (`Devices.signingFolder`, `Phone Builds/.signing`), in `Devices.signedCopy`.
What each piece is signed with comes from `TeamSigning`: the same project written there over a few lines of Lamp's
own code and under names of its own (the app's name and program name are in meta.json, the agent's to write; its ids
come from its folder name and the team), which Xcode builds with automatic signing, registering the phone and making
the certificate and profiles with the account signed in to Xcode (Lamp never holds the account); each piece of the
real build, matched by its id, then gets that piece's profile and the entitlements Xcode signed it with, and a build
holding a piece Lamp's project doesn't, or a program or library that isn't a piece's own (`TeamSigning.checkCode`),
isn't signed. Nothing the agent wrote is read for it. The bundle id carries the team (`deviceBundleID(team:)`). `devicectl` installs and
launches the app with `--console`, so what it prints reaches the app's log. The agent's looks stay on the
simulator: the phone's screen can't be photographed. The app reaches Lamp's gateway at the Mac's Bonjour
name (`Devices.macHost`, the `{{MACHOST}}` placeholder, chosen in LampSupport by `targetEnvironment`): the
gateway also listens on the network while some app is set to open on a phone (`Store.syncLocalNetwork`), marks those
requests, and admits them only to the app routes with the Mac's own name as Host (`Store.isMacHost`).
Away from the Mac, a phone app answers for itself (`LampDirect` in LampSupport, device builds only): `post`
first asks `/ai/keys` with a four-second timeout, at most every half minute; while the Mac answers, the
call goes through Lamp as ever and the reply (the OpenRouter key, the TypeSafe key when decisions go there,
and the app's model choices, served by `Store.keysForPhone` only for iPhone apps) is kept in the
phone's Keychain. The reply is sealed with a secret (`Template.phoneSecret(in:)`) kept in the phone's build folder
and written only into the Info.plist there, which the app reads (`LampPhoneSecret`): the app's token is in its
folder, where the agent's commands read it, so the secret must never be there too, nor in LampSupport.swift or the
`.lamp/device` project of an app for both, or a command could ask for the keys and open them. When the Mac doesn't answer, `LampDirect.handle` does
what the gateway would with the provider directly (chat completions with the JSON retry, systemone
decisions, images). The prompt's fencing and dates are made in the library either way. What's spent this
way isn't recorded in Lamp, and `/ai/computer` says it needs the Mac.

## Apps for both the Mac and the iPhone

An app can be made for both (`Platform.universal`, the "Mac, iPhone & iPad" choice beside Mac and iPhone & iPad), as
Xcode's multiplatform apps are: one code, with what differs under `#if os(macOS)` and `#if os(iOS)`, built for
one place at a time. Where it opens is `LampProject.destination`: a Mac app's is always the Mac and an iPhone
app's always iOS, and an app for both goes where Try On last put it (`chosen`, `target` in `meta.json`; "My Mac"
in `TryOnChoices`, `Store.setMac`, and the simulator and phone choices move it to iOS). It can be open in both places at once: Play
and Stop (and the app menu's Quit) are for where Try On points (`Store.isOpen`, from `openOnMac` and `openOnIOS`),
moving Try On closes nothing, and Stop quits only that copy (`quit(only:)`; a Mac build replaces only the Mac
copy). Each copy keeps its log and pictures in its own folder: the Mac copy's in `.lamp/runtime` (`Runtime.macFolder`,
which the app writes itself, and where what only a Mac copy has, such as a held build or its quit reply, is read),
the iPhone copy's in `.lamp/runtime/ios` (`Runtime.folder` while Try On points at iOS). Everything about running,
looking and using branches on `destination` (`onIOS`); what an app could have, such as the Try On menu or the
phone's away-from-the-Mac keys, branches on `Platform.hasIOS` / `hasMac`. Its scaffold and owned files are
their own (`Template.universalAppSwift`, `universalPackageSwift` listing both platforms, `universalBuildSh`,
which takes `mac` or `ios`), and `Store.build` passes the destination; the destination is part of
`Runtime.fingerprint`, so moving the app rebuilds it. The iOS build is the iPhone app's. The Mac build is Xcode's,
from the same project the phone uses (`Template.writeDeviceProject`, with `universalPbxproj`: one target for
`iphoneos iphonesimulator macosx`, the Mac's own `Info-macOS.plist`), built by build.sh in the app's sandbox with
signing off, and signed for the team in Settings → Building when it's installed, so the app can use what Apple ties to
a team, which Lamp's own certificate can't give it (see `Template.WidgetSharing` for why). Without a team the build
stops with the fix, and the setup check (`PhoneSetup`, `requiresTeam`) asks for one before the first request. Its
bundle id carries the team on both platforms (`LampProject.bundleID`), and `Store.deploy` signs its copy, with what
it added (icon, assets, Info.plist), with the team's certificate (`Devices.signingIdentity`), the profile and the
entitlements Xcode signed Lamp's own project with for the Mac (`Store.signForTeam`, `TeamSigning`), never Lamp's
certificate. Those entitlements never include `get-task-allow`, which would let a debugger into the app while it
holds its secrets. The agent gets
both kinds' rules, each marked for its half, after one rule on sharing the code (`Agent.universalPrompt`). An app
for both is shared as a `.lampapp` like any other (the file says what it's made for, format 6, and carries `Watch/` when it has one); its widgets and Live Activities are the iPhone half's (below).

## iCloud

An app with an iPhone half may keep data in iCloud: `{"icloud": true}` in `capabilities.json`
(`Template.Capabilities.icloud`, and `container(for:)`: "iCloud." and the app's bundle id, so an app for both
has one container on both platforms). It becomes the CloudKit entitlements everywhere Apple signs the app
for a team (the phone's and the Mac's `App.entitlements`, the simulator's ad hoc signature in
`Store.finishSimulatorBundle`) and `LampICloudContainer` in each Info.plist, which is how the app knows it was
built for iCloud. A Mac app on its own is refused it: Lamp's signature can't carry iCloud (see "Apps for both").
The data goes through `LampSync` in LampSupport.swift, the one building block for it: collections like
`LampStore`'s, kept on the device in LampStore as well (under `icloud.<name>`), and sent and fetched by
CloudKit's own `CKSyncEngine` in a zone of the app's in the private database, one record per item carrying its
JSON. The later change to an item wins; a sign-in or a zone deleted in iCloud sends everything up again. The
agent is told in `Agent.Rules.icloud` (iPhone and both-kind prompts) when to use it and that the simulator is
usually not signed in. The team must be in the Developer Program: a free account's build fails at signing, so Lamp
says so first, wherever the app is about to be signed for the team: on the person's phone, or as the Mac half
of an app for both (`PhoneTools.xcodeFreeTeams` reads which teams are free). Before Open and Rebuild & Open
and when a phone is chosen it is the setup check (`PhoneSetup.Context.requiresPaidTeam`); a message is never
held for it, since asking the agent is how iCloud is taken out again, so after a request it is one line in
the chat where the build would start (`Devices.membershipProblem`, in `Store.installOnDevice` and
`Store.build`), not sent to the agent as an error to fix. On a phone the turn's change is already built for
the simulator and saved; on the Mac half that build is the turn's only one, so the change stays in the app's
files unsaved, as after any build that fails. In the simulator nothing is signed for a team, so a free
account goes on working there.

## Apple Health

Health data goes through `LampHealth` in LampSupport.swift, the one building block for it: a `Kind` for each
kind of data (steps, calories, heart rate, sleep, weight, what was eaten and drunk) with its HealthKit type,
unit and the unit's name, and calls to authorize, read a day's total or average, daily totals, the latest
sample, samples, last night's sleep and workouts, and to save a sample. It needs `{"healthkit": true}` in
`capabilities.json`, which is the iPhone's entitlement only (`entitlementsPlist(container:platform:)` leaves
it off the Mac half's signature, which couldn't carry it): a Mac has no Health data, `isAvailable` is false
there, and an app for both reads on the iPhone and keeps what the Mac shows in LampSync. The simulator has
HealthKit with no data in it, so the agent is told to save a sample before reading (`Agent.Rules.iPhoneHardware`).
`HealthTests` compiles the block out of the template and checks every kind's unit.
Apple's Developer Program License Agreement (3.3.3(D)) forbids using iCloud or CloudKit for sensitive,
individually-identifiable health information. The "sensitive" matters: the iCloud rule (`Agent.Rules.icloud`)
keeps what is medical (diagnoses, conditions, symptoms, medications, lab results, clinical records, reproductive or
mental-health entries) on the device, and lets everyday activity and fitness numbers such as step counts sync,
which they aren't. When it's unclear, on the device.

## Work while an iPhone app is closed

`{"background": true}` in capabilities.json means on iPhone what it means on a Mac: the app works while nobody is
looking. A Mac app opens at login and keeps running (`LampBackground`); an iPhone app is woken by iOS to run its
`LampSchedule`s, the same calls as the Mac's (`daily`, `every`), from the iOS copy in LampSupport. Lamp declares
one task for it (`Template.scheduleTask`, "lamp.schedule", with the fetch mode, in `Capabilities.lists`), and the
app's WindowGroup carries `.lampBackground()`, SwiftUI's `backgroundTask(.appRefresh)` running everything due and
asking for the next time (a no-op on the Mac, so an app for both shares the code). iOS ends an app that asks for a
task it has no handler for, so a request is made only once `.lampBackground()` has run and only when the app goes
to the back or after a background run, never as a schedule is made. iOS decides when: near the time, a few times
an hour at most, less for an app rarely opened; the simulator refuses every request, so the work is tried by
running it from the app. Notifications go with it (`LampNotifications`, both platforms): `at:` for later,
`id:`/`cancel` to replace or take one back, `actions:` buttons that work without opening the app, handled by
`LampNotifications.onAction` set at launch, and on iPhone `timeSensitive:` with `{"timeSensitive": true}`, the
entitlement. The rule is `Agent.Rules.iPhoneBackground`, and `Rules.notifications` in both kinds' blocks.

## Photos, location, weather, music and the home

Five more building blocks in LampSupport.swift, each the one place for its framework: `LampPhotos` (Photos: the
library by day and place, albums, a picture at a size, what a picture shows by Vision, saving; the picker is
SwiftUI's), `LampLocation` (CoreLocation: where the person is with a name from the map, watching big moves,
and on the iPhone the visits where they stop, kept in LampStore), `LampWeather` (WeatherKit: now, hours, days),
`LampMusic` (MusicKit: recently played, the library, the catalog, playing; and on the iPhone what the Music app
is playing) and `LampHome` (HomeKit, iPhone only: accessories with their room and state, switching, dimming and
locking). The first four compile on both platforms. Weather and the home are entitlements, declared in
`capabilities.json` as `weather` and `homekit` (`Template.Capabilities`): weather goes to both halves of an app
Apple signs for a team and never to a Mac app on its own (`weather(for:)`), the home to the iPhone's signature
only. Apple also wants WeatherKit and MusicKit turned on for the app under App Services at developer.apple.com,
which automatic signing doesn't do: the blocks' failures say so. The reasons the system shows are in
`iosUsageDescriptions` and, for the Mac, in `Store.deploy` and `universalMacInfoPlist`. The agent is told in
`Agent.Rules.sharedBlocks` (both kinds) and the Home part of `iPhoneBlocks`.
Two of them carry Apple's own terms, which the rules repeat. HomeKit is only for an app whose job is the home,
and what it reads may not leave the phone (3.3.3(I)): not to an AI model, a server, iCloud or the Mac. WeatherKit
(Attachment 8) wants Apple's attribution wherever its weather is shown, which `LampWeatherAttribution` draws
(the Apple Weather mark from `WeatherService.attribution`, linking to its sources page), allows forecasts to be
kept only briefly, and rules out apps for emergencies.

## Generated apps

Lamp owns three files in every app and never trusts what's in them: `Sources/LampSupport.swift`, `build.sh`
and `Package.swift` are written afresh before every build (`Template.writeOwnedFiles`), and the build stops if
that fails. The last two are what the build runs (the shell runs build.sh; SwiftPM compiles and executes
Package.swift as a program), so they're replaced rather than checked: nothing the agent's file tools wrote
into them, with no card, can run. Shared apps never carry them: import writes its own.
Replacing them isn't enough on its own: they sit in the agent's folder, and a command it left running can put
its own there between Lamp writing them and running them. So the build runs as the agent's commands do, in the
app's sandbox (`Store.runBuild`, through `Sandbox.run`), and so does everything else Lamp runs over what's in
that folder: the compiler's looks at the code for live changes and Undo (`LiveReload`), and the finishing of a
simulator bundle (`finishSimulatorBundle`). Xcode's builds are no different: the phone's and the Mac half of an app
for both build in the sandbox with signing off. Only a copy Lamp made in its own folder is signed with Lamp's or the
person's keys (`Store.deploy`, `Devices.signedCopy`, `TeamSigning`). A new command of Lamp's that reads or runs what's
in an app's folder belongs in `Sandbox.run`, never in `Shell.run` directly.
What Lamp itself writes there around a build (its own files, what the build was made from, the stamp in the built
app, the live copy's records, the simulator bundle's files) goes through `AppFolder`, which follows no link on the
way: a build can leave one where any of them goes. Writes that aren't part of a build (the notes, meta.json) don't go through it.

`Sources/Lamp/Template.swift` holds `LampSupport.swift`, the support code copied into every generated
app (`LampAI`, `LampStore`, `LampScript`, the connectors, `LampDriver` for `use_app`). It is a Swift
string: after editing it, extract and type-check it (`swiftc -typecheck`), and bump anything that detects
an outdated app (`Store.open` rebuilds apps built by an older Lamp).

A Mac app's reasons for its permissions are one list, `Template.macUsageDescriptions`, written by build.sh, the
Mac half of an app for both (`universalMacInfoPlist`) and `Store.deploy`: macOS kills an app that asks for
the photo library, Bluetooth, the camera and the like without one. A new one goes in that list and nowhere
else, only for something macOS refuses without it (location and music are asked about with none), and is
named in the prompt's `{{EXTRA_PERMISSIONS}}`. The list is part of `BuildStamp`, so apps built before a
reason was added are rebuilt when next opened.

`use_app` on a Mac app is carried out by the app itself (`LampDriver`, reached by a distributed notification
signed with the app's token, `Store.use`), so no Accessibility permission is needed. With every picture the
app writes its front window as text (`LampScreen` in LampSupport.swift, `.lamp/runtime/screen.txt`): one line
per thing its own accessibility tree names (NSAccessibility walked in-process, SwiftUI's elements included),
with a short id, what it is, its name, what it holds and its middle in the picture. `look_at_app` and `use_app`
return it beside the picture (`Runtime.screenText`), the same lines the iPhone driver writes. An action names
what it's for by `target` (an id or exact name, `LampScreen.find`): a button, switch, link or choice is asked
to press itself (`accessibilityPerformPress`), a field takes the text in place of what it held, a slider or
stepper takes a number or a step, and what has no action of its own, or isn't listed (a drawing, a canvas),
is clicked at a point, pixels in the picture. Lamp tells an app built before the list existed by a line of the
heading in its binary (`Store.screenTextMarker`): such an app is told to be rebuilt when a target is used.

A Mac app can be changed while it's in use (apps show the wand while the file `MagicPanel.flag`, which Lamp writes
at launch, is beside their folders, checked each time a window comes forward): `LampMagic` in LampSupport.swift puts a
wand at the top right of each of its windows, which opens the app's chat beside that window
(`LampSidebar`; where it goes is below) and stays where it is while the chat is open, lit, closing the chat when
clicked again, so people always find it in the same place (`LampMagic.showWand`); the app menu's Customize with Lamp… (⇧⌘E) opens it too (`LampSidebar.openFromMenu`), and in Lamp's window
when the app has no window to put it beside. In a window with a title bar the wand is a title bar accessory. A
window whose content runs under a title bar with nothing in it (a game, `.hiddenTitleBar`) has no bar for it, and an
accessory would give it one: there the wand floats at the top right over the content, level with the traffic
lights, on a dark disc of its own so it shows over any content (`LampMagic.isFullBleed`, `float`, `FloatingWand`). The wand
is wherever the app shows itself, so people can count on finding it: a menu bar app's panel has it at its top right,
in a strip of its own above the app's content (`LampMenuBar.PanelWand`), and a menu has Customize with Lamp… with the
wand's symbol beside Settings… and Quit. Either opens the panel as a window of the app's (the one shown when the icon
is hidden) with the chat beside it (`LampMenuBar.customize`, which Customize with Lamp… does too when there's no
window), since a panel closes at any click elsewhere; a change that reopens the app opens that window and its chat
again, only just after such a quit (`chatQuitKey`). A Mac widget has it in its top right corner (`.lampWand()` in
Lamp's own widget file, which the widget rule asks for): a link the app takes as Customize with Lamp…
(`LampWidgetLinks`, which passes every other link to SwiftUI, or for a widget-only app to whatever opens it).
This is how a new app is changed from its first build on:
as soon as a new Mac app's scaffold is built and opened at the start of its first turn (`Store.showEarly`, then
`Store.present`; else at the agent's first look, or at the end of that turn), its chat window closes and the app opens the chat beside its content, so the rest of the turn's passes go
in while the person watches (`MagicPanel.handOff`, once per app, marked by `.lamp/sidebar-handed-off`; the chat window
closes only once the sidebar has connected, so Lamp neither quits nor leaves the chat nowhere). Lamp asks the app
with a file in its runtime folder for a copy still starting and a notification for one already running
(`MagicPanel.openChat`, `LampSidebar.openForLamp`). The first time the person closes the chat, a popover points at
the wand to say how to get back (`LampSidebar.coach`, once per app). The
chat is an ExtensionKit extension Lamp puts in every Mac app it installs (`Sidebar.install`: Sources/LampSidebar,
built with Lamp and copied into `Contents/Extensions/LampSidebar.appex`, with an extension point of the app's own,
`<bundle id>.lamp-sidebar`): macOS shows an extension bundled in the app without asking the person, in a sandboxed
process of its own whose view the app hosts (`EXHostViewController`) but can't draw, read or type into. Lamp draws
the chat's content, never the app: the extension shows what Lamp sends and passes on what the person does
(`SidebarWire`, one JSON value a line, in Sources/LampSidebarKit), so all the chat does stays in Lamp
(`SidebarServer`: the lines as Lamp's window shows them without Agent Details, gathered and spaced as `Transcript`
does, the draft, attachments, the open question card). Without Agent Details a finished turn's steps are one line above
its answer, "Worked for 2 min 3 s" from the turn's summary, which opens to show them (`ChatItem.items(gather:)`,
`ChatLook.Worked`); a turn still going shows its steps as they come. Both draw the chat with the same pieces, in
Sources/LampSidebarKit (`Composer`, the message box; `ChatLook`, the bubbles, statuses, progress line, Stop and Send),
so a change to how Lamp's chat looks is made there and reaches both; the sidebar program is part of `BuildStamp`, so
apps installed with an earlier one are built again when next opened. It reaches Lamp on this Mac's own address at `Edition.sidebarPort` (macOS keeps other apps, Lamp
included, out of an extension's folder, so a socket there can't be made), and Lamp listens to a connection only
after finding which process is on its other end (`Sidebar.app(on:)`, by the connection's port among the processes
running a sidebar) and checking that it runs the very extension Lamp signed for that app: the hash of what was
signed is kept in Lamp's own folder (`Sidebar.remember`), and the extension is signed with the hardened runtime so
nothing can be loaded into it. The extension must start as Apple's own do, through `_NSExtensionMain` (the linker's
entry point), or it crashes before its code runs. Whatever the app's process can do, its generated code can, so the
app has no way to speak to the agent that builds it: it only shows the chat, says where its window is, and closes or
moves the panel when the chat asks (`LampSidebarHost`, the one thing the chat asks of it). The draft
is shared with Lamp's window (`Store.updateDraft`). A sidebar left open opens again with the app's first window when
the app reopens (`LampSidebar.restore`). An app
installed without the extension (by an earlier Lamp) shows its chat in Lamp's window instead. A change still reopens
the app; the rule (`Agent.Rules.macGenerated`) asks the agent to keep what the person was looking at in
`@SceneStorage`, so it comes back as they left it. To make that look like the window changing in place: as the app
quits it leaves a picture of its front window and where it was in its runtime folder (`LampMagic.leaveCover`); while
the app's turn is going, Lamp shows that picture where the window was (`MagicPanel.showCover`, a borderless window
with the turn's activity in its middle, "Updating…" once the turn is over, and the chat's blank paper where a chat beside it was: `cover-chat-frame.txt`, `MagicPanel.chatCover`), the new
copy opens its first window in the same place (`putBack`), and the picture fades out once the new copy reports its window
(or goes when the turn ends without it).
While Lamp builds a change for a Mac app that's open, the app's windows glow softly at their edges, blurred and
going round blue, purple and orange, and a band of light crosses them as the change goes in (`AppTransition`, drawn by
`LampTransition` in LampSupport.swift; Lamp's cover carries the same glow, `TransitionGlow`). It starts in `Store.build`,
lands in `reloadInPlace` (or, after a reopen, once the new copy's window is on screen, `landWhenShown`), and fades after `install` otherwise (held for Reload,
kept open, failed); Lamp renews it while the turn goes on and the app lets it go after 90 seconds unrenewed. The app
draws it in clear child windows that let clicks through and are left out of its pictures (`windowsOnScreen`), so the
builder never sees it; requests are signed with the app's token, with their time and an id, and taken once. An app
built before it has no `lampTransitionSignature` in its binary and is sent nothing: its next change reopens it with
the new building blocks. Try it in the gallery's Transition entry on an open app.

Where the chat goes (`LampSidebar.show`): always a panel of its own beside the window, never inside it (a column there
took more room from the app than it gave the chat). It's a borderless `NSPanel` attached as the window's child
(`LampSidebar.Beside`), so macOS moves, stacks, hides and takes it to Stage Manager's strip and other Spaces with the
window, holding the chat on a card of the chat's own paper (`LampSidebar.card`, `LampSidebar.Paper`, and `chatGround` in
the chat), opaque: glass let what's behind the window show through, which drew the eye from the chat, and drew a bright
line round its edge. It goes on the side with room, the right first, at its kept width or
the room there is down to its narrowest. Opened where neither side has room, the window makes some (`makeRoom`): it moves
over on its screen when that's enough, else it's made narrower, never below its own smallest width, to leave the chat its
narrowest on the right, and gets the width back when the chat closes (`narrowedBy`, each window its own; a change that reopens the app hands it
to the window put back in its place, `handOn`; given back after full screen when the chat was closed there). Only where neither can be done (full
screen, a window that can't be that narrow) does the chat go over the window's right edge, below its title bar, still its
own panel (`Chat.over`). A move or resize the person makes never moves or narrows their window: the chat changes side, or
goes over the edge when neither side has room, and back beside when there's room again (`replace`); going in and out of
full screen takes the panel down and puts it back where it now goes. Dragged by the chat's bar, the panel comes away from
the window (`Beside.detached`): no longer its child, it goes where it's put, floats over the app's windows while the app is
in front, and stays there through the window's moves and the chat closing and opening again, until the app quits (or the
window goes full screen), when it goes back beside the window. The press lands in the chat's process, so the chat asks the
app to move it (`startMove`) and the app follows the pointer until the button is let go. The chats' process can't
tell which of an app's chat connections is its own, so it asks over each with one request id, and the app picks the
chat once per request (`LampSidebar.isAsked`: the one under the pointer, else the one with the keyboard). Beside the window the chat is
dragged wider or narrower by an edge of its own (`Edges`, the panel's outer side, or the side facing into the window when
it's over it); moved away, by any edge or corner. The edges are a rim inside the card around the chat (`Beside.rim`), not
room around it: the glass glows a little past its edge, and a margin showed that glow cut off square by the panel. The width stays between
`LampSidebar.narrowest` and `widest` and is kept for the app (`LampSidebar.width`). The edges sit beside the
chat, never over it: the chat is drawn by another process, which takes every click on its part of the window. The panel
is told outright to take mouse events (`ignoresMouseEvents` off): its glass is drawn by the window server, so its own
pixels are clear, and a clear window lets clicks on clear pixels through. The panel takes the keyboard for the message box
without becoming the main window. The chat's bar is one row drawn by the extension (`ChatBar`): a red close button like a
window's, which asks the app to close the chat (`closeChat`), "Customize" and the app's name, then the buttons: Wish Info,
Share (the file is made by Lamp and handed over whole, `SidebarState.sharing`, since the extension can't read it; sent
once, so the extension keeps it as it's read, `Link.sharing`), Agent Details and Delete, then Undo Last Change and Versions.
Where the title and every button don't fit, Undo stays and a button for the rest takes their place, which pressed stays
lit and puts the rest, Versions beside Undo, in the title's place. The room between the buttons moves the chat. ⌘` goes
through the app's windows with each open chat right after its window (`LampSidebar.watchCycling`), since macOS leaves
panels out of its own cycle. Versions and Wish Info show as panels in place of the chat (`VersionsPanel`, a page of versions at a time with the rest a click away; `InfoPanel`; the info rows are
`AppInfoView.sections`, the same list Lamp's window draws). An app's chat is in one place at a time: when it opens beside
the app, its window in Lamp closes, unless Lamp is in front with that window (`MagicPanel.chatOpenedInApp`). Lamp's window
keeps the chat where there's no app window to put it beside: a wish not yet made or being found, a menu bar app, a widget,
a background app, an iPhone app, an app built by a Lamp from before the sidebar, and setup cards' keys, sign-ins and
Image Playground. An app opened for its chat that never connects one (it couldn't start) has its chat shown in Lamp's
window (`MagicPanel.showChatIfAppNeverComes`). The chat is drawn by another process, which AppKit's focus doesn't follow
(what had the keyboard, a list say, keeps it through a click in the chat), so once a click in the chat has landed the
keyboard goes to it (`LampSidebar.watchClicks`). Point at the Screen is an item of the + by the message box, beside
Attach a File…, in both chats (`ChatLook.MessageBar`'s `point`, `PlusMenu`) while the app is open on this Mac (`MagicPanel.point`; from Lamp's window, Lamp comes back in front when it's done). It lets the person point at part of the app: the app lays a clear window over its own (`LampMagic.Picker`), outlines the smallest named
thing under the pointer from its own accessibility tree (`LampDriver.elements`), a click where nothing is named (a game's
ball, a drawing) takes the area around it, and a drag draws a box of the person's own; it then leaves a cropped
picture in its runtime folder and says what it is (an area is named by where it is, "Top left area"); Lamp attaches that picture to the message, named after the
thing ("Save button.png", `MagicPanel.name`), and takes a picture only from that folder. In both chats' message boxes it is
one pill (`ChatLook.PointedPill`: what it is and what it's part of, from the app's own row or the heading above it),
which a click points again and its × lets go; pointing again replaces it, and nothing is left drawn over the app.

Whether the change was asked for beside the app or in Lamp's window, a change goes into the open app without a restart when it can (`LiveReload`). The
Mac app, or the Mac half of an app for both while Try On points at this Mac, is
built live (a widget or share extension is built from the same copy, and a change to one reopens the app): build.sh with `LAMP_LIVE=1` copies Sources into `.lamp/live` with each `var body: some View` wrapped
(`Template.liveCopySteps`: the body becomes `AnyView` and reads `LampLive.generation`, so its type never changes and
every view draws again on a reload with its state kept), and builds that copy unoptimized, testable, with
`LAMP_LIVE` and `-Xlinker -interposable` (SwiftPM for a Mac app; Xcode for an app for both, from a copy of the
device project, with its debug library off so the code is in the one binary). The copy is made by one
perl pass over each file (`Template.livePerl`: the body wrap, Lamp's entry, the spare places and the `final` below,
with the stretches of strings and comments found once and never touched). It makes every class `final` that nothing
in Sources subclasses (`live.pl scan` lists the names used as superclasses and as the bounds of generic parameters
and `where` clauses, followed through typealiases): a final class keeps no method table, so a method or computed
property added to it goes in, where one added to a class with a table reopens the app; a class made final that
something subclasses after all fails the build in the compiler's words, which `LiveSlots.brokeFinal` reads (unless
the app's own code wrote that class `final`, when the error is the agent's), and the copy is made without the step
from then on (`no-final`). A class's finality and its initializers (which have method descriptors, a final class's
too; one in an extension is a convenience initializer and isn't) are held with the layout (`LiveReload.Group.inits`),
so a subclass added, or an initializer added or changed, reopens the app with its reason rather than being refused
by the runtime after the compile. So is each type's shape (`LiveReload.Group.shape`): struct, class, enum or actor, an
enum's `@objc` and `indirect`, whether the type is generic (itself or declared inside a generic type, with its
parameters, `generic<T>`), a class's superclass (the first name it inherits when
that's one of the app's classes, or a system name the class's initializers show it inherits from: one of them
overriding, the compiler's own included, or a `super` call; a system protocol such as `ObservableObject` is no superclass), and a protocol's requirement
signature (`: AnyObject`, what it inherits, its associated types' constraints), each of which lays values, objects,
method tables or witness tables out differently while the type holds the same fields; a stored reference's `weak`
or `unowned` is part of its field's entry (`Owner<tab>weak helper: Helper?`). A shape is compared only where both
layouts have one, so a layout an earlier Lamp kept says nothing of it. After a build, `Store.install` tries
`reloadInPlace` first, which decides the app is open and built live, takes the verdict and hands the changed files to
`LiveReload.put`, the one pipeline from the layout check to the record of what the app now runs, acting on its
`Outcome` (it went in, with what was done beyond the code; or why the app has to reopen): the change goes in when the app is open, was built live, and the change didn't touch what's read only at launch (the App, its scenes, its menu commands, an application delegate and their extensions, wherever they're written: `SwiftSource.launchEntries`, held to what the open app had as part of the layout; a view or helper beside them goes in like any code; the file of a SwiftData `@Model` class is held whole, since its accessors find its data by key paths a recompiled file makes over again) or Lamp's own files, and leaves every type
holding what it did (`LiveReload.layout`: the compiler's own list of each type's stored properties and cases,
from `-dump-ast` of just the changed files, compared for the open app's sources and the new ones; no reading of the
text; a typealias is printed as itself wherever it's used, so each is listed with what it names and one the open app
has that now names something else reopens, `LiveReload.aliasGroup`; an associated type the compiler inferred, such
as Identifiable's `ID` or a Sequence's `Iterator`, is a typealias it declares itself and is listed the same; a member
returning `some …`, a modifier's `body(content:)` or a style's `makeBody`, whose type is what it builds, is listed by that
type as the compiler prints it where the body's value becomes the opaque one, `LiveReload.opaqueGroup`, so `1` may
become `1.5` only if the member returns a Double now, and `Text("a")` may become `Text("a").bold()`; where that type is
opaque too (a modifier's `some View`) it's listed by a digest of the calls in its body whose results are opaque, each
with the types it was given (`padding [with … Self -> Text]`), which together are the type, so `.bold()` added before
`.padding()` changes nothing and `.font()` after it does: the open app's witness tables and callers were laid out for the type it had, and the
compiler prints both as `some View`; a view's own body, wrapped by the live copy, and a private member are left out; a private type is listed with its file,
`LiveReload.placeGroup`, since its mangled name carries it and one moved to another file is another type at run time,
and keyed with its file throughout the layout and the declarations (`Row@A.swift`, each part of a nested one; `LiveReload.bare`
gives the name back where the code names it, as a field's type or a use in old code does, and `readable` says "Row in
A.swift"), since two files may each declare a private type of one name and the two are two types with their own fields;
every such entry beyond a type's own fields is one of `LiveReload.Group`, which makes and reads them; the printout is
read in one pass, `SwiftSource.walk`, which keeps the scopes and keys every type the one way (nested under its outer
type, a private one with its file, a local one with its function) for every reader of it: the layout (`LiveReload.Members`),
where each property is declared (`SwiftSource.DeclarationsReader`), what's read at launch (`LaunchReader`) and what
old code does (`LiveReload.OldCode`), all taking the same lines in one walk in `LiveReload.analysis`, so a type can't
be keyed two ways by two readers) (`LiveReload.reloadable`, comparing with the sources the
open app runs, kept in `.lamp/live/running`), only the changed files are compiled (as primaries, the rest of the live copy read for context) and
linked into a library. Every file is compiled when what's declared changed (a function, an initializer, a computed
property, a conformance, a member's `@objc` and its selector, a stored property's observers, which turn every write
into a call: `LiveReload.declarationGroup`, `declarationsChanged`), since an unchanged caller may then mean
another one (a new overload, a method where a protocol's default stood in), and a file taken away while another
arrives (one renamed) reopens the app, since what was private to it is named after its file and would start over.
What's compiled is decided before anything is: the changed files are compiled alongside the layout's check, and that
library is the one sent unless something widened it (spares rewriting the copy, what's declared changing, an enum
growing, a constant remade), in which case every file the change needs is compiled once, at the end of `attempt`,
never once per reason. The library is what the app loads when asked with a request signed with its token, only from its
own `.lamp/live` (`LampLive` in LampSupport, under `#if LAMP_LIVE`). It points the app's own calls at the new
functions by rewriting the symbol pointers they go through, and the method tables of the app's classes (their
deinit included) at the changed methods; types, metadata and stored globals are left alone. A library compiled from
a changed file defines that file's types over again, and its code refers to its own copies directly, which no symbol
pointer reaches: a value would then carry one copy's identity or the other's, so `as? Point` fails across the change,
a conformance added in it isn't found, and SwiftUI, seeing a new type for a view's body, remakes the whole subtree
and loses every state in it. So between compiling and linking, `LiveObject` rewrites each object: every type's
metadata, descriptor and protocol descriptor it defines is renamed (`$lampcopy`), and the code's references become
loads through the global offset table of a weak undefined symbol with the original name, which `LampLive` binds to the
app's copy, or to the library's own for a type the app doesn't have (a new one, kept for the changes after it). A
conformance's descriptor and witness table are treated the same, since the runtime tells generic types apart by them
too (`[AnyHashable: …]` keys), which is why a protocol's requirements, their accessors included, are part of the
layout a change is held to (`LiveReload.members`): the app's witness tables must fit. What the library's data names
is worked out before anything is pointed at the new code, so a change refused leaves the app as it was, and written
before too, since each write opens and closes a page of the library for writing, which a thread already running
the new code there would stop at. So is every
stored global's or static's addressor, since the library's own code calls its own copy directly and would otherwise
keep a second copy of the value; through the table the library's accessors reach the app's storage, so they are
code like any other, and a `didSet` added to a static goes in. The mangled type
names and the records of conformances the change adds, which the library's data still holds, are pointed at the app's
descriptors as it loads (`LampLive.redirectDescriptors`, writing through the library's text, which a Mac app without
the hardened runtime may). A class Swift makes as the app runs (a generic class at each type it's used at, a class under
a generic superclass) gets its method table from the app's description of it, which holds the app's code: so the live
copy starts the app through an entry of Lamp's (`__LampEntry`, added by the copy step before the App's own), which
first points the runtime's call that fills such tables in (`swift_initClassMetadata2`, through the same symbol pointer
as any call) at `LampLive.classMade`, which records every class made and points its table at the newest code, and a
change points every table made so far the same way. A witness table (what a call through a protocol goes through) holds a
thunk for each requirement, which calls whichever method answers it, so one compiled when the protocol's own default
answered goes on calling it after the change answers it in the type: the app's tables, and those the runtime makes
(recorded through `swift_getWitnessTable` the same way, `tableMade`; a conformance with no table of its own in the
image, to a system protocol that may change between releases, has its table asked for and recorded at launch and when
a change brings one, `recordTables`, since the first to ask may be a cast rather than a hooked request), are pointed
at the new thunks. A default argument is made by a function of its own, which every caller calls, so it's rebound like any
function. What a class answers to from Objective-C (an override of a system class's method, a selector's target) is in
its method list, not its table, so a kept class takes its copy's methods (`takeMethods`, read off the copy's class data,
since the runtime has never seen the copy), and the change's categories (an extension's `@objc` members, an override in
one): the runtime would attach those to the kept classes as the library loads, before any check, so `LiveObject` renames
their list (`__lamp_catlist`) and `LampLive` attaches them once the change fits (`attach`). What `LampLive` can't make
right it refuses, and the app reopens: a class's method table that changed shape, a class whose methods the change lists
in another order than the app (one added, taken away or moved), since a table made after it would be laid out from the
app's list, or a kept class that answers to something from Objective-C its copy no longer has (`removedMethods`), which
it would go on answering with old code; that last is judged only for a change compiled from every file (`whole`, sent
with the change), which is what a declaration taken away gets, since another leaves what an unchanged file's extension
adds. The
build then waits to be installed until the app closes (`LiveReload.awaitInstall`, which unlike a held build doesn't
keep the agent off the app). The libraries of earlier changes go once a later one is in, and all of them when the
app is installed (`LiveReload.forgetLibraries`): a loaded one stays mapped, and otherwise a long session leaves one
for every change tried. Anything else needs the app reopened, with why in the chat's
details (`LiveReload.Verdict`; what `LampLive` refused, and a change that didn't compile or load, say so there too,
through `LiveReload.send`'s answer), so the rules can be tuned by what happens. The compiler's printout of a big app is tens of megabytes: it's kept whole off the main actor (`Sandbox.output`), each pattern is tried only on the nodes it could match (`SwiftSource.node`), and what's read from it is kept in memory by a digest of the code (`LiveReload.Analyses`), so the same code is never printed twice, the open app's layout after a reopen included. A change refused is refused again at the install after its build without that work, while nothing it was judged on has changed (`LiveReload.put`, `refusalKey`); a refusal by the open app itself is tried again. For a request's change, while the app is open, Lamp doesn't reopen it under the person: the build is held (`Store.awaitReload`, `Runtime.awaitReload`), the app shows a Reload button beside the wand in its title bar (`LampMagic.ReloadButton`, tinted glass in the accent colour whose tint brightens and settles again, shown with a `reloadReady` notification) and the chat a line with one too (`.reload`, under the agent's answer), and a click on either reopens it where it was (`Store.reloadWaiting`; the app asks with `reloadNow`, which puts in only a change Lamp holds). The agent is told the change waits for the person (`reloadNote`) and doesn't look or use the app again in that request. Closing the app installs it too. A look with `reopen` asks the same way while the person has the app open (`Store.asksBeforeReopening`, the one check for both): it puts in what it can as the app runs, then holds the app for Reload and tells the agent so (`askedToReopenNote`). Both show the same Reload button and chat line, nothing of their own. Open App and Undo still reopen it, and so does every change and every look in a new app's first turn, which
nobody is using yet and whose passes the person is watching go in; when the person keeps the app open at its question (unsaved work), the build waits for Reload the same way. A live build reads the app's own files
from its Assets folder rather than its bundle (`LampAssets`), so a new picture goes in live too; the package, the
app's settings and its icon still reopen it. Each request to a live app ends with `Agent.liveNote`, which tells the
agent what goes in without reopening. The note opens by saying the person is watching the app beside the chat and
sees a live change at once and a held one not until Reload, so the agent works in small shown steps. Each look then
tells the agent which way its change went (`ChangeOutcome`): into the open app, waiting for Reload with LiveReload's
reason and, where there's a known shape that would have gone in, that shape (`LiveReload.advice`), or reopened or
opened. The turn's end tallies them in a detail line (`Store.outcomeTally`), which is how often changes go in live.

New stored properties go in live too (`LiveSlots`, in LiveReload.swift). The copy step (`Template.livePerl`) gives
each type of the app's spare room the open app's values already have: every class a few places,
`__lampSpare_<Class>_0`… of `LampSpare?` (named after the class, so a subclass's don't clash with what it inherits;
`@Published` when the header says `ObservableObject`), every view one `@State` box (`__lampState_<View>`, a
`LampStateBox`), and every other struct one place holding any number of properties by name (`__lampSpare_<Struct>`, not optional,
so its own `==` and hash run: they take a property never set as its starting value; saved data leaves it out
through two overloads of the keyed coding containers, which the compiler's Codable code takes over the general ones). A struct's moved properties drop out of the initializer Swift makes for it, which the new code may call with them,
so `LiveSlots.memberwiseInitializers` makes that one again in an extension in the struct's file, from the labels and types
the compiler lists for it (`SwiftSource.Declarations.memberwise`), one for each moved property, so a call passing any
of them is matched by the first it passes and one passing none only by Swift's own. So does a struct whose memberwise
initializer is private, since these extensions go in the type's own file. A view's moved `@State` is no parameter of
the view's initializer any more, and can't be made one (SwiftUI makes the state box lazily, after the initializer
has run, so a value given that way would be lost): a change whose code passes it there reopens the app, saying so. A struct or view declared inside a function can't be extended, so a
property added to one reopens the app with that reason. A class's moved property is a `final` computed one, so a
class something subclasses keeps the method table the open app laid out. The spare itself is a parameter
of that initializer too, with a default, which a call never notices but a reference to the initializer as a value
(`.map(Item.init)`) does, since it matches by the whole signature: when a live build fails on the spares
(`LiveSlots.brokeBuild`), every struct the copy gave a spare has its memberwise initializer written again without
the spare's parameter, in `.lamp/live/Sources/LampMemberwise.swift` (`LiveSlots.addMemberwise`, from a dump of the
plain sources, which the copy step keeps), and the build is tried once more before spares are given up.
Left out is what a spare would break: SwiftData and Core Data models, `Sendable` classes, `Equatable` views (declared
so, or made so in an extension, which the scan reports), a class under a class of the same simple name (whose spare
places would clash), the App
and its scenes, property wrappers, App Intents, OptionSets and RawRepresentable structs (declared so, or made so in an
extension, which the copy step's scan reports), whose `init(rawValue:)` is the memberwise one, and every struct in an
app any of whose own files lays memory out by hand (vertex data; the struct read as bytes may be declared in another;
Lamp's own files always do and are told apart by name, `-own=`). When
the only difference in layout is new stored properties in such types, `LiveSlots.fit` rewrites each one-line
declaration in the live copy into a computed property kept in a spare, found by the compiler's own
source ranges (`SwiftSource.declarations`, from the same `-dump-ast` as the layout), so however it's written (with
attributes on lines above, in a `var a = 1, b = 2` list, in a type written on one line) it's replaced exactly, with
no reading of the text (a view's `$name` becomes a binding to its
box), and the change is compiled again and checked as usual. Being stored, a spare is observed like any property, so
views redraw. A value set is read back as set, nil included: a spare tells "set to nil" from "never set" by holding an entry at
all (`LampSpare.has`, a class's non-nil `LampSpare?`, the state box's stored entry), since a nil boxed as `Any`
doesn't cast back. A class's starting value that isn't a literal (`.now`, a call) is worked out on the first read and kept;
a struct can't keep one from a read, so its new property needs a starting value that comes out the same every time (a
literal (by the compiler's word, however it's spelt: `"a\nb"`, `0xFF`), an empty collection, or one of the app's own
enum's cases, judged again each time the property is put back;
anything else, or a different one later, reopens the app, since the spare compares a value that never set the
property by the starting value it was taken in with); a `@Published` property in a class whose places aren't published (conforming
in an extension) reopens it too. `@State` is read in both forms the compiler has given it: `_name: State<T>`, and
`__name: LazyState<T>` where it is a macro. Cases added at the end of an enum whose cases carry nothing need no
spare: its values keep their size (`LiveSlots.casesAdded`). Only while nothing the app keeps holds it but as itself or
in a plain collection (an array, set or dictionary through any depth): Swift uses the numbers after the last case for `nil` in an optional of it and for other enums'
cases that carry it, which a new case would take over. That's looked for in every stored field, static and global of
the new code (`LiveReload.enumsHeld`), before the change goes in; a property added while the app was open keeps its
value in a spare as any value, under the metadata the app's code had, which the grown enum's own no longer reads
from, so one holding the enum or a carrier reopens the app; and a value type
that carries the enum by value (a struct with a field of it, an enum with a payload of it) is held to the same plain
forms, since its own optional and payload cases borrow the enum's numbers, unless it has a spare of Lamp's, whose
`Any?` gives Swift more; an app that keeps
values of any type reopens instead, since one could hide there: `Any`, `AnyObject` (a value is boxed for it),
`AnyHashable`, a `NavigationPath` or one of Foundation's collections, `any P` for a protocol the app doesn't declare (the standard wrappers conform to those on their own,
so `any Collection` may hold `[Mood?]`), or `any P` for one of the app's own when the enum conforms to P, directly,
in an extension or through a protocol that inherits P, or an extension of a system type does and could wrap it
(`LiveReload.existential`); a model keeping `any Shape` is no reason to reopen for a Mood that is no Shape. When an enum
grew, every file of the app's is compiled again, so no code of the open app's meets a case it never knew (a switch over
it, or printing it, reads past what its metadata describes); code already running keeps the version it started with,
so the sources the open app runs, and those of every change that went in since it opened (`.lamp/live/old-code.txt`,
`LiveReload.recordOldCode`: what an earlier change's code started may still be running), are read for a switch over the
enum, or an interpolation of it, in an escaping closure that outlives a draw (one made outside a view's body or a
member returning a view, or one a body hands to anything but SwiftUI, a Timer's, a dispatch queue's, the app's own, or
sets into a property or gives as a property's value; a Button's action is made again at the next draw), an async
closure or an async function (`LiveReload.enumsMetByOldCode`), and the app reopens when there is one. The enum's metadata stays the change's own rather
than the app's (`LiveReload.compile(keep:)`, renamed `$lampown` so `LampLive` binds every later change to it), since
the app's doesn't know the new cases; and the app's own metadata is pointed at the change's description of the enum
(`LampLive.load`, one pointer), so the app's field records, the runtime's asks (printing, Codable, hashing, a cast)
and code compiled before still read the new cases. A constant made from the enum (`Mood.allCases`) is remade like one
whose text changed (`LiveSlots.constants(naming:)`). What old code may still be doing is read more widely than a
switch or an interpolation: any value of the enum's type, or of a type holding it by value (`LiveReload.holders`),
that running code has in hand reopens the app, since an old frame reads it by the layout it was compiled with (an
optional of it, a comparison, a hash, a cast); a class is no such holder (its field keeps its layout, and old code
reading it is caught as a use of the enum itself), nor a view, whose value lives in SwiftUI's graph, nor a key path
passed as a function (`.map(\.name)`), an escaping closure the compiler makes for that call alone. A generic enum
reopens the app when it grows: the runtime lays its values out for each type it's used at, and there is no one
metadata to point at the change's; a private enum's symbols carry the compiler's discriminator, which
`LiveObject.isKept` allows for. What a grown enum is checked against (the layout with statics and globals, `held`)
and what old code does come from the analyses already made (`Analyses.Entry`), not a further run of the compiler.
A property an explicit `CodingKeys` names stays a field (Codable needs it stored),
so it reopens the app, as does one set in an initializer the type writes itself (`SwiftSource.Declarations.assigned`:
a computed property can't be set before the stored ones are; a convenience initializer sets them after `self.init`
and doesn't count), one with observers, `lazy`, or held weakly or
unowned, or `@ObservationIgnored` (a spare is observed), or a `@Published` one whose `$name` publisher is used, or
one with no starting value, or a struct's whose starting value isn't the same every time; `LiveSlots.fitting` says
which, and the chat's detail carries that reason beside the layout's, with the
copy step's own names said as what they are (`LiveReload.readable`). A view's `$name`, its state's binding, becomes
its box's only within that view's own declaration (`SwiftSource.Declarations.types`), since another view in the
file may have state of the same name. Which property is in which spare
(`.lamp/live/slots.json`) is put back into each fresh copy (they come back as additions, and `LiveSlots.fit` puts
them in the same places) until the app is installed again; a property taken out of the code has its place retired
once the change is in (`LiveSlots.retire`), since the place still holds its value, and its name is sent with the change
for the app to set aside (`LampSpare.retired`: what it left neither reads nor counts in `==` or `hash`), and a name
brought back gets a place of its own (a class's under a new index, a struct's or view's under its key, the type and
name numbered by `Slot.generation`, `LiveSlots.spareKey`); what `fit` planned (the places, the constants remade) is written down only once the change is in
(`LiveSlots.commit`), so a change refused leaves no record of places it never took: the
whole build compiles the plain copy, keeps what it compiled in `.lamp/live/built`, and that's what the open app runs
once it's installed (`LiveReload.markRunning(from:)`). A spare never reaches saved data: `LampSpare` encodes as
nothing, and a computed property isn't encoded. If spares ever keep an app from building, it's built again without
them (`LiveSlots.giveUp`, `.lamp/live/no-spares`), so the agent only sees errors in its own code; the marker, like
`no-final`, counts the whole live builds since and goes after ten (`LiveSlots.expireGiveUps`), so the step is tried
again now and then at the cost of one failed build when it still breaks.

A constant (a static or global `let`) whose value changes would otherwise not change at all: the open app made its
value once and keeps it in storage the new code goes on reading. So each constant's value is part of the kept layout
as a digest (`SwiftSource.constantEntries`, not compared as what a type holds), and one that changed is rewritten in
the live copy into a computed property that makes the new value once and keeps it (`LampConstants`, by name and
value; `LiveSlots.changedConstants`, `rewriteConstant`). The first time a constant is rewritten every file is
compiled again, so every reader goes through it; it stays rewritten until the app is installed again. One that can
hold an object needs the app reopened instead (it waits for Reload, as above), since a second object would split the
app's state: one of the app's own classes, and anything that isn't a plain value of Swift's or SwiftUI's
(`holdsObject`), so a Lamp building block such as `LampAPI.own(…)` or a system class too. A tuple's labels and Lamp's
own spare places in a struct name no type of their own, so they don't count. A constant declared in one list with
others (`let a = 1, b = 2`) isn't rewritten, and the reason says so.

A stored static or global `var` is made once too, the first time it's read, so a new starting value for one can't
show without reopening, and whether it seemed to would depend on whether it had been read: its starting value is
part of the layout as a digest as well (`LiveReload.Group.stored`), and one that changed reopens the app.

**The live cases** (`Tests/LiveCases`, run by `LiveCasesTests`) are the record of which side each kind of change
lands on: every case found by a review round, as an app's sources, one `afterN/` folder per change and `expect.txt`
with the verdicts Lamp gave and what the app printed. The test runs each through Lamp's own pipeline (`verdict`,
`put`, with the library handed to a process built from the case instead of an open app, `LiveReload.deliver`), so
it tries the code as Lamp runs it, not a copy. The process runs alongside: its `reload(n)` waits for the n-th
change, loads the library when it's delivered and answers, which is what `put` commits on, and after a refused
change it's ended, rebuilt from the new code and started again, as Reload does (a `keep-open` file in the case
says the person kept the app open instead, so the next change is judged against the code still running). Each case costs a build and a few compiles, so they run only when
asked (`LAMP_LIVE_CASES=1 swift test --filter LiveCasesTests`, a few minutes with the cases running several at once, or `LAMP_LIVE_CASES=name,name` for some), and
`LAMP_LIVE_CASES_RECORD=1` writes the expectations instead of checking them: after a change to anything above,
run them all, read every difference as a change of behaviour (the first line of each print says what's wanted),
and record only what's meant. A new kind of change gets a case: its sources, its edits, and a print of what the
app should see, with what's wanted in the print's words.

Code already running keeps the version it started with (a closure given to a Timer, a loop in a Task, an observer):
calls go to new code, but a closure already handed out is the old one. `Agent.liveNote` asks for loops and timers
to call a method of the app's each time, so a change to that method goes in.

Where a class's fields are is sometimes worked out at run time (a subclass, or fields after a system type such as
an `@Observable` class's registrar), kept in a global for each field that the app fills in. A library has its own
copies, which nothing fills in, so `LampLive` copies the app's values into each library as it loads
(`takeFieldOffsets`), asking for the class's metadata first when the app hasn't worked it out yet. A field the app
has under no such name (a new class's, or a private one whose code moved to another file, since a private name
carries its file's) is laid out by the library itself, which does it as the app did for the same class.

A file taken away doesn't reopen the app: its code stays in the open app, which the new code no longer calls, and a
type it declared that something still holds shows as that holder changing. A type taken away is therefore no
reason to reopen by itself (`layoutProblem`), but its layout is kept with the open app's until it reopens, so a type
brought back under the same name is held to what it was. Only removing the App's file or Lamp's own reopens. A
removal can change what an unchanged caller means (a deleted method that stood in for a protocol's default), so
every file but Lamp's (the App's included, for what else its file holds) is compiled again and every call goes to
code compiled without it.

A Mac app can also open beside a web page, in Chrome's sidebar (Lamp Dev only, an experiment: Settings →
Experimental, `BrowserBridge.switchKey`; how it fits together is in `experiments/browser-connector/README.md`).
The sidebar is a web page of the app's own (`Assets/Sidebar/`), which the app serves itself on this Mac's own
address (`LampBrowser.startPage` in LampSupport.swift), at a name under `.localhost` and a port of its own
(`Template.sidebarHost`, `sidebarPort`, trying the next few when another program has it), so it works while the app
is open whether Lamp is or not. One extension frames every app's page: it keeps the app's name and consent
line above the frame (the page makes its own offer), gives the page no browser powers, and is the page's only way to the person's tab (a read only
when the page's file declares it, once per click in it). The page asks its app for everything else (`lamp.call`,
with a key Lamp hands the extension, which passes it on only once the page proves it's the app's: the key's
signature over a nonce and the port); the app answers only its own name, only that key, never a request another
site made, and lets only the extension frame the page, whose own policy keeps it talking to the app alone. The page
looks as if Apple made it, not like a web page and not like a copy of the window's own theme: `/lamp.css` is
Apple's system look for a narrow Mac list pane, light and dark (grouped grey ground, rounded groups, inset
separators, SF, parts that rearrange at large text), and an app stands out only through one tint, chosen among
Apple's system colours with `data-tint` (each shade measured to read, `SidebarTintTests`), and its own content.
How a page is built (layout, pictures, every state from reading to a failed save, what to check) is the
`chrome-sidebar` skill, which the builder opens before writing the page. The app serves its own pictures
(`/assets/`, or hands one it keeps with an item to the page as a `data:` URL) and SF Symbols (`/symbols/`, drawn by
the app, used as masks), and the extension draws its strip above the page in the page's colours (`look`, plain
colours only). Apps built before pages still publish a
surface as data (`LampBrowser.start`), which the extension still draws. The app declares where it fits in
`browser.json` (`BrowserCompanions.Declaration`), which Chrome matches without the extension reading the page. The
builder decides from the wish (`Agent.Rules.browserCompanion`) and tries the sidebar with `look_at_app` and
`use_app` given `sidebar` and `page`: Lamp opens the app's page itself, out of sight at the sidebar's width
(`PagePreview`), shows it light, dark and at 200% zoom with the app's window beside it, says what it measured there
(contrast, the system font, small words, pictures and symbols that didn't load, sideways scrolling, words cut off,
parts out of line),
and hands it the page beside it, so every engine tries it the same way; it's the one thing the builder uses in a new app, since it isn't the person's Chrome.
Each Chrome tab has its own sidebar and the app keeps what one tab prepared by its tab (`call.tab`), so what one
page prepared never shows on another; keep that when changing either side. The builder may also give an app a
right-click item (`menu` in browser.json) for what its sidebar does with a page, whatever that is (save it, explain,
summarise or translate it, answer something about it): it opens that app's sidebar, and shows only on pages a fit
names by address, the one thing Chrome can check before its menu opens.
**The one exception to "once per click in it"**: choosing an app's right-click item counts as the person's click in
that app's page. The sidebar tells that page once (`lamp.onMenu`) and lets it read once without a click in it, only
within 15 seconds of the choice, only with the proof the page gave in that sidebar, and only of the page the item was
chosen on (the extension checks the tab's address before reading). A choice the page gets too late (a slow-starting
app) doesn't run, and the sidebar says so and that choosing the item again runs it. Nothing else stands in for a click: not the
toolbar icon, not opening the sidebar, not the page asking on its own. From the item a page may also go straight
through a step it would otherwise stop at for a look first (a save's check, say), since choosing the item already
said what to do; it then shows what it did where it can be changed or undone. Widening this needs the same say-so as
making it.

A build asks the app to quit before it replaces it, and the app's answer decides (`AppQuit`). An app may ask
about unsaved work first: Lamp sends the quit request itself and reads the reply macOS carries back, which is
"cancelled" when the person keeps the app open and doesn't come while the question is still up. Until then Lamp
waits, with the app in front and "Waiting for … to close…" in the chat. Kept open, the app isn't replaced: the
chat says so, the build waits like a held icon (`HeldInstalls`) and goes in when the app closes, and a look tells
the agent that what's on screen isn't its change and `use_app` is refused (`Turn.keptOpen`,
`Runtime.holdsBuild`); a turn asks the app once. Lamp ends an app itself in one case only: it agreed to quit and
is still there. One that doesn't answer may be stuck or in the middle of a long save, and from outside the two
look the same, so Lamp never ends it: a copy that answers Lamp's "still there?" (`LampRuntime` answers on the
main thread, and says it listens by leaving its process id in its runtime folder) is asked that before it is
asked to quit, and when it doesn't answer the chat says so beside a Force Quit button (`UnresponsiveNotice`,
`Store.notResponding`), with what the click costs: anything unsaved in that app. The click is the only thing
that ends it. A build that waits for an app for both
goes in only while Try On points at this Mac. Don't add a time limit after which an app is ended anyway: that
is what lost people's work.

`capabilities.json` at an app's root is where the agent declares what the app needs beyond its code
(`Template.Capabilities`): for an iPhone app the entitlements and background work described above, for a Mac
app what Finder may hand it, `{"opens": ["folder", "png", "public.image"]}` ("folder", "file", extensions,
type identifiers). Each field has its own check and only what passes is used (`Capabilities.checked`),
whoever wrote the file. A new capability is a field there, its check, and where it lands: `apply(to:)` for a
Mac app's Info.plist (called in `Store.deploy`, as `finishSimulatorBundle` does for the simulator's bundle),
`lists` and `entitlementsPlist` for an iPhone app. A shared app carries the file as Lamp read it, checked,
and the copy's is written from what passed the same checks on the way in (`Sharing.Package.capabilities`);
such a file says it is format 4, so an older Lamp asks to be updated instead of dropping it.

`opens` becomes `CFBundleDocumentTypes`, one entry for each kind (macOS ignores a type's extensions once it
names content types), always as an alternative, so an app is offered for a kind of file and never takes it
from the app that opens it by default; a kind nothing else opens (a made-up extension) macOS gives to the
app. Without a declaration macOS hands the app nothing: Finder takes no drop on its
icon and doesn't list it in Open With, and the agent's confined `open -a App file` is refused with -10820.
With one, that command works, and `look_at_app` gives the agent the exact line (`Store.handingHint`): the
installed copy's path, since the copy in build/ or the bundle id starts a second copy beside the one Lamp
opened. `Agent.sandboxNote` says which failures are the sandbox's and not the app's; keep it true when the
profile changes.

### 3D scenes and games

Games have two recipes: `Agent.Rules.game2D` in the prompt (SpriteKit, every kind of app), and the `scene-3d` skill
(RealityKit, Mac apps, offered only on a Mac with macOS 15, where RealityView begins), with the `maps` skill beside it
for a real place built from OpenStreetMap data. A Mac app whose own code
imports RealityKit gets `Sources/LampScene.swift` (`Template.lampSceneSwift`, written by `writeSceneSupport`
beside LampSupport.swift and taken away with the last such import), and its Package.swift and build.sh ask for
macOS 15 (`Template.withScene`). It's Lamp's like LampSupport.swift: protected, left out of versions' diffs and of
shared `.lampapp` files, and part of `BuildStamp`. It holds `LampSceneView` (sky, camera rig, keys, the frame
loop), `LampMesh` (lathe, extrude, sweep, tube and boxes with textures laid on in metres), `LampMaterial`
(materials with their detail drawn in code, no image files), parts that press, turn, slide and are grabbed, and
`LampScene.copies` (instancing), `scene.place` (a prop by name, so a live change to it shows) and `scene.stream` (a big world built a tile at a time around the player, a few milliseconds a frame, so it opens at once). It carries what cost time to find: no sun shadows (with them RealityKit drops
the sunlight on some frames and the whole picture flickers), a camera near plane of 10 cm, and instance batches
split below a few million vertices (a bigger batch isn't drawn, silently).

Props are made in code and checked by eye: `LampSceneView(props:)` names them, and `look_at_app` with `prop`
asks the running app to show one from four sides (`LampPropStudio`, answered in `.lamp/runtime/prop.txt`) for the
agent to compare with a reference picture. `look_at_app` with `motion` works for every Mac app: `LampRuntime`
watches the front window for about two seconds and writes what changed frame to frame (`motion.json`, the two
most different frames beside it), and `Runtime.motion` puts that in words; it's how flicker is caught, which a
single picture hides.

### Widgets

A Mac app can have a desktop widget. The agent writes it in `Widget/` at the app's root (`Agent.Rules.widget`,
Mac only; an iPhone app's widgets are described under "Home screen widgets and Live Activities" below). Swift in that folder (`Template.hasWidget`,
asked before every build) gives the app's Package.swift a second program, built as an extension, and build.sh
puts it in the app as `Contents/PlugIns/<Exe>Widget.appex` with the bundle id `<app's id>.widget`. It is
signed by itself, sandboxed (`Template.widgetEntitlementsPlist`), before the app around it
(`AppSigning.command`): macOS shows no widget that isn't sandboxed, and the app stays unsandboxed. The widget
shares no code with `Sources/` and doesn't get `LampSupport.swift`, only its own small file (below). Nobody but the person can place a widget
(Edit Widgets), and `look_at_app` can't see one. A rebuild in place keeps a placed widget; moving the app,
which renaming it does, removes it.

A shared app (`.lampapp`) carries its widget's code in `Widget/`, never Lamp's own file there. Such a file
says it is format 3 (`Sharing.format(withWidget:)`; one without a widget stays 2), so a Lamp from before
widgets asks to be updated instead of building the app without it. `Sharing.Package.sources` is all the
code in a file, the app's and the widget's: the review reads that list and `Sharing.install` writes from it,
so add nothing to an app's code folders from a shared file by another way. The widget is read whatever
number the file gives itself.

Asking for a widget gives a widget and nothing that looks like an app. When a widget is all that was asked
for, the agent makes the app one scene, `LampWidgetOnly()`, and puts everything in the widget
(`Template.isWidgetOnly`: an app with a widget whose own code is that scene). Such an app has no window, is
kept out of the Dock (`LSUIElement`, written by build.sh), and Lamp never opens it in front of anyone. A
click on its widget opens the app, as macOS does for every widget, and shows nothing: the scene is a menu bar
item that is never put in the menu bar, so SwiftUI has no window to open for the click (a Settings scene
opened an empty Settings window). A link on the widget (`widgetURL`, `Link`) is sent to the app too, not
to the browser, so the app passes it on (`LampWidgetLinks`: it answers the request to open a link itself and
hands the link to whatever opens it, never back to itself); a widget with no link opens nothing. Whether a
widget has a link is the agent's choice, and the rule says nothing about clicks. A
widget that needs something an app must fetch or keep gets a real app, in the menu bar. Either way the chat
has one card (`WidgetCard`, a `.widget` line added at the first install with a widget): how to add the
widget, then "On your desktop". macOS gives Lamp no way to open Edit Widgets or to place a widget, so the
card only says how. It knows the widget is placed because the app it belongs to may ask macOS
(`LampWidgetPlacement` in LampSupport.swift) and leaves the answer in its runtime folder; a widget-only app
is run out of sight for that after a build and when Lamp comes back to the front, and quits by itself. The
agent is told to say two sentences at most and never how to add the widget: that is the card's.

The widget gets the app's data by asking the app (`Template.WidgetSharing` says why, and is the one place
to change it): macOS refuses an app group to a certificate with no team ID, which is how Lamp signs when no team
is chosen, and Lamp doesn't use exceptions to the sandbox. `LampWidget.share(value, as:)` in LampSupport.swift keeps what the app
shares, answers on this Mac's own address at a port worked out from the app's id (`Template.widgetPort`) to
whoever sends the app's widget secret (`Template.widgetToken`), and reloads the widget. `LampWidget.read` in
`Widget/LampWidgetSupport.swift`, a fourth file Lamp owns and rewrites (`Template.writeWidgetSupport`, only
for an app with a widget), asks, and keeps the last answer in the widget's own sandbox for when the app is
closed. So a widget is as fresh as the last time its app ran. The secret never crosses the connection: the
widget signs its question with it and the app signs its answer over the question's nonce, so only the app's
widget is answered and the widget passes over anything else that took the port.

The widget's buttons change the app's data through the app, with one call on each side whatever the signature:
an App Intent in `Widget/` calls `LampWidget.perform(name, payload)`, and the app's `LampWidget.onAction` does
it, shares what changed and the widget is redrawn. How it travels is decided when `Store.deploy` signs the app.
Signed for the person's team, the app and its widget get an app group named `<team>.<bundle id>`
(`Template.macAppGroup`; macOS honours that form from the signature alone, while `group.…` would need a
provisioning profile), in both signatures and both Info.plists (`LampAppGroup`, `Store.setAppGroup`): the widget
writes each action as its own file in the group's folder (whole, under its final name) and posts a Darwin
notification, and the app does them at launch and when nudged, deleting each once its handler has run. Signed with Lamp's certificate, the widget sends the action over the reading
connection, signed with the same secret over the action's id, and the app answers once its handler has run; an
action the app wasn't there to take waits in the widget's own storage and goes with its next read. The app does
each action once, by id, so one sent again after a lost answer isn't done twice, and counts it done only after
its handler has run, so one cut short by a quit is done next time. The widget changes its list of waiting
actions under one lock. The widget's own App Intents
metadata is kept without a team (only the app's is taken out): its buttons run inside the widget.

Lamp never replaces an app on disk while it's running (`HeldInstalls`): macOS then stops taking the running
app for its widget's owner and refuses its redraws until it's reopened. A build quits the app first; a new
icon or its artwork (`Store.installIcon`) waits for the app to close or for the next build. The widget's
own process is ended just before the swap too, and before an app is deleted (`WidgetProcess`, found by its
file inside that app or, for a copy running from elsewhere such as the Trash, by the widget's bundle id):
left alive it no longer matches the widget installed, and macOS fails every reload and leaves the widget
blank until that process happens to exit.

### Home screen widgets and Live Activities

An iPhone app, and the iPhone half of an app for both, gets its widgets the same way: Swift in `Widget/`
(`Template.hasWidget` says yes for every kind; `isWidgetOnly` stays the Mac's) makes a WidgetKit extension
holding home screen widgets and Live Activities (`ActivityConfiguration`) in one `WidgetBundle`. The rule is
`Agent.Rules.iPhoneWidget`, given to the iPhone prompt and, marked for its half, to an app for both's.

- **Building.** In the simulator build the extension is a second SwiftPM product (`iPhonePackageSwift(widget:)`,
  `universalPackageSwift(widget:)`), linked with its own entitlements in its binary like the app's, and wrapped
  by `iPhoneBuildSh(widget:)` as `PlugIns/<Exe>Widget.appex` at the top of the bundle (`XPC!`,
  `com.apple.widgetkit-extension`, a version that changes every build so iOS rereads the widget's kinds),
  signed before the app; `finishSimulatorBundle` signs any `.appex` before the app again. The app's Info.plist
  says `NSSupportsLiveActivities` and names the folder it shares (`LampAppGroup`). On a phone and for an app for
  both, the Xcode project gains an app extension target (`withWidgetTarget`: its folder as a synchronized group,
  an Embed Foundation Extensions phase, automatic signing with the app, `Widget-Info.plist`, `Widget.entitlements`);
  for an app for both the target and its embedding carry `platformFilter = ios`, so the Mac half builds without
  it. A malformed extension doesn't fail the build, it just never shows in the gallery: check there.
- **Shared code.** Swift in `Widget/Shared/` compiles into both targets: Lamp links it into `Sources/` as
  `Sources/WidgetShared` (`linkSharedWidgetCode`, before every build, and only ever a link Lamp made), because
  SwiftPM refuses one file in two targets; Xcode's synchronized group doesn't follow that link, so the project
  gives the app target `Widget/Shared/` as a synchronized group of its own (`withWidgetTarget`). It's where an
  `ActivityAttributes` type goes. In an app for both the Mac half compiles that folder too, and
  `ActivityAttributes` is unavailable on macOS, so the rule says to put it under `#if os(iOS)` and to check the
  Mac half with `swift build --product <app>`.
- **Data.** Unlike the Mac (`Template.WidgetSharing`), iOS lets the app and its extension share an app group,
  `group.<the app's id as signed>` (`appGroup(for:onDevice:)`; the team is in it on a phone): both are signed for
  it, ad hoc in the simulator through the entitlements in their binaries. `LampWidget.share` (in LampSupport,
  under `#if os(iOS)`) writes a JSON file there and reloads the timelines; the widget's `LampWidget.read` comes
  from `lampWidgetSupportIOSSwift`, the iPhone version of Lamp's own file in `Widget/`. The calls are the Mac's,
  so the agent learns one way.
- **Live Activities** are started, updated and ended from the app with ActivityKit; there is no push from a
  server, so the rule says to give timers and progress an end date and let them move by themselves.
- **Looking.** A widget and a Live Activity aren't the app's screen. `use_app` with `key` "home" or "lock" presses
  the viewer's own Home and Lock commands (`Simulator.Driver.pressMenuItem`; lock then wakes the screen, onto the
  lock screen) before the picture. Only the person can add a widget to the home screen; the chat's `WidgetCard`
  says how in iOS words (`WidgetCard.phoneStatus`), and iOS doesn't say whether they did, so it always does.

### Apple Watch

An iPhone app, and the iPhone half of an app for both, can have an Apple Watch app: Swift in `Watch/`
(`Template.hasWatch`, asked before every build) is a SwiftUI watch app, and Swift in `Watch/Complications/`
(`hasComplications`) its complications, a WidgetKit extension inside it. The rule is `Agent.Rules.iPhoneWatch`.

- **Building.** `Template.withWatch` adds the watch's targets to Package.swift (`.watchOS(.v10)`, the
  complications as an extension like the widget, the watch app's target excluding Complications/) and to
  build.sh: the iPhone app is built by product name, so the watch code isn't compiled for iOS, and
  `watchBuildSteps` builds for the watch simulator SDK into `<App>.app/Watch/<Exe>Watch.app` (`WKApplication`,
  `WKCompanionAppBundleIdentifier`, id `<app's id>.watchkitapp`) with `PlugIns/<Exe>WatchComplications.appex`,
  each signed before what holds it, the app group linked into their binaries as for the iPhone app. Without the
  watch SDK the iPhone app builds without it, with a warning. On a phone and for an app for both,
  `withWatchTarget` adds a watchOS app target embedded by an Embed Watch Content phase (`platformFilter = ios`)
  and the complications' extension target embedded in it; Xcode takes synchronized-group exceptions per file, not
  per folder, so the Complications/ files are listed each time the project is written.
- **Data.** `LampWatch` in LampSupport (WatchConnectivity on iOS, calls that do nothing on the Mac) sends
  everything shared as the session's application context and takes the watch's actions (`onAction`, once each
  by id). The watch's half is `lampWatchSupportSwift`, written into both folders (`writeWatchSupport`; the
  complications' copy compiles with `LAMP_COMPLICATION` and only reads): `@LampWatched` and `LampWatch.read` read
  what the watch app kept in the folder it shares with its complications, and `send` goes as a message, which
  wakes the iPhone app, or a transfer when the phone is away. While a complication is on the watch face, each
  change also goes as a complication transfer (`transferCurrentComplicationUserInfo`, about 50 a day), which
  wakes the watch app out of sight: `.lampWatch()` on its WindowGroup takes it (`backgroundTask(.watchConnectivity)`)
  and redraws the complications.
- **Simulator.** After the iPhone app opens, `Store.openWatchApp` installs and opens the watch app on the watch
  simulator paired with that iPhone (`Simulator.pairedWatch`, which pairs a new one when Xcode has a watchOS
  that pairs; `LAMP_PRETEND_MISSING=watch`); with none, one line in the chat says how to add watchOS. The agent
  can't look at or use the watch. A shared `.lampapp` carries `Watch/` (format 6), without Lamp's files there.

### App Intents

An app's actions reach Siri, Shortcuts, Spotlight, the Action button, a widget's buttons and Control Center as
App Intents (`Agent.Rules.intents`, given to every kind of app; the widget parts are in `Rules.widget` and
`Rules.iPhoneWidget`). The system finds them in `Metadata.appintents` inside the bundle, which Xcode writes from
the compiler's record of the code's constant values; a package build writes nothing of the sort, so build.sh does
what Xcode does (`Template.appIntentsSetup`, one for a Mac bundle and one for an iOS one). When some Swift in
`Sources/` or `Widget/` imports AppIntents and Xcode's `appintentsmetadataprocessor` is there, the compiler is
asked for the record (`-emit-const-values`, with the protocols Xcode lists, `Template.appIntentsProtocols`,
written into `.build` by the script), and `intents` runs that processor and then `appintentsnltrainingprocessor`
(Siri's phrases) on each bundle before it's signed: the app (`Contents/Resources` on the Mac, the bundle's top
on iOS) and its widget extension. The record is looked for where SwiftPM's build engine leaves it
(`.build/out/Intermediates.noindex/<package>.build/<configuration>/<target>-p.build`); a build that doesn't
leave it there warns and goes on. The phrase step needs `CFBundleDevelopmentRegion` in Info.plist and only
warns when it fails. With only the Command Line Tools the build warns that the system won't see the intents,
and the rule tells the agent to say so. Xcode's own builds (a phone, the Mac half of an app for both) extract
them by themselves.

macOS runs a Mac app's intents only when the app is signed for an Apple team: signed as Lamp signs by itself
(its own certificate, or ad hoc) the intents are listed in Spotlight and Shortcuts, but the app's connection to
the service that runs them is refused, and running one reports success and does nothing. So when a team is
chosen in Settings → Building and this Mac has its Apple Development certificate (`Devices.signingIdentity`),
`Store.deploy` signs a Mac app with that, from the login keychain where Xcode keeps it
(`AppSigning.command(ownKeychain: false)`), widget first as before; otherwise it takes `Metadata.appintents` out
of the app and its widget and signs with Lamp's certificate. Moving between the two changes the app's signature,
which macOS treats as a new app: its permissions are cleared once and the chat says so (the same path as any
change of certificate). The team's certificate keeps its name through Apple's yearly renewal, which is what the
signature's requirement names, so permissions last as long as with Lamp's own. The agent is told the rule
(`Agent.Rules.macIntents`), and `look_at_app` says why when a Mac app with intents was installed without them
(`Store.intentsHint`, read off the installed copy: no Xcode, no team, or a team whose key wasn't allowed). A team
chosen later brings them back: it's part of such an app's fingerprint, and opening one installed without them
builds it again once a team can sign it (`Store.intentsCanComeBack`). Settings → Building shows the team (`PhoneSigningSection`, "Signing") with an iPhone or
iPad app, which needs one, or when this Mac has a team's certificate; with only Mac apps, None is a choice and
nothing is chosen for the person.

On iPhone, a widget's or Live Activity's button runs its intent in the extension unless the intent is a
`LiveActivityIntent`, which iOS performs in the app, starting it out of sight when it's closed. So the rule puts
such an intent in `Widget/Shared/` and its work under `#if !LAMP_WIDGET`: the extension compiles with
`LAMP_WIDGET` (a `.define` on its package target and `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in the Xcode project),
the app without it, and the work changes the data and calls `LampWidget.share`. `LiveActivityIntent` doesn't
exist on macOS, so in an app for both it goes under `#if os(iOS)`. A Mac widget shares no code with the app, so
its buttons can only change what the widget keeps itself.

### Share extensions and Spotlight

An app takes things in without being opened through a share extension: Swift in `Share/` at the app's root
(`Template.hasShare`), built like the widget on every route and beside it when there's both. The agent writes only
`ShareView` (`struct ShareView: View { let items: [LampShare.Item] … }`, usually just `LampShareSheet(items:)`);
Lamp owns `Share/LampShareSupport.swift` (`Template.writeShareSupport`, one source for both platforms), which holds
`LampShareController`, the principal class the extension's Info.plist names (`shareExtensionPlistLines`: the
`com.apple.share-services` point and what it's offered for), the item loading and the ready-made sheet.
`LampShare.send(items)` writes the share into the app group as a folder of its own (written under a dot name, then
renamed, so the app never reads half of one) and posts a Darwin notification; the app's `LampShare.onReceive` in
LampSupport takes each finished share at launch, when nudged and when it comes to the front, and deletes it once its
handler has run.

- **iPhone**: a third SwiftPM product (`extensionTargets`), its entitlements in its binary
  (`.lamp/share-entitlements.plist`, `simulatorExtensionEntitlementsPlist`), `PlugIns/<Exe>Share.appex` signed before
  the app (`iPhoneShareBuildSteps`); on a phone and for an app for both a target of its own in the Xcode project
  (`withShareTarget`, sharing the widget's Embed Foundation Extensions phase when both exist), iOS only. The app group
  is the widget's (`appGroup(for:onDevice:)`): the app carries it and `LampAppGroup` whenever it has either extension.
- **Mac**: build.sh puts it in `Contents/PlugIns/<Exe>Share.appex`, sandboxed (`macShareEntitlementsPlist`). macOS
  allows the shared folder only to a signature with a team, so `Store.deploy` keeps the extension only when it signs
  the app for the person's team (the folder is `macAppGroup`, set in every Info.plist with `setAppGroup`, and
  `AppSigning.command(share:)` signs it before the app); signed with Lamp's certificate it's taken out, since it
  would take what people share and lose it, and `look_at_app` says why (`Store.shareHint`). macOS keeps a new share
  extension off until the person turns it on (Edit Extensions… in a Share menu), which the rule tells the agent.
- A shared app (`.lampapp`) carries `Share/` without Lamp's file and says it is format 7.

`LampSpotlight.index(id:title:details:keywords:)`, `remove` and `removeAll` keep the app's own things in Core
Spotlight, and `.lampSpotlightOpen { id in … }` on a view hears which one was tapped (SwiftUI's
`onContinueUserActivity` for `CSSearchableItemActionType`, which also gets the tap that launched the app): a view
modifier, since an app has no other place that's told. The rules are `Agent.Rules.share` (as `macShare`,
`iPhoneShare` and `universalShare`) and the Spotlight part of `Rules.sharedBlocks`.

### Services the person already uses

An app reaches the person's account on a service they use (Notion, Linear, Airtable, GitHub, Readwise…) in one of two
ways, or open data that needs no account in a third, and every service an app can connect to is one entry in
`Connectors.all` (Sources/Lamp/Connectors.swift): its
name, what people keep there, how it connects, its API's documentation and a few lines on the calls that matter.
The builder finds them through the `connectors` tool, which lists them and, given one, says how to build on it
(`Connectors.answer`), so the system prompt has one line about connectors however many there are
(`Agent.connectorRules`, which keeps the Mac's own accounts first and `LampComputer` after, and names open data
too, since a wish for the weather or exchange rates isn't about an account). Each entry's
declaration in LampSupport.swift (`LampService.<id>`, `LampAPI.<id>`) is written from the same entry
(`Connectors.fill`, in place of `{{SIGN_IN_SERVICES}}` and `{{TOKEN_SERVICES}}`), so what the builder is told is what
the app has. A service is added only when the person can connect without anyone registering an app first; one that
needs a developer app, a secret key that can spend money, or whose terms forbid an app collecting its tokens (Jira
and Confluence's API tokens) doesn't belong.

**Signing in on the service's page** (`LampService`, `LampServiceButton`; Mac apps only): through the service's own
MCP server. Nobody registers anything beforehand: Connect finds the service's sign-in addresses the way MCP
describes them (the server's 401 names its resource description, which names the authorization server), registers
the app with the service under its own name (dynamic client registration, no secret), and opens the service's page
in the browser with PKCE. Each address is trusted only as far as the document before it vouches for it (`discover`):
the resource description must be on the service's own https origin and name that server, its authorization server
must be https and its description must name itself as `issuer`, and every sign-in address must be on that server's
origin; anything else stops the sign-in before the browser opens. No request of the sign-in follows a redirect, its
description fetches included, so each document comes from the address that was vouched for.
`ServiceSignInTests` runs this against the services' recorded answers and against changed copies of them.
The service sends the person back to this Mac's own address (`127.0.0.1`, a listener open
only while that sign-in waits, which ignores anything that isn't the answer to it), and the app trades the code for
its sign-in. Disconnect forgets the sign-in here and asks the service to end both its keys, writing each answer
(never a key) to the app's log. What a service says when it refuses is cut to one short line before the app shows it
(`brief`). Calls are the
service's own MCP tools (`call`, `tools`); after a sign-in the app writes the tool
list, with no account data, to `.lamp/runtime/services/` for the builder. Not on iPhone yet: a phone can't keep the
listener open while the browser is in front.

**A personal token** (`LampAPI`, `LampAPIButton`; every kind of app): for a service whose own site lets the person make
one. Connect opens a sheet with one sentence on what to do, a link to the service's page and a field for each thing
to paste (the token, and for Harvest the account number); the app asks the service's address for checking a token
before keeping it. Calls are the service's REST API (`get`, `post`, `patch`, …)
with paths relative to its `base`: a path that leads anywhere else (another site, a scheme, above the base) is
refused before anything is sent, and no request follows a redirect, so the token goes only to the service.
A 401 means the token is over and it's forgotten; a 403 is asked of the check address again, since Toggl Track says
403 for a token it doesn't take where others say it of one thing the token may not see. Disconnect forgets the
token here; it still works until the person deletes it on the service. `TokenServiceTests` runs this against each
service's recorded answer to a wrong token. A service that runs on the person's own server (Home Assistant) has
`{server}` in its base and its token page, and an address field on the sheet: what they type is cut to its scheme,
host and port (`LampAPI.server`; with no scheme, http for a home-network name or a number, as such servers come,
https otherwise), kept with the token, and the token goes only there.

**Open data** (`LampAPI` with no fields; Open-Meteo, Open Food Facts, Frankfurter): no account and no key, so no
Connect, no sheet and no button; it is always connected and the app calls it as it opens. It keeps `LampAPI`'s paths
relative to its base, plus a full address under one of its own other hosts (`also`: Open-Meteo answers air quality
and place names elsewhere). Only services free to read without signing up belong here, and their terms (credit,
limits) go in the entry's notes for the builder.

Both kinds are kept by Lamp for the app, not in the app's own Keychain (`LampSecrets` in LampSupport.swift,
`AppSecrets` and `/app/secrets` in Lamp): Lamp's certificate has no Apple team, so macOS ties an item an app makes to
the one build that made it and asks for the login password after every rebuild, while Lamp is the same program from
build to build. Lamp keeps them as it keeps its own keys (the Keychain when it is signed for a team, else a file only
this user can read), each app's under its instance (so an app made later under the same folder name doesn't inherit
them), and forgets them when the app is deleted. The app's token is in its folder, where the agent can read it, so
Lamp answers only the app itself (`PeerProcess.isApp`): the process on the other end of the connection must run from
where Lamp installed the app and pass that installed copy's designated requirement; `AppSecretsTests` runs real
processes against it. Two things keep that check from being passed by a process the builder's shell starts as the
app: every Mac app is built with a `__RESTRICT` segment (buildSh), so dyld ignores `DYLD_INSERT_LIBRARIES` and the like
for it — LiveReload's `dlopen` from inside the app is unaffected — and the agent's sandbox refuses `process-exec` under
the apps folder, since exec needs no read the profile closes. A connection therefore opens only while Lamp is open. On
iPhone `LampSecrets` stays the device's Keychain, which asks nothing, and an app that keeps its own secrets again is
one line (`LampSecrets.store`). Neither kind is ever in the app's folder, so a shared copy arrives disconnected and is
flagged in the review (`Sharing.checklist`). How to build on each is in its doc comment in LampSupport.swift, which the tool's answer
sends the builder to.

**A service that isn't listed** can still be called from the app's own code. When it needs a key, the app declares
it with `LampAPI.own` (its API's address, the page where the key is made, one sentence of steps, how the key is
sent: a header or a query parameter, and a path to check it) and uses `LampAPIButton`, so the person pastes the key
on the same Connect sheet as a listed service's, it is checked, kept in `LampSecrets` under a name of its own
(`own-…`, so it can't stand in for a listed service's token), and sent only to that address. No key field or dialog
of the app's own, and never UserDefaults, LampStore or a Keychain item of the app's own: the first two are the app's
settings and folder, and the last asks for the password after every rebuild. Both `Agent.connectorRules` and the
tool's list (`Connectors.list`, also its answer to a name it doesn't know) say so. Such a service's address must be
https (`httpsOnly`: nothing is sent otherwise), while a listed one's may be the person's own server on plain http.
The review counts `LampAPIButton`, `LampAPI.own` and `LampSecrets.` in the app's code as connecting an account, and
open data alone as going online.

## Naming: Lamp and Lamp

The app is called **Lamp**: that's the name in everything the user reads (the interface, Help, the agent's
words to the user, the "Customize with Lamp" command in generated apps, the bundle and the DMG). **Lamp** is its
code name and stays in code, comments, type names (`LampSupport`, `LampAI`, …) and in everything existing
installs depend on: the bundle ID `dev.lamp.host`, `~/Library/Application Support/Lamp`,
`~/Applications/Lamp Apps`, the `lamp://` scheme, the `.lampapp` extension and the signing certificates.
Renaming any of those needs a migration, not a find-and-replace.

## Interface

Lamp's screens drift as features land: each adds its own explanation, warning or status, and an earlier
tidy-up is undone. Before adding to any of them (Settings, the welcome, the chat and its cards, the build
card), check:

- **Is it a choice, an action, or the fix for one?** Screens are for doing, not explaining. Labels say what
  something does; a note is only for what the person must accept to decide (an install, a permission, a
  cost), in a sentence or two. No footers, captions, or badges summing up what something is used for.
- **Can it be used now?** A control appears once it does something. Until then, its place shows why not
  and the one thing that fixes it (Not Ready, a gray line, a Download or Sign In… button): no menu of
  models that can't run, no field or switch that won't take effect yet. A menu lists only what works now,
  and one with a single option is plain text. Disabled is for a moment's state in a standard control
  (Remove with nothing selected), not for something that needs setting up first.
- **Does it ever contradict itself?** What's shown is what Lamp does: a menu shows the choice actually
  used, even when the saved one can't be. When all is well, say nothing; a problem is one orange mark and
  one gray line with its fix. Never a choice on screen with words under it saying it won't work.
- **Is this its only home?** Show a thing where it's chosen or changed, and from anywhere else link there
  rather than repeat it: repeats drift from what Lamp actually does. An experiment and its settings live in
  Settings → Experimental, under its checkbox; a feature leaving Experimental takes its settings to the tab
  whose job they are.
- **Does structure carry the meaning?** Related things share a group. What depends on something sits
  indented under it and shows only while that's on. Details for the curious (paths, versions) go in `.help`.
- **A card's buttons are one size**: the size Allow and Don't Allow are (`.cardButtons()`), on every card in both
  chats, the main one prominent; never the small size, which in the wand's narrow panel was too slight to find.
  Where they don't fit beside a card's words they go under them (`ChatLook.OfferCard`).
- **Same words for the same thing**, in every screen, Help and errors. Product names come from one place
  (`Engine.title`: "ChatGPT Codex"), never a literal.

### The gallery

Lamp Dev has a gallery (Window → Gallery, ⌥⇧⌘G; `Gallery.swift`): each of the chat's cards in every state it
can be in, drawn from made-up values at the chat's width and the wand panel's, light and dark. A card is drawn by
a view that takes plain values (`AskCardView`), and the view that reads `Store` only finds those
values and passes them in, so the gallery shows exactly what people see. Keep it that way: a new card, a new
state of one (a layout, a shape saved by an earlier Lamp, a button that shows only sometimes) or a fix to how one
lays out gets its entry in `Gallery.entries` in the same change, and is looked at there before the PR. A card
that reads `Store` in its drawing can't be listed: split it first.

### Settings

Each tab has one job: **Building**, how Lamp builds apps; **Apps**, what apps use while they run; **AI
Providers**, what's on this Mac, then cloud providers, with keys, sign-ins and downloads (other tabs' menus
end in "Configure providers…", which leads here); **Memory**, what Lamp remembers and whether it does; **Experimental**, what the Lamp team is still working on, a tab that is there only while there is an experiment to show (`ExperimentalSettings.hasAny`; now Apps in Chrome, in Lamp Dev only).
Lay out with the shared pieces in `Setup.swift`, and extend one rather than lay out by hand:
`SettingsCheckboxes` (on/off is a checkbox, box first, never a switch), `.underCheckbox()`,
`.checkboxNote(…)`, `NotReadyBadge`, `NotReadyRow`, `CapabilityNote` (the gray why-and-fix under Not Ready),
`ImageModelRow`, and `.settingsPane()` at the end of each tab. A PR that adds to Settings says which tab, and why the option needs to exist at all.

### The app's info panel

The info panel (`AppInfoView`, ⓘ in an app's toolbar) shows facts about one app; it chooses nothing. What
belongs: what the app has cost, what answers its AI (from `AppAI.resolve`, so it's what really answers),
how Lamp builds it, and where it lives. What doesn't: menus, switches, explanations, upgrade offers, or
anything that's the same for every app and already in Settings.

- **Read-only.** A thing that can be changed is changed in Settings: each section ends in one small button
  that opens the tab where it's chosen ("Configure Providers…", "Building Settings…"). The only exception is
  undoing what an app was left with by an earlier Lamp ("Use Settings' Choices", shown only when there is
  something to undo).
- **Facts, not notes.** A row is a label and its value. Nothing answers: `NotReadyBadge` as the value, with
  no sentence under it; the fix is in Settings, one button away. No footers or captions.
- **Fit the width.** Rows are `InfoRow`: the value beside its label when it fits, else under it, both
  left-aligned. Keep values short (`AppInfoView.short`), and keep the panel's width (`inspectorColumnWidth`)
  wide enough that most rows fit on one line.
- **Current.** The panel observes whatever its rows read (Settings, keys, the app's own choices, the models
  on this Mac), so a value never outlives what it describes.

## The website

`site/` is lamp.dev (Astro; `site/FIRST_IDEA.md` and `site/BUG_REPORTS.md` cover its moving parts). Its
Download buttons (`DownloadButton.astro` and the menu bar's) are the lamp's bright orange with white words, about
3:1 at their lightest, a faint shadow under the words. That trade-off was weighed and accepted: the brightness is
the point of the button, and the label is large, bold and the same on every page. About 3:1 is the floor for
those buttons, so a change that goes below it is a regression; everything else on the site, links and small
text included, is held to 4.5:1.

## Conventions

- Comments explain why, in plain prose; user-facing text never names files, types or frameworks.
- Files committed to the repo (README, docs, code comments, tests) must never name a person, personal device or hostname, or narrate a particular session or test run; put those details in the PR description.
- Verify in an isolated harness app rather than in the user's apps.
- No attribution lines in commits or PR descriptions.
