Kind: game, a newspaper crossword printed on newsprint over a gray map of the place it's about (paper and ink, one
yellow for the cursor, Apple's serif for the masthead).

# Local Crossings

A new crossword every day, made from the map of where the person is: its answers are the streets, parks, the
neighborhood and the cafés and restaurants around them ("Late ___ Cafe, café on Langdon St", "___ Street, the main
drag around here"). The grid is freeform: words cross where they share a letter and the squares between are empty,
so the map shows through. The masthead names the place ("The Park Slope Crossword") and counts the person's own
editions (No. 12 is their twelfth). Typing fills the word the cursor is in; arrows move, Tab and Return go to the
next clue, a click on the square the cursor is on turns it the other way, Space does too. Check Puzzle strikes
through wrong letters, Reveal Square and Reveal Word give letters away (marked with a folded corner); either costs
the day its "perfect". When every square is right the clues give way to a card with the time, the streak and the
count of perfect days. The flame in the masthead shows the streak and opens History (the calendar of solved days).

## Where the puzzle comes from

- It's made from where the Mac is: the system asks once, at the first launch (the paper shows the city in the
  Mac's time zone behind the question). Refused, or with Location Services off, the page says how to allow it in
  System Settings or to choose a place, and tries again when the app comes back to the front. Change Place…
  (Puzzle menu) takes a typed town instead, or the person's location again. The choice is `PlaceChoice`, saved as
  "place".
- `Survey.gather` asks Apple's map (MapKit, no key) for places of interest around the spot (food and drink at five
  points 600 m apart, parks and culture within 1.5 km) and reverse-geocodes the same points for street and
  neighborhood names. It takes about half a second. The result is a `Neighborhood`, saved as "neighborhood" and
  used again while the person is within 1.5 km and it's under three weeks old. Apple limits how often the map can be
  asked, so it's never asked more than once a day.
- `Answers.candidates` turns it into candidate answers with clues made only from what the map said, each with a
  tier: 0 anyone living there knows it (the town, the main streets, the big park), 1 the clue gives it away, 2 only a
  regular would know.
- `Layout.make` lays out a freeform grid (at most 13×13, aiming for 12 words) from a fair mix of tiers, trying 200
  arrangements and keeping the fullest, best-knit one. The seed is the day and the place, so it's the same puzzle all
  day. Answers from the last few days are left out while enough remain.
- `Polish` asks the AI the person builds with, once per place and in the background, to pick the best 40 answers and
  reword their clues. A reworded clue that names anything the map didn't say keeps the plain clue. Puzzles after
  that use its picks; today's clues are reworded only if no letter is in yet. Without AI everything still works.
- `Reminder` schedules a notification at 9 each morning that the day's crossword is ready, a week ahead, so they
  keep coming while the app stays closed; each launch and delivery schedules the week again, and solving the day's
  puzzle takes that day's away. The system asks permission the first time.
- `Delivery` does all this and keeps the day's `Edition` (the puzzle, place, number) as "edition", so the paper
  is the same until midnight wherever the Mac goes.

## How the code is organized

- `Sources/App.swift`: the window (hidden title bar, so the paper runs to the edges; default 980×720) and the
  Puzzle menu (Check Puzzle ⇧⌘K, Reveal Square ⇧⌘H, Reveal Word ⌥⇧⌘H, Change Place…, History ⌘Y, Clear Examples).
- `Sources/PuzzleBoard.swift`: the page (map, newsprint wash, masthead), the board (clue bar, grid, clues or the
  done card), the page asking for location (`NeedsLocation`), `PlaceSheet` and the keys.
- `Sources/MapBackdrop.swift`: the gray map behind the paper, a MapKit snapshot about 3.2 km across, muted, no
  points of interest, made once per place, size and appearance.
- `Sources/Look.swift`: `Paper`, the colors (page, ink, faded, square, sun, haze, leaf, wrong; light and dark) and
  type, and `Rule`.
- `Sources/Crossword/`: `Neighborhood.swift` (the place and `Survey`), `Answers.swift`, `Layout.swift` (with
  `Crossword`, `Cell` and `SeededRandom`), `Polish.swift`, `Edition.swift` (`Edition`, `Delivery`),
  `CrosswordGame.swift` (playing: cursor, typing, check, reveal, the finish; progress saved as
  "crossword.progress"), `GridView.swift`, `CluesView.swift` (with `ClueBar`).
- `Sources/Reminder.swift`, `Sources/Game.swift` (`Game`, `Solve`), `Day.swift`, `History.swift` (solves in the LampStore collection "solves",
  the streak), `HistoryView.swift` (with `MonthCalendar`), `DoneCard.swift`, `DailyState.swift`.

## Sample data

On first launch `Samples.swift` writes thirteen solved days from the last two weeks (yesterday back to nine days ago
in a row, so the streak reads 9), marked `isExample`, once. Clear Examples deletes only those.

## Easy to change

- What answers are made of: the categories in `Survey` (`food`, `outdoors`, `culture`) and how far it looks; the
  words never used (`Answers.stock`, `Answers.generic`); the clue wording in `Answers.candidates`.
- When the reminder comes and what it says: `Reminder.hour` and the text in `Reminder.schedule`.
- Puzzle size: `Layout.maxSide` and `Layout.wordsWanted`, and the mix of tiers in `Layout.make`.
- The look: `Paper` in `Look.swift`; how much map shows: the wash's opacity in `PuzzleBoard` and the distance across
  in `MapBackdrop`.
- What the AI is asked: the prompt in `Polish.curate`.
- Adding another daily puzzle: a case in `Game`, a folder beside `Crossword/` with its model and view, its model in
  `DailyState`, a line in `PuzzleBoard`.
