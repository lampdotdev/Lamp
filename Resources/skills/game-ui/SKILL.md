---
name: game-ui
description: A game's screens and how they feel - picking the screen flow that fits this game (how it opens, teaches, restarts and returns) before drawing any of them, what the shared display and each phone show in each phase, authored art direction, an overworld where one suits, one signature motion, landscape phone controllers, teaching controls in play, and checking the real opening. Read before designing or changing a game's opening, title, menus, level select, HUD, pause or results, whatever the game is made with.
---

# A game's screens

A game's interface should feel made for its world. The failure to avoid is one screen holding everything: the controls,
a stage picker, a join code and the settings, around a small game. Apply this to a new game, or when the person asks
for its screens to change: don't redesign a game they already like on your own.

## A short brief

Before drawing a screen, settle these for yourself, and make each one for this game rather than the first that comes:

- what the players do, and what counts as winning;
- who is holding what, and from how far they look: a shared TV across the room, a Mac at a desk, a phone in the hand;
- three qualities of its world (playful, homemade, a bit chaotic);
- one material or medium the interface is made of (a recipe book, cut paper, a two-ink print, chalk on slate, a tin toy);
- a palette of a few colors, a shape language, and one signature motion (below).

## Pick the flow first

For a new game, or when the person asks to change how its screens go, decide the flow before drawing any screen: how
the game opens, where it teaches, how a restart works and how a player comes back. A title over a backdrop is what comes
first to mind, and few games need it, so ask what the player should do first and what, if anything, has to come before
that. These are examples of a flow, each with when it fits and what it costs:

- **Instant play** (2048): it opens on the game, already playable. One action is named beside its target until it's
  been done, and a new game is one quiet press. It fits a game a glance explains, with nothing to choose. There's no
  moment for mood or choices, so the name stays small and settings wait in pause.
- **Arcade loop** (Asteroids): the name, the game playing itself and the best scores turn over until someone starts, the
  first seconds of play teach, and game over comes back round with the score. It fits short runs and a score to beat.
  The loop has to be worth watching, or it's a title with extra steps.
- **An opening in the fiction** (UNDERRUN): it opens inside the world, on a transmission, a scene or someone talking, and
  play grows out of that, with the name arriving when it's earned. It fits a game with a story or a strong place. It
  costs writing and slows a second visit, so it's short and can be skipped at any moment, and the registered state keeps
  which beat it's on and how far through, so a change or a return goes on from there and a finished one isn't replayed.
- **A briefing** (HexGL): the course, the vehicle and what's at stake, then a countdown. It fits a game where what
  you're about to face changes how you play. It adds a step before every round, so Rematch and Continue go past it.
- **Calm exploring** (Moonpool): it opens in the place, with nothing to fail, the name passing through and the first
  thing worth finding in sight. It teaches by what the player notices, and a return puts them where they left off.
  It fits a game with no pressure. A goal can go unseen, so the world has to point at it.

Another flow is often better: a game played only with phones may open on joining, a board game on its seats. The
path with a title below is one more choice, not the default.

Write the choice in APP.md as a `Flow:` line, so a later change keeps it: a sentence or two on how the game opens, where
it teaches, how a restart and a return go and why that suits this game, never only a name. Leave it where it is when a
change doesn't touch how the screens go.

### What every flow keeps

Leave out the screens the game has no use for:

1. **A title**, where the flow has one: the game's name in a scene or strong emblem, one dominant Play or Continue, and a
   few quieter choices (How to play, Settings). It's the first screen and the main menu at once. No level cards, join
   code or list of controls here: those are later screens.
2. **Joining or setup**: only when the game needs it, and only the choices needed now. Rule tweaks go behind a labeled
   secondary choice.
3. **Level or mode choice**: a screen of its own, when the choice means something. A game with one endless mode goes
   straight to play.
4. **Play**, then **Pause** with Resume first, and **Results** that say what happened before any decoration.

Starting is one action and it visibly changes something: no splash that only asks for a press before the real menu, and
no second confirmation of what the player just chose. A prompt to press something is built from the real bindings (the
game skill says how).

Rematch and quick start keep the session's choices: players, level, mode, and go straight to the round. Settings aren't
a step on the way to play.
Back returns to the previous choice with its state intact, and leaving a lobby, restarting a round and quitting read
as different things. Confirm only what would throw away progress or break up the party.

Each screen has one job. "What is this game?" and "which level?" are two questions, so they're two screens.

### With phones

Before writing a phone's screens, go through each phase of the flow and settle what the shared display shows and what
each player's phone shows, and put that in the `Flow:` line too. The shared display is whatever everyone looks at: the
Mac, a TV, or a phone or iPad running the game. A phone used as a controller, by a phone page or an app of the wish's own
(the phone-controllers skill), is a different thing from a phone running the game, which has only its own screen and
needs no split.

A party quiz might come out like this; another game's will differ:

| Phase | Shared display | Each player's phone |
| --- | --- | --- |
| Joining | the code, who's in | name, then "You're in" |
| Waiting | who's still to come | what the game is waiting for |
| A question | the question, the time left | the answers |
| Results | what happened, the scores | their own result, Again |

- Say who steers a menu everyone can see: the first player, the host, or a vote. All phones moving one marker isn't a
  design.
- Waiting always says for what, on both, and the game never sits silent.
- A phone that drops is named on the shared display, and the flow says whether the game holds or carries on. It comes
  back to the current phase as the same player, never to the start.

## Authored, not defaulted

Certain choices mark a game as made in one sitting, because they're what comes first: pill buttons in a centered stack,
a centered title with its tagline, start prompt and controls underneath, a default rounded font, emoji as art, soft
drop shadows on cards, a teal gradient, a static backdrop with a panel on it.
Any of them can be right, but only when chosen for this game. Two games shouldn't share a composition.

The name is treated live text: set in a face that fits, then given size, spacing, a slant, an outline, a stamp or a
place in the scene. Letters can sit on a sign, follow a path, or be cut out of something. System fonts are a fine
start, and a licensed font may ship in the game's own folder with its credit, but `assets` doesn't fetch fonts. `make_art`
paints no lettering, so never ask it for a logo, and its pictures have their own soft, rounded style: use one where that
suits the medium, and draw the rest in code. A small game needs zero or one new picture.

## Theme in the composition

Theme changes how a screen is built, not only its colors. Choose a small vocabulary and use it on every screen:
background, surfaces, edges, the focus marker, a display type and a reading type, a few icons, and one way of moving
between screens.

- **A cooking game**: the title is an open cookbook, the levels are its tabbed recipes with a picture of each dish, a
  stamped rating marks a finished one, and a page turn carries you between them.
- **A camping party game**: the title is a campsite at dusk, the levels are stops on a trail map joined by a dotted
  path, a pennant marks where you are, and the camera moves along the trail.

The metaphor stays a presentation, never a puzzle: destinations keep ordinary names, and what can be chosen looks
choosable.

Level choices show a preview, a name and progress, with focused, selected, locked and completed each distinct. A lock
says what opens it. Never tell these states or the players apart by color alone: add a shape, label or icon.

Give the title or scene room, and save the strongest accent for what's focused and what matters now.

## A menu that's a place, where it suits

Some games choose their levels in the world instead of on a screen of cards: a small map where a character or vehicle
goes from stop to stop. It suits a game with places to go, and it's one idea among others: a cooking game can use its
recipes, a heist a planning table, and a game of one arena needs none. Don't add one to a small game that asked for
something plainer.

**Worked example: Pond Hop.** A party game of frogs on three ponds. The title is the first pond, close up, and Play lifts
the camera to show all three joined by a trail of lily pads. The frog sits on the pad of the chosen pond. Left and right
hop it to the next pad, the pond's name and best score appear beside it, OK dives in, and Back returns to the title.

What makes it work anywhere:

- The stops are a list of nodes, not a space to steer through: arrows choose, OK enters, Back returns. No analog stick,
  diagonal, timing or gesture is needed to enter a level, so it works with a TV remote, touch and phones.
- A returning player never walks the path again: Continue and Rematch start the chosen level directly.
- Decide who steers it ("With phones", above).
- In a small window the choices stay the same size; the map recomposes rather than shrinks.
- What the registered state keeps is yours to name: the screen, the node and the focus, with the camera registered too,
  restored directly with no intro replayed (the game skill, "Changes while it's played"). The map isn't `busy()`.

## Teaching and input

- Teach by doing: a safe first objective, the action named beside the thing it applies to, then the next action when
  it's needed. A wall of keys before play teaches nothing.
- How to play and the controls stay reachable wherever the game can stop: from pause, and from its title if it has one.
  They show the player's actual bindings (the game skill says how). On a phone, say touch, not keys. Essential help
  never needs hover.
- A menu opens with visible focus on the likely choice, and works with every input the game promises.
- Input belongs to the screen on top: a press in a menu never also moves the player behind it.
- With phones as controllers, the shared screen shows what's public (who's in, whose turn, the score); each phone shows
  its player's current action, and that a choice was received. A join code belongs to the joining screen (the
  phone-pages skill), which a game played only with phones may open on; it's never on a title.
- A phone controller is part of the game, held sideways by default: movement under the left thumb, the main action under
  the right, identity and Back quiet in the middle. Same medium and palette as the game, and buttons named with its verbs
  ("Hop", not "OK"). What isn't usable now looks it, and a press shows only what the game accepted, so a phone with no
  game there says so. A gesture is optional, and always has a tap beside it. The phone-pages skill has the layout.
- Never carry essential information by sound alone.

## Feedback and layout

- Every control answers at once: a focus marker that moves, a press that gives. What's routine stays small, so a win
  can feel bigger. Each response says what happened and how much it mattered, and tuning it in the running game beats
  any fixed timing.
- One signature motion the game repeats (a squash and leap, a page turn, a stamp) gives it more character than many
  effects. Quiet screens are allowed: type and empty space can carry a game, and a results screen needn't explode.
- Quick transitions that a fast press can interrupt, with no queue of animations. A particle never hides a hazard or
  an instruction.
- Keep text readable over anything that moves, with a quiet panel behind it if needed. Try the real strings: long names,
  big scores, the longest button glyph.
- Keep clear of safe areas and thumbs on a phone and of cropped edges on a TV (the tv-design skill and the game's device
  rules have the measurements). A small window recomposes the screen; it doesn't shrink everything.
- Offer reduced motion and mute where there's motion or sound to reduce, and keep meaning without either.

Sound carries the same world as the screens; the game skill says how to make and play it.

## Proof

Play the journey, don't only look at it:

- the whole of the flow, from its opening through a round to how it ends, then a rematch or a return with the choices
  kept;
- pause, help and Back from each place, returning to where they were;
- each input the game supports, and a mix of them where players differ;
- long text, a small window and a wide one;
- mute and reduced motion;
- joining, a failed join and reconnecting, where the game takes phones.

Look at each screen, and at motion with `look_at_app`'s `motion`: one picture proves appearance, not navigation or
sound. Lamp's preview can open a phone page and play it (the phone-pages skill), but a real join is proved only where
phones are really used. When you finish, name any
device or path you didn't run.

## Check the real opening

After your last edit to any screen and before you say a new game is done, or a change to its flow, see what a new
player sees. A look from before that edit doesn't count, so every later edit to a screen means this check again.

On Lamp's web runtime, `look_at_app` with `reopen` gives a fresh preview from the start: a plain look shows where the
person is in an open game, and `use_app` adds to the moves already played, so after playtesting it can land anywhere.
Look before pressing anything. That picture comes about two seconds in, so where the opening changes by itself, follow
it with `use_app` and `wait` before any other move.

A native game, or a page with a loop of its own, has no such preview. There `reopen` opens the app again, and while the
person has it open Lamp asks them to press Reload first, with no picture until they do. Its saved data stays too, so the
picture may be a returning player's. Say which you saw, and when you couldn't see the opening, say so instead of
calling it checked.

Hold it against the `Flow:` line, not against a picture of a title: does everything on screen serve what the player is
doing right now? An instant-play game may name one action beside its target, and a game played only with phones may
open on joining. What fails is anything there because a title usually has it: a list of controls, level cards, a join
code that isn't this screen's job, a tagline and prompt stacked under the name with no reason in your brief. Prompts match
the real bindings, and starting does something the first time.

Then say in a line, by name, what's on that screen that doesn't serve the flow (a rules strip, two cards of controls), or
that nothing does. Fix what you named and run this check again.

## One critique pass

Once the journey plays, look at each screen against your brief once, the phone page included (`use_app` with `phone`, the
phone-pages skill). Name the one thing on it that reads as a template, and fix that, along with anything you saw break.
Then stop polishing; navigation that doesn't work is fixed however many passes it takes. This pass doesn't paint new
pictures, and a wish that asked for something small stays small.
