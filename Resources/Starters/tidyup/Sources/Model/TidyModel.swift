import AppKit
import SwiftUI

/// Everything Tidy Up knows: the folders and their rules, what each tidy would do now (the preview), and
/// what past tidies did (the activity log). Folders are saved whole in LampStore under "folders"; tidies one
/// at a time in the "tidies" collection.
@MainActor
final class TidyModel: ObservableObject {
    static let shared = TidyModel()

    @Published var folders: [WatchedFolder] {
        didSet {
            LampStore.save(folders, to: "folders")
            if folders.map(\.id) != oldValue.map(\.id) { watchFolders() }
            for folder in folders where oldValue.first(where: { $0.id == folder.id }) != folder { refresh(folder.id) }
        }
    }
    @Published private(set) var plans: [UUID: Planner.Plan] = [:]
    /// Folders whose files are being named by their contents right now.
    @Published private(set) var naming: Set<UUID> = []
    @Published private(set) var records: [TidyRecord] = []
    /// The AI couldn't name files (not set up, or it failed); they keep their names.
    @Published private(set) var namingUnavailable = false
    /// What the last tidy or undo did, shown briefly under the toolbar.
    @Published var notice: String?

    private let log = LampStore.collection("tidies", of: TidyRecord.self)
    private var watchers: [UUID: LampFolderWatcher] = [:]
    private var refreshes: [UUID: Task<Void, Never>] = [:]
    private var autoTidies: [UUID: Task<Void, Never>] = [:]
    private var daily: LampSchedule?

    private init() {
        SampleContent.addIfFirstLaunch()
        folders = LampStore.load([WatchedFolder].self, from: "folders") ?? []
        records = log.all(orderBy: "date", descending: true, limit: 200)
        // Reading Downloads or Desktop the first time makes macOS ask, and the read waits for the answer: done
        // once the window is up, so the window is there behind the question rather than missing until it's answered.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            watchFolders()
            folders.forEach { refresh($0.id) }
        }
        // Folders set to tidy once a day are tidied at 9:00, or on the next launch or wake after it.
        daily = LampSchedule.daily("daily-tidy", hour: 9) { [weak self] in await self?.tidyDailyFolders() }
    }

    func folder(_ id: UUID?) -> WatchedFolder? { folders.first { $0.id == id } }

    func records(for folder: WatchedFolder) -> [TidyRecord] { records.filter { $0.folderPath == folder.path } }

    /// The tidy Undo would take back in this folder: its latest one, unless it was already undone.
    func undoable(in folder: WatchedFolder) -> TidyRecord? {
        records(for: folder).first { !$0.isExample && !$0.undone && !$0.moves.isEmpty }
    }

    /// Whether Tidy Now has anything to do: some file in the preview is ready to move.
    func canTidy(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return plans[id]?.changes.contains { !$0.waitingForName } ?? false
    }

    var hasExamples: Bool { records.contains(where: \.isExample) }

    // MARK: Preview

    /// Works out the folder's preview again, then reads names for files that are to be named by their contents.
    func refresh(_ id: UUID) {
        guard let folder = folder(id) else { return }
        let namer = ContentNamer.shared
        let plan = Planner.plan(folder, contentName: namer.name(of:), canName: !namer.unavailable)
        plans[id] = plan
        guard !plan.unnamed.isEmpty, !naming.contains(id) else { return }
        naming.insert(id)
        Task {
            await namer.readNames(of: plan.unnamed)
            naming.remove(id)
            namingUnavailable = namer.unavailable
            refresh(id)
        }
    }

    /// After the AI failed: ask it again.
    func retryNaming() {
        ContentNamer.shared.resetAvailability()
        namingUnavailable = false
        folders.forEach { refresh($0.id) }
    }

    // MARK: Tidying

    /// Does what the preview shows.
    func tidyNow(_ id: UUID) {
        guard let folder = folder(id), let plan = plans[id] else { return }
        let moves = Mover.apply(plan.changes, rules: folder.rules)
        record(moves, in: folder, automatic: false)
        refresh(id)
    }

    /// Tidies without anyone watching: waits for names to be read first, so the result is what a preview
    /// would have shown.
    func tidyAutomatically(_ id: UUID) async {
        guard let folder = folder(id), folder.rules.auto != .off else { return }
        let namer = ContentNamer.shared
        var plan = Planner.plan(folder, contentName: namer.name(of:), canName: !namer.unavailable)
        if !plan.unnamed.isEmpty {
            await namer.readNames(of: plan.unnamed)
            plan = Planner.plan(folder, contentName: namer.name(of:), canName: false)
        }
        let moves = Mover.apply(plan.changes, rules: folder.rules)
        record(moves, in: folder, automatic: true)
        refresh(id)
    }

    private func tidyDailyFolders() async {
        for folder in folders where folder.rules.auto == .daily {
            await tidyAutomatically(folder.id)
        }
    }

    private func record(_ moves: [TidyRecord.Move], in folder: WatchedFolder, automatic: Bool) {
        guard !moves.isEmpty else {
            if !automatic { notice = "Nothing to move." }
            return
        }
        let record = TidyRecord(folderPath: folder.path, moves: moves, automatic: automatic)
        log.put(record)
        records.insert(record, at: 0)
        if !automatic { notice = moves.count == 1 ? "Moved 1 file." : "Moved \(moves.count) files." }
    }

    func undoLastTidy(in id: UUID) {
        guard let folder = folder(id), var record = undoable(in: folder) else { return }
        let restored = Mover.undo(record)
        record.undone = true
        log.put(record)
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        notice = restored == 1 ? "Put 1 file back." : "Put \(restored) files back."
        refresh(id)
    }

    // MARK: Folders

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Tidy This Folder"
        panel.message = "Choose a folder for Tidy Up to look after. Nothing moves until you say so."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(url)
    }

    @discardableResult func add(_ url: URL) -> UUID {
        if let existing = folders.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { return existing.id }
        var folder = WatchedFolder(path: url.path)
        folder.rules.group = GroupRule(mode: .byKind)
        folders.append(folder)
        return folder.id
    }

    /// Stops looking after a folder. Its files stay exactly where they are.
    func remove(_ id: UUID) {
        folders.removeAll { $0.id == id }
        plans[id] = nil
    }

    func skip(_ change: PlannedChange, in id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].rules.skip.append(change.source.lastPathComponent)
    }

    func clearExamples() {
        for record in records where record.isExample { log.delete(record.id) }
        records.removeAll(where: \.isExample)
    }

    // MARK: Watching

    /// Watches every folder: a change redraws its preview, and in a folder set to tidy when files arrive, a
    /// tidy follows once the new files have settled (Planner.settleTime), since a file still being written is
    /// never moved.
    private func watchFolders() {
        watchers = Dictionary(uniqueKeysWithValues: folders.map { folder in
            let id = folder.id
            return (id, LampFolderWatcher(folder.url, latency: 1) { [weak self] changed in
                MainActor.assumeIsolated { self?.folderChanged(id, changed) }
            })
        })
    }

    private func folderChanged(_ id: UUID, _ changed: [URL]) {
        guard let folder = folder(id) else { return }
        refreshes[id]?.cancel()
        refreshes[id] = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            refresh(id)
        }
        let arrived = changed.contains {
            $0.deletingLastPathComponent().standardizedFileURL == folder.url.standardizedFileURL
                && FileManager.default.fileExists(atPath: $0.path)
        }
        guard folder.rules.auto == .whenFilesArrive, arrived else { return }
        autoTidies[id]?.cancel()
        autoTidies[id] = Task {
            try? await Task.sleep(for: .seconds(Planner.settleTime + 5))
            guard !Task.isCancelled else { return }
            await tidyAutomatically(id)
        }
    }
}
