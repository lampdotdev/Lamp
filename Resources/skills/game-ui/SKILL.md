---
name: game-ui
description: A game's screens and how they feel - a title screen that belongs to its world, the flow from title through joining and level choice to play, pause and results, teaching controls in play, menus for a controller, keys, touch or phones, and what to check. Read before designing or changing a game's title, menus, level select, HUD, pause or results, whatever the game is made with.
---

# A game's screens

A game's interface should feel made for its world, one screen at a time. The failure to avoid is one screen holding
everything: the controls, a stage picker, a join code and the settings, around a small game. The game skill holds how
a game is made; this says what its screens are and how they lead from one to the next. Apply it to a new game, or when
the person asks for its screens to change: don't redesign a game they already like on your own.

## A short brief

Before drawing a screen, settle four things for yourself:

- what the players do, and what counts as winning;
- who is holding what, and from how far they look: a shared TV across the room, a Mac at a desk, a phone in the hand;
- three qualities of its world (playful, homemade, a bit chaotic);
- one material or metaphor the interface is made of (a recipe book, a trail map).

## The flow

The usual path, leaving out what the game has no use for:

1. **Title**: the game's name in a scene or strong emblem, one dominant Play or Continue, and a few quieter choices
   (How to play, Settings). It's the first screen and the main menu at once: no extra "press any button". No level
   cards, join code or controls here: those are later screens.
2. **Joining or setup**: only when the game needs it, and only the choices needed now. Rule tweaks go behind a labeled
   secondary choice. A game played only with phones may start here.
3. **Level or mode choice**: a screen of its own after Play, when the choice means something. A game with one endless
   mode goes straight to play.
4. **Play**, then **Pause** with Resume first, and **Results** that say what happened before any decoration.

Rematch and quick start keep the session's choices: players, level, mode. Settings aren't a step on the way to play.
Back returns to the previous choice with its state intact, and leaving a lobby, restarting a round and quitting read
as different things. Confirm only what would throw away progress or break up the party.

Each screen has one job. "What is this game?" and "which level?" are two questions, so they're two screens.

## Theme in the composition

Theme changes how a screen is built, not only its colors. Choose a small vocabulary and use it on every screen:
background, surfaces, edges, the focus marker, a display type and a reading type, a few icons, and one way of moving
between screens.

- **A cooking game**: the title is an open cookbook, the levels are its tabbed recipes with a picture of each dish, a
  stamped rating marks a finished one, and a page turn carries you between them.
- **A camping party game**: the title is a campsite at dusk, the levels are stops on a trail map joined by a dotted
  path, a pennant marks where you are, and the camera moves along the trail.

The same game with a dashboard layout and a themed header would have neither. The metaphor stays a presentation, never
a puzzle: destinations keep ordinary names, and what can be chosen looks choosable.

Level choices show a preview, a name and progress, with focused, selected, locked and completed each distinct. A lock
says what opens it. Never tell these states or the players apart by color alone: add a shape, label or icon.

Give the title or scene room, and save the strongest accent for what's focused and what matters now. Don't box every
element in its own card.

## Teaching and input

- Teach by doing: a safe first objective, the action named beside the thing it applies to, then the next action when
  it's needed. A wall of keys before play teaches nothing.
- How to play and the controls stay reachable from the title and from pause, and show the player's actual bindings
  (the game skill says how). On a phone, say touch, not keys. Essential help never needs hover.
- A menu opens with visible focus on the likely choice, and works with every input the game promises.
- Input belongs to the screen on top: a press in a menu never also moves the player behind it.
- With phones as controllers, the shared screen shows what's public (who's in, whose turn, the score); each phone shows
  its player's current action, and that a choice was received. A join code belongs to the joining screen (the
  phone-pages skill), never on the title. Game controls on a phone are held sideways (the same skill).
- Never carry essential information by sound alone.

## Feedback and layout

- Every control answers at once: a focus marker that moves, a press that gives. What's routine stays small, so a win
  can feel bigger. Each response says what happened and how much it mattered, and tuning it in the running game beats
  any fixed timing.
- Quick transitions that a fast press can interrupt, with no queue of animations under rapid input. A particle never
  hides a hazard or an instruction.
- Keep text readable over anything that moves, with a quiet panel behind it if needed. Try the real strings: long names,
  big scores, the longest button glyph.
- Keep clear of safe areas and thumbs on a phone and of cropped edges on a TV (the tv-design skill and the game's device
  rules have the measurements). A small window recomposes the screen; it doesn't shrink everything.
- Offer reduced motion and mute where there's motion or sound to reduce, and keep meaning without either.

Music and sound carry the same world as the screens: a calm cue for menus, a clear tick for focus, a real flourish for a
win. The game skill says how to make and play them.

## Proof

Play the journey, don't only look at it:

- title to choice to a round to results, then rematch with the choices kept;
- pause, help and Back from each place, returning to where they were;
- each input the game supports, and a mix of them where players differ;
- long text, a small window and a wide one;
- mute and reduced motion;
- joining, a failed join and reconnecting, where the game takes phones.

Look at each screen, and at motion with `look_at_app`'s `motion`: one picture proves appearance, not navigation or
sound. Lamp's preview can open a phone page and play it (the phone-pages skill), but a real join is proved only where
phones are really used. When you finish, name any
device or path you didn't run.
