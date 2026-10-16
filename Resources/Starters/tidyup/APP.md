Kind: tool

# Tidy Up

Tidies folders by rules the person can read. The window has a sidebar of folders it looks after (Downloads and
Desktop to begin with; Add Folder… for any other) and, for the selected one, its rules written as sentences whose
choices are menus ("Installers older than 30 days go to the Trash"), then a Preview table of what a tidy would do
to each file (where it goes and why) or the Activity log of past tidies. Tidy Now does what the preview shows;
Undo Last Tidy puts the folder's last tidy back. A folder can also tidy itself, when new files arrive or once a
day at 9:00, while the app is open; that's off until the person turns it on, so a first launch only previews.

Rules for each folder (`FolderRules`), each with a scope (all files or one kind of file):
- Names: keep them, put the date first ("2026-10-15 Name"), or name the file by what's in it.
- Grouping: none, by kind (Screenshots, Images, Documents, Archives, Installers, Music, Movies), or by month
  ("2026-10 October").
- Old files: leave them, or after N days move them to an Archive folder or to the Trash.
- Never touch: extensions (".psd") or words in the name.
- When to tidy: only on Tidy Now, whenever new files arrive, or once a day.

## Safety (keep all of it)

- Only files directly in the folder are looked at. The one exception: the old-files rule also reaches the files in
  the folders Tidy Up groups into (a kind's folder or a month's), or an installer grouped on its first day would
  never be cleared. Nothing else ever looks inside a folder.
- Never touched: hidden files, files still downloading (.download, .crdownload, .part, .partial, .opdownload,
  .tmp), files created or changed in the last minute (`Planner.settleTime`), and anything on the skip list.
- Nothing is overwritten: a taken name gets " 2", " 3"… (`Planner.uniqueURL`, checked again when moving).
- Nothing is deleted: "Trash" is `FileManager.trashItem`, and Undo brings files back from the Trash too.
- Naming by contents only renames names that say nothing (Screenshot…, IMG_…, Untitled, mostly digits:
  `Planner.looksGeneric`), never a name the person chose, and at most 12 files per tidy (`Planner.namingBatch`),
  newest first; the rest wait for a later tidy.

## Code

- `Sources/App.swift`: the window (880×580, at least 720×480), the Tidy menu, the Settings scene.
- `Sources/Model/FolderRules.swift`: the rules and the skip-list check. `WatchedFolder.swift`: a folder, its rules
  and the two starting folders' defaults. `FileKind.swift`: the kinds of file, their folder names and words, and
  how a file's kind is told (extension, type, the screenshot mark).
- `Sources/Model/Planner.swift`: works out a plan (a list of `PlannedChange`: from, to or Trash, why) from a
  folder's rules without touching anything. All the safety rules above live here.
- `Sources/Model/ContentNamer.swift`: names by contents. Text from `LampText.read` (Live Text for screenshots and
  pictures, PDF text, plain text) goes to `LampAI.ask`, which answers `{"name": …}`; a picture with no text is
  shown to the AI instead. Answers are cached by path and modification date in LampStore ("contentNames"). When the
  AI isn't set up or fails, files keep their names and the preview says so quietly, with Try Again.
- `Sources/Model/Mover.swift`: carries out a plan, and undoes a tidy (last move first; folders the tidy made and
  left empty are removed).
- `Sources/Model/TidyModel.swift`: the one model. Folders are saved whole in LampStore under "folders", tidies one
  at a time in the "tidies" collection (`TidyRecord`: each move's from and to). It keeps each folder's plan current
  (`refresh`, also after a `LampFolderWatcher` reports a change), reads names in the background, runs Tidy Now and
  Undo, and does automatic tidies: `LampFolderWatcher` for "whenever new files arrive" (a tidy follows a minute
  after files land, once they've settled) and `LampSchedule.daily("daily-tidy", hour: 9)` for "once a day".
- `Sources/Views/`: `ContentView` (split view, sidebar, selection kept in `@SceneStorage`), `FolderDetailView`
  (rules on top, Preview/Activity below, toolbar), `RulesView` (the sentences; `ChoiceMenu` is a menu inside a
  sentence, `ScopeMenu` the all-files-or-a-kind choice), `PreviewList` (the table; right-click to show a file in
  Finder or leave it alone, which adds it to the skip list), `ActivityList`, `TidyCommands` (the Tidy menu: Tidy
  Now ⌘T, Undo Last Tidy ⌥⌘Z, Add Folder… ⌘O, Clear Examples), `SettingsView` (Open at Login).

Automatic tidies only happen while the app is running: the app doesn't declare background work, so it doesn't
open at login unless the person turns on Open at Login in Settings.

## Sample data

On the very first launch `SampleContent.addIfFirstLaunch()` saves Downloads (grouped by kind, installers older
than 30 days to the Trash) and Desktop (screenshots named by what's in them and grouped by month), both tidying
only on Tidy Now, and one tidy in the Activity log from yesterday morning marked `isExample` (made-up files; it
can't be undone and shows an Example tag). The flag "samplesAdded" makes sure this happens once. Clear Examples
(the Tidy menu, and a button above the log while the example is there) deletes only the records marked
`isExample`; folders and real tidies stay.

## Easy to change

- Kinds of file and their folder names: `FileKind` (add a case, its folder name, words and how it's recognized in
  `FileKind.of`).
- A new rule or choice: a field in `FolderRules`, its sentence in `RulesView`, and what it does in
  `Planner.plan`.
- What counts as still downloading or too recent: `Planner.inProgressExtensions`, `Planner.settleTime`.
- Which names get replaced by content names, and how many per tidy: `Planner.looksGeneric`, `Planner.namingBatch`;
  the AI's instructions: the prompt in `ContentNamer.readName`.
- Month folder names and the date-first format: `Planner.monthFormatter`, `Planner.dayFormatter`.
- The daily tidy's time: `LampSchedule.daily(..., hour: 9)` in `TidyModel.init`, and its words in `RulesView`.
- The starting folders and their rules: `WatchedFolder.downloads` / `.desktop`; a folder added later starts with
  grouping by kind (`TidyModel.add`).
