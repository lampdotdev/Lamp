Kind: companion, in the menu bar.
Look: system colors and SF Symbols, a flame for a game worth watching and a basketball when none is; orange is kept
for the Watch buttons, the flame and the tension bars. Dense scoreboard rows: team, channel and streaming-service logos (fetched on demand), rounded
monospaced scores and times, small league tags, uppercase section labels, hover highlights instead of row lines, and a
win-chance bar in the teams' own colors on good-game cards.

# Buzzer Beater

A menu bar app that watches live games across the major leagues and says when one gets good: close and late,
overtime, a big swing in win probability, an upset against the pregame line or the rankings, a comeback, a big
individual night, a no-hitter. Each good game gets one notification per kind of moment, with a Watch button that
opens it where the person can stream it. Scores come from ESPN's public scoreboard every minute; there's no key
or account.

A click on the icon (a flame and the number of good games, or a basketball) opens a panel:

- **Good games**: a card for each, with its headline ("Oilers up 1 with 6:53 left"), the latest key play, the
  score, the clock and a Watch button.
- **Just ended**: games it showed as good that have finished, with Highlights once ESPN posts the recap.
- **Also live**: every other live game as a row (league, score, clock, a watch button).
- **Coming up**: when nothing is live, the next few games worth a look today and tomorrow, ranked from the
  pregame line, the teams' records, rankings and national TV.

At the foot, Settings, refresh with how long ago it checked, Lamp's wand and Quit. Settings has the leagues (each with its own description of a good game, in
plain words), notifications, where the person lives (for regional channels), the streaming services they have,
alerts only for games they can watch, and Open at Login.

## Code

- `App.swift`: the `LampMenuBar` scene (the panel, the icon with the count) and the Settings scene.
- `PanelView.swift`: the panel: header with refresh and Lamp's wand, good-game cards, Just ended
  cards, the Also live list, Coming up (`UpcomingRow`), Settings and Quit.
- `Scores.swift`: `League` (which leagues there are and which are on at first), `Game` and `Team`, `WatchSettings`
  (LampStore "settings"), and `Watcher`, the one model: it polls ESPN with `LampSchedule`, parses the scoreboard and
  keeps the pregame lines (LampStore "lines").
- `Excitement.swift`: turns a live game into a `Buzz` (a score from 0 to 100, a headline, a key for the kind of
  moment). With win probability, a game near 50/50 late or with a big swing in the last minutes is tense; without
  it (hockey, soccer), the score rules decide.
- `Summaries.swift`: ESPN's game summary per game (`GameDetail`: win probability, the latest key play, the
  highlights clip), fetched for the games that matter, and `FlaggedGame` (LampStore "flagged"): games it showed as
  good, kept so it can offer highlights once they end.
- `Upcoming.swift`: today's and tomorrow's games when nothing is live, and `previewScore`, how they're ranked.
- `Interests.swift`: each league's description of a good game. A league whose description the person changed
  is judged by the AI (`LampAI.decideEach`) against that description instead of the built-in rules, falling back
  to the rules when no AI is set up.
- `Alerts.swift`: notifications (once per game per moment, LampStore "alerts") and which network streams where.
- `Streaming.swift`: the person's services and the channels each carries, the best link for the Watch button,
  and team cities for what's local (LampStore "teamCities").
- `Logos.swift`: `LogoCache` (team logos from ESPN, downloaded once when first shown and kept in LampStore.folder/logos),
  `TeamLogo` (with an abbreviation circle as fallback), `Team.tint` (the team's color), and `NetworkLogos`/`NetworkBadge`
  (channel and streaming logos: each site's icon from Google's icon service, matched by name, fetched on demand).
- `SettingsView.swift`: Settings, in three tabs on the standard gray window background: Leagues (a System
  Settings-style list with league logos and switches; double-click opens a sheet to describe a worthwhile game; + adds
  an any-league moment), Where to Watch (location and services) and General (alerts, Open at Login). Resizable.
- `capabilities.json`: a background app, so alerts come while the panel is closed.

## Data

All in LampStore: `settings`, `lines`, `alerts`, `flagged`, `moments` and `teamCities`. There's no example
content: the games are live, and when there are none the panel says so and shows what's coming up.

## Easy to change

- Which leagues are on at first: `League.defaults`. A league's built-in description: `League.defaultCriteria`.
- What counts as tense, and the headlines: `Excitement.swift`.
- The notification wording: `Alerts.swift` and `Summaries.swift`.
- How often it checks: the schedule in `Watcher`.
- What the panel shows: `PanelView.swift`. The win probability behind each card is `GameDetail.winProbability`.
