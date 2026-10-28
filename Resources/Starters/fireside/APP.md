Kind: collection
Look: a worn campfire songbook. Grained paper with a coffee ring, taped index cards with painted pictures
(`Assets/`, chosen by `SongArt`), rubber stamps, ticket stubs and guitar picks (`Theme.swift`), and a dark firelit
stage with embers for practice. Another instrument or occasion gets pictures and words of its own.

# Fireside

A guitar songbook for one player who knows a handful of open chords (G, C, D, Em, Am, E, A, Dm) and wants twenty
songs they can play from memory around a campfire. It looks like a songbook carried around for years: grained paper
with a coffee ring, taped index cards with painted pictures, rubber-stamp states, ticket stubs, drawn chord
diagrams, and a dark firelit stage with embers for practice. The tone is friendly and a little dry.

- **Folders with a rule**: each folder is a plain-words rule ("Singable, familiar songs for friends around a
  campfire…") that the AI files and ranks songs by. Three come with it: Campfire, Fingerpicked and sad, and Bedtime
  songs for Mila. A new folder is a name and a rule; every song is judged against it.
- **Home numbers**: Playable Tonight (songs whose chords are all known, and how many are by heart) and Learn Next
  (the one chord that would unlock the most songs, with its diagram). The Twenty, in the sidebar, counts songs
  known by heart, as picks.
- **Adding songs**: drop or paste a link, a PDF, a photo of a tab or text anywhere, share one to the app, or press
  ⌃⌥⌘G with a tab open in Safari, Chrome or Arc. The AI reads title, chords, a one-chord-per-bar sequence, tuning,
  pattern and difficulty (never lyrics), files it into every folder it fits, and says which chords are missing.
- **Practice**: "wait for me" mode shows the next chord, listens through the Mac's input, and moves on when it hears
  it (green right, amber close), with no tempo. Memory mode hides the tab and listens to the whole song; finishing
  it promotes the song to "know it by heart", which the person never sets themselves. Songs go "reading it" → "can
  play it" → "know it by heart".

Chord listening is local (FFT chroma matched against chord templates, tolerant of noise and detuning) and
approximate: it can't tell which string is muted. Settings: the chords in hand, and opt-in reminders.

## Code

- `App.swift`: the window, the Settings scene (`SongbookSettings`: known chords, reminders).
- `ContentView.swift`: the sidebar (`Sidebar`, `TwentyCard`), a folder's header, the ticket stubs (`PlayableTicket`,
  `UnlockTicket`), the song cards (`SongCard`), search, drops and the toolbar.
- `Library.swift`: `Song`, `SongFolder`, `PracticeRecord` and `Library` (the one model: storage, the starting
  folders and songs, playable/unlock counts, the capture shortcut, shares, reminders).
- `Import.swift`: reading a tab with the AI, filing and ranking by folder rules (`LampAI.decideEach`), new folders,
  links and files.
- `SongDetail.swift`: one song: facts, chords, the bar sequence, its journey through the three states.
- `PracticeView.swift`: follow and memory sessions on the firelit stage (`Embers`).
- `Listening.swift` (microphone, the strongest input channel, confirming a held chord) and `ChordDetector.swift`
  (resampling, FFT, chroma, chord scores).
- `ChordDiagram.swift`: the open-chord shapes and their drawn diagrams.
- `Sheets.swift`: new folder, import, and editing a song's arrangement.
- `Theme.swift`: colors, the paper, tape, stamps, picks, and `SongArt` (which painting a song or folder gets).
- `Capture.swift`: the front browser tab's address, by AppleScript.
- `Intents.swift`: a shortcut that opens the songbook.
- `Assets/`: nine painted pictures (campfire, lantern, harmonica, mug, pine, boat, moon, feather, guitar).
- `Share/ShareView.swift`: the share extension's sheet.

## Data

All in LampStore: the `songs`, `folders` and `practice` collections, and the values `known` (chords in hand),
`nudges` (reminders on), `seeded` and `monthly-date`. The three folders are written on the first launch when there
are none; the twelve songs (public-domain folk songs as simple chord studies, no lyrics) once, marked by `seeded`.
A song's `art` is chosen once by the AI among `SongArt.all`.

Reminders, when on: after three sessions, one at the hour the person usually plays (`habit`), and once a month what
they've learned by heart since (`monthly`).

## Easy to change

- The starting chords: `Library.known` and the list in `SongbookSettings`; shapes in `ChordShapes`.
- The starting folders and songs: `Library.init` and `Library.seed`.
- How songs are read and filed: the prompts in `Import.swift`.
- How forgiving listening is: thresholds in `Listening.judge` and `ChordDetector.score`.
- The look: `Theme.swift` (colors, paper, stamps), the pictures in `Assets/` and `SongArt`.
- The goal of twenty: `TwentyCard` and `PickTally`.
