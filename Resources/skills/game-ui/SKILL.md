---
name: game-ui
description: A game's screens and how they feel - authored art direction, a title that belongs to its world, the flow from title through joining and level choice to play, pause and results, an overworld where one suits, one signature motion, landscape phone controllers, teaching controls in play, and one critique pass. Read before designing or changing a game's title, menus, level select, HUD, pause or results, whatever the game is made with.
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

## Authored, not defaulted

Certain choices mark a game as made in one sitting, because they're what comes first: pill buttons in a centered stack,
a default rounded font, emoji as art, soft drop shadows on cards, a teal gradient, a static backdrop with a panel on it.
Any of them can be right, but only when chosen for this game. Two games shouldn't share a composition.

The name is treated live text: set in a face that fits, then given size, spacing, a slant, an outline, a stamp or a
place in the scene. Letters can sit on a sign, follow a path, or be cut out of something. System fonts are a fine
start, and a licensed font may ship in the game's own folder with its credit, but `assets` doesn't fetch fonts. `make_art`
paints no lettering, so never ask it for a logo, and its pictures have their own soft, rounded style: use one where that
suits the medium, and draw the rest in code. A small game needs zero or one new picture.

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

Rematch and quick start keep the session's choices: players, level, mode, and go straight to the round. Settings aren't
a step on the way to play.
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
- Decide who steers a shared menu: the first player, the host, or a vote. All phones moving one marker isn't a design.
- In a small window the choices stay the same size; the map recomposes rather than shrinks.
- What the registered state keeps is yours to name: the screen, the node and the focus, with the camera registered too,
  restored directly with no intro replayed (the game skill, "Changes while it's played"). The map isn't `busy()`.

## Teaching and input

- Teach by doing: a safe first objective, the action named beside the thing it applies to, then the next action when
  it's needed. A wall of keys before play teaches nothing.
- How to play and the controls stay reachable from the title and from pause, and show the player's actual bindings
  (the game skill says how). On a phone, say touch, not keys. Essential help never needs hover.
- A menu opens with visible focus on the likely choice, and works with every input the game promises.
- Input belongs to the screen on top: a press in a menu never also moves the player behind it.
- With phones as controllers, the shared screen shows what's public (who's in, whose turn, the score); each phone shows
  its player's current action, and that a choice was received. A join code belongs to the joining screen (the
  phone-pages skill), never on the title.
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

## One critique pass

Once the journey plays, look at each screen against your brief once, the phone page included (`use_app` with `phone`, the
phone-pages skill). Name the one thing on it that reads as a template, and fix that, along with anything you saw break. Then stop. This pass doesn't paint
new pictures, and a wish that asked for something small stays small.
