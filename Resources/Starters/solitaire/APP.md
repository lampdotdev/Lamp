Kind: game, on green felt with cards drawn entirely in code (no image assets, no art).

# Solitaire

Classic Klondike, laid out as Windows Solitaire had it: the stock and waste top left, four foundations top right,
seven columns below. Cards are dragged (a face-up run moves together), let go on the pile they overlap most that
takes them, or slide back. A double-click sends a card up to its foundation; a click on the stock turns over one
card (or three, in Settings or Game ▸ Draw, from the next deal), and on the empty stock turns the waste back over,
as often as wanted. The card a column's last move uncovers turns face up by itself. Undo (⌘Z, also in the toolbar)
takes back any move, New Game is ⇧⌘N (⌘N stays New Window, which Lamp relies on). The toolbar shows the moves and
a clock that starts with the first move, stops on a win and doesn't run while the app is closed; the chart button
shows statistics (played, won, best time, fewest moves). When nothing is hidden and the stock and waste are empty,
the game finishes itself, a card at a time. A win sets off the bouncing-cards cascade (a click ends it early), then
a result card with New Game.

Rules: the tableau builds down in alternating colors, only a king goes to an empty column, foundations build up by
suit from the ace, and a card can come back down from a foundation onto the tableau.

## Sample content

On first launch a game is already under way: `Board.sample()` deals the same seeded game every time and plays a
few sensible moves into it, with 1:34 on the clock. It isn't counted as played until the person moves a card, and
once saved it's an ordinary game. There's nothing else to clear, so there is no Clear Examples.

## Code

- `App.swift`: the window (900×640 by default, 640×480 at least), the Settings scene and the commands.
- `Card.swift`: `Suit` and `Card` (rank 1 is the ace; the id is the same face up or down so SwiftUI follows a
  card as it moves), and `SeededGenerator` for the sample deal and the felt's texture.
- `Board.swift`: the rules and nothing else. `Pile` names a place; `Board` holds every pile (last card on top),
  `run(from:at:)` (what grabbing a card picks up), `accepts(_:on:)`, `move`, `draw`, finishing, and the sample.
- `Game.swift`: the `@Observable` game the views use: the board, Undo (whole boards kept in `history`), the
  clock, statistics, preferences, auto-finish and the win. Saved with `LampStore`: `game` (the board, the clock,
  whether it's counted), `stats` and `preferences`. Add new properties to these types as optionals so saved
  games keep loading.
- `TableLayout.swift`: where every pile and card goes for a window size; card size follows the window, and a
  long column squeezes its fan to fit.
- `TableView.swift`: draws all 52 cards at their places (moves animate because each card keeps its identity),
  the empty-pile outlines, and the drag, double-click and stock click.
- `CardFace.swift`: `CardView` (either side) and `CardFace`: corner indices, pip layouts for 2 to 10, a large
  suit for aces, a framed letter for court cards. Card colors are the `Color` extension at the top.
- `CardBack.swift`: the card back, a blue lattice drawn with Canvas. Only this file changes for a new back.
- `Felt.swift`: the green table and `PileOutline`, the faint outline of an empty place.
- `WinCascade.swift`: the bouncing cards, stamped into one bitmap each frame so the trails stay.
- `ContentView.swift`: the window's content and toolbar, `WinSummary`, `StatsView` and `Clock`.
- `SettingsView.swift`: Settings (draw one or three) and `GameCommands` (Undo, the Game menu).

## Easy to change

- The card back: `CardBack.swift`. Card faces and their colors: `CardFace.swift`.
- The felt's colors and texture: `Felt.swift`.
- Rules and variants (Spider, FreeCell, Vegas scoring, limited passes through the stock): `Board.swift`, with
  any score kept in `Game` and shown in the toolbar in `ContentView.swift`.
- How the end looks: `WinCascade.swift` (speed, gravity, bounce, how often a card leaves).
- Card size and spacing: the constants at the top of `TableLayout.swift`.
