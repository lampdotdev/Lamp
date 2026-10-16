Kind: tool, styled like a calm paper planner (warm paper, serif headings, the sun's orange for what's done).

# Today

A home page for the day. One window shows today's date, three priorities to write and check off, a scratchpad
for notes, and "How's the day going?" as five kinds of weather (Rough to Great). Underneath, the last seven days
in a strip: a dot per priority (filled when done) and the day's weather; clicking an earlier day shows what was
on it, read-only. When the last planned day left priorities unfinished and today has room, a banner offers to
carry them over ("1 left from yesterday", Carry Over or Not Now). A desktop widget shows today's priorities and
how many are done, and checks them off from the desktop. Siri and Shortcuts can add a priority ("Add a priority
to Today").

## How the code is organized

- `Sources/App.swift`: the window (default 860×660, minimum 680×620) and the Day menu.
- `Sources/Model/Day.swift`: `Day` (one calendar day: priorities, notes, mood), `Priority`, `Mood` (label and
  weather symbol) and `DayKey`, which turns a date into the day's id ("2026-10-15", local time zone).
- `Sources/Model/TodayModel.swift`: the one shared `@MainActor` model (`TodayModel.shared`). Holds every saved
  day, knows which day is today (`refreshDay()` on midnight and when the app comes forward), and makes every
  change: titles, check-offs, notes, mood, carry-over, Clear Examples. Each change saves the day and shares
  `TodaySummary` with the widget. It also handles the widget's "toggle" action (`LampWidget.onAction`).
- `Sources/Model/SampleDays.swift`: the example week written on first launch.
- `Sources/Model/TodaySummary.swift`: what the widget is given. `Widget/TodaySummary.swift` is the same type
  again (the widget shares no code with the app): change both together.
- `Sources/Views/`: `TodayView` (layout, date header, carry-over banner, toolbar), `PrioritiesSection`,
  `MoodSection`, `NotesSection`, `WeekStrip` (with the read-only day popover), and `Theme` (the paper, sheet
  and sun colors with light and dark versions, the serif `Font.planner`, and `PaperSheet`, the card each
  part sits on).
- `Sources/DayCommands.swift`: the Day menu: ⌘1–⌘3 check off a priority, ⇧⌘C carries over, Clear Examples.
- `Sources/Intents.swift`: the Add Priority App Intent and its Siri phrases.
- `Widget/Widget.swift`: the widget (small: the count and the next thing; medium: every priority with a circle
  that checks it off through the app via the `TogglePriority` intent). It shows "A new day" once the date has
  moved past what the app last shared.

## Data

Everything is in LampStore: the collection "days" holds one `Day` per date that has anything in it, keyed by
`DayKey`. Past days are never changed by the window, only shown. "samplesAdded" records that the examples were
written, so they never come back.

## Sample data and Clear Examples

On the very first launch (no "samplesAdded" flag and no days), `SampleDays` writes the past week: today with
two priorities, notes and a mood, yesterday with one priority left to carry over, and five earlier days. Each
part is marked as an example (`Priority.isExample`, `Day.notesAreExample`, `Day.moodIsExample`); editing a part
clears its mark. Clear Examples (in the toolbar while there are examples, and in the Day menu) removes the
marked parts only, then deletes any day left with nothing in it, so whatever the person wrote stays.

## Easy to change

- Number of priorities: `TodayModel.prioritiesPerDay` (rows, headings, menu shortcuts and the widget follow;
  add prompts for extra rows in `PriorityRow.prompts`).
- Mood scale, words and symbols: `Mood` in `Day.swift`.
- Colors and fonts: `Theme.swift` (and the copy of the colors at the end of `Widget/Widget.swift`).
- How far back the week strip and carry-over look: `TodayModel.daysShown`.
- Something new to track per day (water, steps, a habit): add an optional property to `Day` (old days still
  load), a change method on `TodayModel`, and a `PaperSheet` section in `TodayView`.
- Sample content: `SampleDays.week()`.
