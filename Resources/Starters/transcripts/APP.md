Kind: tool. Dense and calm: system colors, SF Symbols, a red Record button as the one bold thing.

# Transcripts

Records a meeting, a lecture or a voice memo and transcribes it on this Mac while it's heard (nothing is sent
anywhere to be transcribed). The window has the recordings in a sidebar (title, date, length; searchable by
title and by what was said) and, on the right, either the recorder or the recording selected. The recorder is a
big Record button, a live level meter, the running time and the transcript appearing as it's heard. A finished
recording shows its title (click to rename), a Summary made by the person's own AI through `LampAI` (a few
sentences, decisions, and action items as checkboxes), and the transcript with a time on each line; a click on a
line plays the audio from there. AI is optional: without it the transcript works and the Summary says so quietly.

## How the code is organized

- `Sources/App.swift`: the window (default 880×580, minimum 640×420) and the Recording menu (⌘R start/stop,
  ⇧⌘N show the recorder, Clear Examples).
- `Sources/Model/Recording.swift`: `Recording` (title, date, duration, `lines`, `summary`, `audioFileName`,
  `isExample`, `hasCustomTitle`, `transcriptNote`), `TranscriptLine` (start time and text), `Summary`,
  `ActionItem`, and the `clock`/`spoken` time formats.
- `Sources/Model/Library.swift`: the one shared `@MainActor` model (`Library.shared`). Holds the recordings and
  the selection, makes every change (add, rename, tick an action item, delete with its audio, Clear Examples),
  starts and stops recording, and asks for summaries. Owns the `RecordingSession` and the `Player`.
- `Sources/Model/Summarizer.swift`: the one `LampAI.ask` call, the transcript passed as `data:`, decoded into a
  `Summary` and a suggested title (used only while the person hasn't renamed the recording).
- `Sources/Model/Examples.swift`: the two sample recordings (a team weekly sync and a lecture), text only.
- `Sources/Audio/RecordingSession.swift`: one recording in progress. `AVAudioEngine`'s input goes to an AAC
  file and to the transcriber from the same tap; publishes the level meter, the lines heard and the words
  still being recognized. A transcription failure never stops the recording: it's kept as `transcriptNote`.
- `Sources/Audio/Transcription.swift`: the `Transcriber` protocol, the choice between the two below, and
  `TranscriptCollector`, which gathers lines from whatever thread they arrive on.
- `Sources/Audio/AnalyzerTranscriber.swift`: macOS 26 and later, `SpeechAnalyzer` + `SpeechTranscriber`
  (downloads the language's model once, converts the microphone's audio to the format it wants).
- `Sources/Audio/ClassicTranscriber.swift`: earlier macOS, `SFSpeechRecognizer` with
  `requiresOnDeviceRecognition`, a new request every 50 seconds, lines split at pauses.
- `Sources/Audio/Permissions.swift`: microphone and speech recognition, and the System Settings page to open
  after a refusal. `Sources/Audio/Player.swift`: plays a recording from a time.
- `Sources/Views/`: `ContentView` (split view, the toolbar's Record/Stop with the time), `RecordingList`
  (sidebar, search, delete, Clear Examples button), `RecorderView` (the button, `LevelMeter`, the live
  transcript, permission problems), `RecordingDetail` (title, Play, Copy Transcript, `TranscriptRow`s) and
  `SummarySection`.

## Data

Recordings are the LampStore collection "recordings", one `Recording` each; new properties must be optional so
older recordings keep loading. Audio files are `.m4a` in `LampStore.folder/Recordings/`, named in
`audioFileName`; deleting a recording deletes its file. The selected recording is kept in `@SceneStorage`.

Sample content: `Examples.addOnFirstLaunch` writes two recordings marked `isExample` with no audio (so Play is
hidden and lines aren't clickable) and sets "examplesAdded" in LampStore, so they're written once and never
again. Clear Examples (the Recording menu, and a quiet button at the foot of the sidebar while any example is
left) deletes only recordings with `isExample`.

## Easy to change

- What the summary contains: the prompt and `Draft` in `Summarizer.swift` (add a field to `Summary` as an
  optional, then show it in `SummarySection`).
- Templates for kinds of recordings (a one-on-one, a lecture): a kind on `Recording` and a prompt per kind in
  `Summarizer`.
- How the transcript is split into lines: `ClassicTranscriber.pause` and `wordsPerLine`; with SpeechAnalyzer
  each result is one line (`AnalyzerTranscriber.start`).
- Language: both transcribers use the Mac's language (`Locale.current`).
- The recorder's look: `RecordButton` and `LevelMeter` (bar count is `RecordingSession.meterLength`).
- Sending action items somewhere (Mail, Reminders): from `Summary.actionItems`, with a toolbar button in
  `RecordingDetail`.
