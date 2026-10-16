Kind: companion

# Focus

A Pomodoro-style focus timer that lives in the menu bar. The icon shows the time left while a session runs
("18:42" beside a timer symbol; a cup during a break, a pause symbol while paused). A click opens a panel with
two pages:

- **Timer**: what this session is for (a text field, with recent ones in a menu beside it), a big ring that
  fills as the phase goes by, Start/Pause and Skip, a line of warm words, and the lengths as small menus.
- **This Week**: sessions per day for the last seven days (Swift Charts) and what the time went to, by intent.

At the foot of the panel: today's finished sessions as dots (grouped by the run toward a long break), and the
Settings and Quit buttons a menu bar app needs. Settings has the lengths, whether breaks start by themselves,
the sound, and Clear Examples.

Focus 25 minutes, short break 5, long break 15 after every 4 sessions in a row (the run starts over each day).
When a phase ends the app plays the "Glass" system sound, and a notification scheduled for that moment says so
(silent, so the sound isn't doubled; it arrives even when the app is closed). The break-over notification has a
Start Focus button, handled in `App.swift`. Skipping a focus session never records it.

## Code

- `App.swift`: the `LampMenuBar` scene (panel + live label), the Settings scene, the Timer menu
  (`FocusCommands`, shown while Settings is in front), and the notification action.
- `FocusTimer.swift`: the one model (`FocusTimer.shared`), an ObservableObject on the main actor. Starting,
  pausing, skipping, finishing a phase, catching up on phases that ended while the app was closed, the
  once-a-second ticker, notifications, Clear Examples.
- `Model/`: `Phase`, `FocusSession` (a finished focus session), `FocusSettings`, `TimerState` (where the timer
  is; a running timer is saved as the moment it ends, so time passes correctly across a quit or a rebuild).
- `SampleSessions.swift`: the example history.
- `Palette.swift`: the two colors, tomato for focus and sage for breaks, with dark-mode versions.
- `Views/`: `MenuBarLabel`, `PanelView` (pages and footer), `TimerView` (intent field, ring, buttons, lengths),
  `FocusRing`, `TodayDots`, `WeekView` (+ `WeekSummary`, the numbers it shows), `SettingsView`.

## Data

All in LampStore: the `sessions` collection (`FocusSession`), and the values `settings` (`FocusSettings`) and
`timer` (`TimerState`). Sessions are loaded into `FocusTimer.sessions`, newest first.

Sample data: on first launch (`FocusSettings.examplesWritten` is false) `SampleSessions.make()` writes twelve
sessions spread over the six days before today, each with `isExample = true`, so This Week has something to show
and today's dots start empty. The flag is then saved, so they are never written again. **Clear Examples** (Timer
menu, Settings, and a link under This Week while any remain) calls `FocusTimer.clearExamples()`, which deletes
only sessions marked `isExample`.

## Easy to change

- Default lengths and the long-break rhythm: `FocusSettings` (and the choices in `LengthsRow` in `TimerView.swift`,
  the ranges in `SettingsView`).
- The end sound: `NSSound(named: "Glass")` in `FocusTimer.finishPhase` (other system sounds: Tink, Hero, Purr…).
- Notification wording: `FocusTimer.scheduleNotification`. The warm words under the ring: `TimerView.encouragement`.
- Colors: `Palette.swift`. The ring's size and thickness: `FocusRing` and `TimerView`.
- What the menu bar shows: `MenuBarLabel`.
- What's recorded per session: `FocusSession` (add optional properties so saved sessions still load) and
  `FocusTimer.finishPhase`.
