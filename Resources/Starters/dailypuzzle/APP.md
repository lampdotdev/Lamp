Kind: game, played on a board of rounded letter tiles (system colors, honey for what changed, green for the goal).

# Daily Puzzle

A new puzzle every day, with a streak. The puzzle is Word Ladder: get from a start word to an end word (COLD to
WARM) changing one letter at a time, each step a real four-letter word. Everyone gets the same puzzle on the same
date; it changes at midnight. The ladder grows down from the start word toward the goal at the bottom: typing
fills the next row (empty slots show the letter they'd keep), Return submits, Delete takes a letter back, and a
word that isn't allowed shakes the row with the reason under it. The changed letter of each step flips in and is
highlighted. Par is the shortest possible ladder; a hint shows the next letter to change along a shortest way,
which costs the day its "perfect". Reaching the goal shows a done card (steps, par, time from the first letter,
streak). The flame in the toolbar shows the streak and opens History: current and longest streak, totals, and a
calendar of solved days (a star for perfect ones). Undo Last Word (⌘Z) takes back a step; Show Hint is ⇧⌘H and
History ⌘Y, in the Puzzle menu.

## How the code is organized

- `Sources/App.swift`: the window (default 600×640, minimum 480×540) and `PuzzleCommands` (Undo Last Word, the
  Puzzle menu with Show Hint, History and Clear Examples).
- `Sources/Game.swift`: `Game`, the list of daily puzzles (only `.wordLadder` so far) with each one's title,
  symbol and one-line rules, and `Solve`, a finished puzzle (game, day, steps, par, seconds, hint used, example).
- `Sources/Day.swift`: `Day`, a calendar date on this Mac ("2026-10-15"), with `number` (days since 2024-01-01 on
  a fixed calendar), which picks each day's puzzle.
- `Sources/History.swift`: every `Solve`, kept in the LampStore collection "solves", and the streak (counted to
  today, or to yesterday while today is unsolved), longest streak and Clear Examples.
- `Sources/DailyState.swift`: what the window and menus share: the history, each game's state, whether History
  is open, and `refreshDay()` (called at midnight and when the app comes forward).
- `Sources/PuzzleBoard.swift`: the window's content and toolbar (Undo, Hint, the streak button).
- `Sources/WordLadder/`: the game. `Words.swift` is the word list (about 1,550 common four-letter words);
  `WordLadder.swift` the rules (the day's pair, `pairs`, word checks, breadth-first `shortestPath`);
  `LadderGame.swift` today's play (steps, typing, hint, refusals, the finish), saved as "ladder.progress" so
  quitting halfway resumes; `LadderView.swift` the board and its key handling.
- `Sources/Tile.swift`: `Palette` (honey, goal green, with light and dark versions), `LetterTile` (its styles and
  the flip) and `Shake`.
- `Sources/DoneCard.swift` and `Sources/HistoryView.swift` (with `MonthCalendar`).

## Sample data

On first launch `Samples.swift` writes thirteen solved days from the last two weeks (yesterday back to nine days
ago in a row, so the streak reads 9, then a missed day and a few more), each the real puzzle of its day and marked
`isExample`. A flag in LampStore ("examplesWritten") makes sure that happens once. Clear Examples, in the Puzzle
menu and at the foot of History while examples remain, deletes only solves marked `isExample`.

## Adding another daily puzzle

1. A case in `Game` with its title, symbol and rules.
2. A folder beside `WordLadder/` with its rules, a model like `LadderGame` (records a `Solve` with that game
   through `History.record` when finished, keeps its progress under its own LampStore name, and has
   `refreshDay()`), and its view.
3. A property for its model in `DailyState` (and a call in its `refreshDay()`), and a line in
   `PuzzleBoard.board`. With two or more games the toolbar shows a picker between them by itself.
The streak and calendar count a day when any of its puzzles was solved.

## Easy to change

- The words: `Words.swift` (add or remove; a pair's par must stay reachable) and the puzzles: `WordLadder.pairs`
  (each pair's shortest ladder is 4–6 steps; the order is the order days take them in).
- Word length: `WordLadder.length`, with a matching word list and pairs (the "Words here have four letters"
  refusal in `LadderGame` names the length).
- Colors and tile look: `Palette` and `LetterTile` in `Tile.swift`.
- What a done card says: `DoneCard.headline`.
- Which puzzle a day gets: `WordLadder.puzzle(for:)`.
