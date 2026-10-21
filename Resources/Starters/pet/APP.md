Kind: companion
Look: a round pink cat. Its figure and face (`PetFigure`, `PetFaceGlyph`), its colours (`PetLook`, also behind the
panel), the food it eats, its accessories, the words in `PetMood` and the cat icon. Another creature gets all of
these.

# Pet

A small creature that lives in the menu bar and is fed by the person's daily habits. Its face in the menu bar
shows its mood; a click opens a panel with the pet drawn large and animated, its name (editable in place), a
fullness gauge, its streak, and today's habits as food. Tapping a habit when it's done feeds the pet one
serving: the food drops into its mouth, it bounces and hearts float up. Right-click a habit to take a serving
back. Fullness falls slowly through the day and the pet wakes up peckish each morning; days where it got at
least three quarters of its food are happy days, and a streak of them earns accessories (a flower at 3 days, a
scarf at 7, a crown at 30) and makes it grow a little. It sleeps at night. An optional reminder (off by
default, in Settings) comes at 3 PM if it has had less than half its food.

It's a menu bar app (`LampMenuBar` with a panel), with a Settings window for the name, the reminder, opening
at login, and editing habits (name, SF Symbol, times per day). Everything is drawn in code: no images.

## Code

- `App.swift`: the menu bar scene with the panel and the face icon (`MenuBarFace`), and the Settings scene.
  The model is handed to each inside its braces, as `LampMenuBar` requires.
- `PetView.swift`: everything about how the pet looks, and nothing else. `PetMood` (happy, content, hungry,
  sleepy, with their words), `PetAccessory` (what a streak earns and when), `PetLook` (colors), `PetView` /
  `PetFigure` (the big animated drawing in a 200-point square; every movement is worked out from the clock
  in a TimelineView, so there's no animation state), `PetFaceGlyph` (the small template face for the menu
  bar) and the shapes.
- `PetModel.swift`: the pet's day. Feeding and taking back, fullness as it falls, mood, streak, the day
  rolling over (yesterday goes into the history), the reminder, and Clear Examples. A 30-second clock keeps
  mood and the day current while the app runs.
- `PetRules.swift`: the numbers that decide how it feels (morning fullness, how fast it gets hungry, what a
  happy day is, bedtime, the reminder's hour).
- `Habit.swift`: `Habit`, `DayResult` (one finished day, for the streak) and `PetState`, everything saved.
- `PanelView.swift`, `HabitRow.swift`: the panel and one habit's row.
- `SettingsView.swift`: the Pet and Habits tabs.
- `SampleData.swift`: the first launch's content.

## Data

One value, `PetState`, saved whole in LampStore under "pet" on every change (`PetModel.state`'s didSet). Add
new properties to it as optionals so saved data keeps loading.

## Sample content and Clear Examples

On the first launch `SampleData.seed` writes four habits (Drink water ×4, Stretch, Read 10 pages, Walk), four
happy days of history before today (so there's a streak and a flower) and one glass of water today. All of it
is marked `isSample`. `PetState.seeded` makes sure it's written only once. Clear Examples (a quiet button at
the foot of the panel, and in Settings → Pet) calls `PetModel.clearExamples`, which removes only the sample
habits, what was eaten of them today and the sample history; habits the person added and the pet's name stay.

## Easy to change

- **A different creature** (a cactus, a fish, a robot): redraw `PetFigure` and `PetFaceGlyph` in
  `PetView.swift` and change the words in `PetMood`; colors are `PetLook`. Keep the moods as the states it
  draws, and nothing else needs to change.
- **What it earns**: `PetAccessory` (the days needed and how each is drawn in `PetFigure`).
- **How fast it gets hungry, bedtime, the reminder's time**: `PetRules`.
- **The starting habits**: `SampleData`. **Symbols offered for a habit**: `Habit.symbolChoices`.
- **Feeding from elsewhere** (finished tasks, closed reminders): call `PetModel.feed(_:)` with a habit.
