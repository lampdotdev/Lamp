# How the agent talks and what the chat shows

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

A capability given to one engine must be given to all of them that can take it, in the same change:

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
  in the chat as a message like any other, which stays one when the turn ends. The chat is one timeline: messages,
  steps and Reload in the order they happened, the newest at the bottom, so steps never collect below what was said
  after them. The Reload line shows while a change waits for it, whether the Mac copy's held build, a game's step held
  whole or in part (its line says what shows after Reload, never "Put into", `Store.stepPage`) or a page's change
  that a copy on another device couldn't take in place (`Transcript`, `Store.awaitsReloadElsewhere`), and pressing it
  puts the change on every place the person has the wish on (`Store.reloadEverywhere`), saying where in one line. A turn's steps since it last said something belong to its one live line (`ChatLook.ActivityLine`,
  `ChatItem.live`, the sidebar's `SidebarState.workingSteps`), which says what it's doing now and changes in place;
  the steps before that stay where they came, between the messages, each stretch of more than one folded to its one
  line as soon as the agent says something after it (`ChatItem.closing`), as it would be when the turn ends. While the turn goes on the line is open, at
  the bottom under its steps, oldest first, so what's going on now is always last (a command by the name
  the agent gave it, any other tool call in the words the line said while it ran, `LogLine.visible`, never its
  files); the step still going is the line itself and joins the list when the agent moves on (`ChatItem.live`). The line
  has no chevron and doesn't fold: its steps get one once they fold, when the agent says something after them. When the turn ends each stretch of steps folds where it came (`ChatItem.items`): the one just
  before the turn's last message into "Worked for…", above that message, any other to how many steps it was, or to
  its one step. Each fold is given a line saying what it did, with how long its steps took
  ("Listed the shelf's saved entries · 12 s", `ChatItem.title(of:untitled:)`), by the small model on the route that
  built the turn (`StepTitles`, `AppAI.fastModel`; a turn built on this Mac is titled by the model on this Mac that
  built it, or not at all, whatever key is saved): a stretch of steps is asked about once, in a call of its own, as soon as
  the agent says something after it (a message, a progress line, a question card: `StepTitles.closed(in:turn:)`) or a
  first build moves on to its next part, so the
  lines are there when the turn ends, and what's left (the steps after the last message, and a stretch whose early call
  failed) in one call after the turn's summary, never waited on. A stretch whose early call is still out then is asked
  for when that call comes to nothing. The call at the end is the last: when it fails, or a title it gives isn't fit to
  show, it's tried once more straight away for the folds still without one, so a fold costs more than one call only
  when one came to nothing, and never one per message. A call through Claude Code or Codex is ended after 90 seconds
  (`StepTitles.timeLimit`), and what went wrong is logged, never the steps or titles. The model is
  told only the request and the steps' words, never a command or what it printed, with which steps failed or never ran
  (`StepTitles.words`); a step's words are what the agent set out to do, so the prompt has it say what was done, not
  that its aim was reached, and say when it failed. A fold keeps its
  words until the line comes, and for good when it doesn't. How long a fold took comes from when Lamp logged its
  lines (`LogLine.at`), so a chat from before that shows no time; "Worked for…" stays the whole run's time, shown
  until its fold is titled. Whatever the agent writes as messages on the way is
  treated the same, each shown as it's said and kept as it was (`LogLine.visible`), since models write such updates
  whether or not they're asked to use the tool: what the person has read never turns into a gray line among the
  steps or goes away. (A Lamp from before this folded them; `ChatLook.ProgressLine` and the status line marked with
  `ChatLook.progressSymbol` are still drawn for a sidebar talking to one.) A change to much of what an app already shows is built in passes
  (`lookRules`: the layout with placeholders, then the parts working, then the detail), each begun with a
  `progress` line and ended with `look_at_app`, which puts it into the open app, so the person watches the app
  take shape rather than waiting for the end; in a new app what's read only at launch is made right in the first pass,
  so later ones go in without reopening it, and in an app the person already has open it goes in the last pass, with
  the other changes that need a reopen. A new app is built in passes too, the window's layout first. A new Mac app's
  scaffold ("Lamp is making this app.") is built and opened as its first turn starts, with the chat beside it
  (`Store.showEarly`, `Store.present`), so the person watches every pass go in; an iPhone app's simulator comes
  forward at the agent's first look. When no chat comes back beside the app after a pass reopens it (the reopen
  failed, it crashed, or the pass made it an app with no window), the chat comes up in Lamp's panel, on its own
  (`MagicPanel.keepChatInSight`, `ChatPanel`). The early build is settled before the turn lets go of the app, however it ends.
  Result cards saved by an earlier Lamp still read and aren't shown (`LogLine.visible`). A new app's first build is drawn as the
  chat's chapters (`Chapters`, `BuildChapters`), not as a card over it: each part of the agent's plan is a heading with
  its tick and how long it took, with what the agent said during it and its steps, folded, under it; the part going
  on has its steps so far and the live line, as any turn has; the parts still to come wait grayed below, with Lamp's
  own last one, building and opening it; and a question card comes where it was asked, in its part. A part's steps are
  its own: a stretch of steps ends where the build moves to the next part, as where something is said, and is titled
  then like any fold (`StepTitles.closed(in:)`), so a part's last steps read what they did, not how many they were. Once the app is made each part folds to one line of its own in the chat (its tick, title and time) that opens to
  what was said and done in it, drawn as any turn is, with the agent's answer under them: the parts are never packed
  inside one fold for the whole build; a build that asked on the way, failed or was stopped stays open. Which
  part a line goes under is decided as it's logged (`TurnProgress.chapter(for:)`) from what Lamp is sure of: the plan,
  the files it lists for each part and the files written. A file listed for a later part moves the build on, and so
  does something said (a message, a progress line, a question, a new plan) once the part it's on is done, to the next part; anything
  else (a read, a command, a look, a fix to an earlier part's file) stays with the part the build is on. The part is
  kept on the line (`LogLine.part`) and the plan's parts on the run's summary (`LogLine.plan`), so the chat reads the
  same after the turn and a relaunch; a line with no part (before the plan came) goes with the line before it, the
  first part at the start. Agent Details shows the lines as they came, with no chapters. Lamp sends the build as
  one line of its own (`SidebarLine.Kind.build`, `SidebarBuild`), worked out from the same segments
  (`SidebarServer.lines`), and the chat draws it (`ChatLook.BuildChapters`), so it reads the same beside a Mac app
  and in Lamp's panel. What each piece
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
  `ChipRow` the same way). A question left to Lamp is "Decide for me" (`TalkCard.youDecide`), except on a question only the person can answer
(`personOnly`: Lamp's device card, `device_permission`). Asking ends the turn: nothing is built or saved
  until the answer, and an agent that goes on to another step after `ask` is ended by Lamp, the way a
  runaway one is (`Store.endIfOver`), whichever engine it is. Once the card is answered the chat
  follows its end again (`ChatFollow.followThroughSettling`). Only the card that waits is drawn as a card: answered, it folds to a line with what was chosen, and a notes receipt is a line too, so one thing in the chat asks for attention at a time. A new piece is a tool there, its view, and a line in `talkRules`. The agent still
  doesn't ask about layout, colors or names (`Agent.Rules.ask`).

When a conversation starts again, Lamp says so in a line of the chat, as any status: "Started a fresh conversation for
<wish>: the last one had grown too large to send" when a request couldn't be sent, and, alone in a cleared chat,
"Started over from the original", or "Started over from the latest original" for a starter's copy brought up to the
starter this Lamp ships (all in `Conversation`; "How big a conversation grows" in the engines guide).

## The chat's one screen

A wish's chat is one screen, drawn the same wherever it is (`ChatScreen`, in Sources/LampSidebarKit): its bar, the chat
or a panel in its place (Versions, Wish Info, Share Link), the message box, every card and line. It's drawn from the
state Lamp makes for the wish (`SidebarState`, made by `SidebarServer.state(for:)`) and hands every click and word back
as a command (`SidebarCommand`, done by `SidebarServer.handle`), through a `ChatLink`: the extension beside a Mac app
talks to Lamp over its socket (`Link`), and Lamp's own panel (`ChatPanel`) calls Lamp directly (`LocalChat`). Nothing
about the chat is decided where it's drawn, so a change to what the chat shows or does is made once, in the state and
the screen, and reaches both. Where the chat is, and how it moves, is in "Generated apps" (beside a Mac app) and below.

The chat is in one place at a time, always beside whatever is showing the wish (`ChatPanel.beside`): a Mac app's own
chat beside its window (the extension, from the first build on); beside the iPhone or iPad simulator, Lamp's Android
emulator, or one of Lamp's own previews (a TV, a device's screen) Lamp's panel, attached to that window and following
it (its own windows as their child; another app's found through Accessibility, by its title, or else the window list,
and looked for again a few times a second); and where nothing on this Mac shows the wish (an app on a TV, an Xbox or the
person's phone, a widget, the menu bar, the background, a wish not made yet or being found, an app that didn't build or
crashed) the same panel on its own: a window of its own size in the middle of the screen, wider than beside a window
(the chat is what's being looked at) and clear of the corner where notifications come, with its width kept apart from
the width beside a window (`ChatPanel.aloneWidth`). A Mac app moved to a TV or another device takes its chat to that
panel as its Mac copy quits, with or without a turn going on (`ChatReturn`). Moving between these (the app opens or quits, a preview
closes) keeps the draft (it's the store's, `Store.updateDraft`) and where the person was reading: each chat says which
line is first in view as the scrolling settles (`SidebarCommand.scrolled`), and a chat drawn again opens there
(`SidebarState.readingAt`). A wish deleted with its chat in Lamp's panel takes the panel with it. The panel's bar has what the chat beside a Mac app has, and for a wish that isn't a Mac
window beside it Play and Stop (`SidebarToolbar.play`) and Try On's one list for every kind (`TryOnMenu`, which looks for devices as it opens, as Lamp's own does, and each
of the wish's other apps in a menu of its own, to use, quit and give a place). A kind not given places one at a time
(an Apple, Android, TV or device app) ends its list with "Add an App for Another Device…" (`TryOnMenu.another`), which
sends that request in the wish's chat and brings the chat forward, so the agent asks which device, as when it's typed. A
wish whose apps are all in folders has it too, after their menus, and on the desk it's that wish's whole Try On. In Lamp's panel a Mac app's chat has Play too, which opens the app with its chat beside it;
and whenever a wish's Mac app opens while its chat is in Lamp's panel (Play, a reopen for a change, the person opening
it), the app is asked to take the chat (`ChatPanel.place`, `MagicPanel.openChat`), and the panel closes once it has.
Chats on their own cascade, a step down and across from one another, so none hides another. Lamp's mark at the start of the bar brings
the desk forward (⌘[).

What only Lamp could hold is handed to it, as Share hands over the file it makes: a setup card's header is in the chat,
with Set Up…, and its keys, downloads and sign-ins, and Image Playground for a hand-drawn icon, are in Lamp's sheet
(`SetupSheet`), over Lamp's panel when the chat is there and in front on its own when it's beside the app. The same goes
for what builds, asked for when a request finds nothing does (`BuilderLine`): the line is in the chat, with a button for
each of Claude Code and Codex that's on this Mac and signed in (`SidebarLine.choices`), which only a click takes since it
spends the person's plan, and the key or sign-in in the sheet (`SetupView`). There, choosing Claude Code or Codex shows how far it has got under
the choice (`EngineUseRow`: its download, what failed with Try Again, its sign-in), and Try Again goes the whole way
through (`EngineUse`); the request stays waiting until that's done. A device's
step opens its setup window, and an iPhone or Android setup line its kind's setup. A new wish's empty chat shows its
intro (`SidebarIntro`, `ChatLook.Intro`: its icon, its name to change, what to do, and ideas that go into the message
box), and Apple's tools installing shows above every chat (`SidebarBanner`). A sidebar built by an earlier Lamp reads
an older shape of the state, and Lamp sends it what it can read (`Connection.push`, by the version it says in `hello`).
