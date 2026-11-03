---
name: game-playtest
description: For a web game at home on the Mac, only when the person asks to play it, test it, check that it works or judge how it looks - playing a round in the preview, seeing the real opening, proving a flow and its screens, and one short critique. Open it then, and do only what was asked. Never for a request that only changes the game.
sections: game#Playtesting; game-ui#Check the real opening; game-ui#Proof; 3d-game#Checking it
---

# Playing and checking the game, when asked

Lamp builds this game and opens it at the end of every turn, and says whether its window drew. Playing it, looking at
it and judging it happen only when the person asks, and only as far as they asked:

- **Play it, test it, check it works:** one `use_app` round as the person would play it: start, steer both ways,
  take a hit, wait out the round to the results, press A to restart. Fix what fails and play that part again.
- **How it looks, or how it fits a smaller window:** one `look_at_app` (with `reopen` for the opening, `shape`
  "960x540" for a smaller window, `motion` for what moves), without playing a round.
- **Check the code:** read it, without opening or playing the game.
- **A critique:** look at the opening, a moment of play and the results in the pictures you already have, against
  what the person asked for. Name at most one thing a player would trip on or that reads as a template, and fix it,
  or say nothing is worth changing. A screen that works isn't restyled for this.

A request to check once doesn't reach later changes: the next change is written and finished as the guide says. The
sections below hold for this game only inside what the person asked; where one says "before you finish", read "when
asked". Say what you didn't try.

{{sections}}
