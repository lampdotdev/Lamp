Kind: utility

# Countdowns

Days until the things you're waiting for. The app lives in the menu bar: its icon shows the days to the next
countdown ("12d", or "Today!"), and a click opens a panel listing every countdown soonest first, where they are
added, changed and removed. A desktop widget shows them big: small is the next one on its own color, medium the
next three as colored tiles, large up to six as rows. Each countdown has a name, a day, an SF Symbol and a color
from a small set, and may repeat every year (birthdays, anniversaries). On its day it shows "Today!"; the day after,
a one-time countdown drops off the widget and moves to a collapsed "Past" section in the panel, and a yearly one
rolls over to next year.

## Code

- `Sources/App.swift`: the scene. `LampMenuBar` with the panel and a label (`MenuBarLabel`) that follows the
  store, and a `Settings` scene. The store is a `@StateObject` in the App so the label updates with it.
- `Sources/Countdown.swift`: the model. `Countdown` (Codable, saved in LampStore) and the day sums:
  `nextDay(from:)` (this year's or next year's day for a yearly one; nil once a one-time day is past),
  `daysLeft(from:)`, and the texts for rows and the menu bar. `CountdownColor` is the set of colors, stored by
  name; `CountdownSymbols.all` the symbols offered in the editor.
- `Sources/CountdownStore.swift`: `CountdownStore`, the one source of truth. Loads and saves the countdowns in
  the LampStore collection "countdowns" and the settings (`Prefs`) under "prefs", writes the examples, keeps
  `today` current (midnight, clock or time zone changes, waking from sleep) and hands the widget its data with
  `LampWidget.share(..., as: "countdowns")` after every change.
- `Sources/PanelView.swift`: the panel (fixed 340pt wide). The list, or the editor in its place while one is
  being added or edited (no sheets: they get lost from a menu bar panel). `CountdownRow` and `SymbolBadge`.
  Footer: Clear Examples (only while examples exist), Settings (`LampMenuBar.openSettings()`), Quit.
- `Sources/CountdownEditor.swift`: name, day (graphical calendar), repeats yearly, symbol grid, color row;
  Add/Save on Return, Cancel on Escape, Delete asks first.
- `Sources/SettingsView.swift`: whether the menu bar shows the days, and Clear Examples.
- `Widget/Widget.swift`: the widget's `WidgetCountdown` (the same type the app shares, written again here since
  the widget shares no code with the app, with the same day sums), the timeline (an entry now and at each of
  the next seven midnights, so it counts down with the app closed) and the `@main` widget.
- `Widget/CountdownWidgetViews.swift`: the three sizes. The widget turns the system margins off
  (`contentMarginsDisabled`) and pads itself, so the small size's color reaches its edges.

## Sample data

On the very first launch `CountdownStore.writeExamplesOnce()` adds four countdowns dated from that day (Concert in
18 days, Weekend away in 42, Mum's birthday in 75 and yearly, Half marathon in 110), each marked `isExample`, and
saves the flag "examplesWritten" so they are never written again. Clear Examples (in the panel's footer and in
Settings) deletes only the countdowns marked `isExample`; anything the person added stays, and so does a sample
they changed and saved (`CountdownStore.save` unmarks it).

## Easy to change

- Colors offered: `CountdownColor` in Countdown.swift, and its match by name in `WidgetCountdown.tint` in
  Widget/Widget.swift (both sides must list the same names).
- Symbols offered: `CountdownSymbols.all`.
- How days are counted or worded: `Countdown.daysLeft` / `daysText` / `shortLabel`, and the same sums in
  `WidgetCountdown` plus `DaysNumber` in the widget views.
- What the menu bar shows: `MenuBarLabel` in App.swift.
- How many each widget size shows: `CountdownWidgetView` (`prefix(3)`, `prefix(6)`).
- The look of each widget size: `SmallView`, `MediumView`, `LargeView`.
