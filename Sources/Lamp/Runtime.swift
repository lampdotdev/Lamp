import AppKit
import CryptoKit

/// What Lamp can see of a generated app while it runs. The app saves what it prints to
/// `.lamp/runtime/log.txt` and pictures of its windows next to it (see `LampRuntime` in
/// Template.lampSupportSwift), and macOS writes a report when it crashes. All of it goes to the
/// agent, which otherwise only sees the code.
enum Runtime {
    /// Where the copy Try On points at keeps what it prints and its pictures. An app for both can be open on
    /// this Mac and in a simulator at once, so its iPhone copy has a folder of its own beside the Mac copy's,
    /// and neither writes over the other.
    static func folder(_ project: LampProject) -> URL {
        project.platform.choosesPlace && project.onIOS ? macFolder(project).appendingPathComponent("ios") : macFolder(project)
    }
    /// The Mac copy's folder, which the app itself writes to (`LampRuntime`): what only a Mac copy has, such as
    /// its answer to being asked to quit or a build held while it stays open, is read here wherever Try On points.
    static func macFolder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/runtime") }
    /// `folder` as the agent names it, from the app's folder.
    static func folderPath(_ project: LampProject) -> String { String(folder(project).path.dropFirst(project.dir.path.count + 1)) }
    static func logURL(_ project: LampProject) -> URL { folder(project).appendingPathComponent("log.txt") }
    /// What each place's build was made from, kept apart: a game or a screen has a build of its own for every place it
    /// opens (this Mac, the simulator, Android, a TV, an Xbox), and building for one leaves the others as they were. This
    /// Mac's and the simulator's are in their copies' folders; every other place's beside this Mac's, named after it.
    private static func builtURL(_ project: LampProject) -> URL {
        let place = project.destination
        guard project.platform.choosesPlace, place != .mac, place != .ios else { return folder(project).appendingPathComponent("built") }
        return macFolder(project).appendingPathComponent("built-\(place.rawValue)")
    }
    /// The build no longer stands for the sources (a build after a live change failed): the next look builds again.
    static func forgetBuilt(_ project: LampProject) { AppFolder.remove(builtURL(project), in: project.dir) }

    /// Remembers when the current build was made (the file's date, so crashes of older builds aren't blamed
    /// on it) and what it was made from: the fingerprint of the sources as they were when the build started.
    static func markBuilt(_ project: LampProject, from fingerprint: String) {
        // The build has just run in the agent's folder, which may now hold a link where this file goes.
        try? AppFolder.write(fingerprint, to: builtURL(project), in: project.dir)
        // A page's build says what its files were, so a copy of it open elsewhere is given only what differs (`PageCopies`).
        PageCopies.record(project, as: fingerprint)
    }

    /// A build that hasn't been installed because the person kept the app open when it was asked to quit. The
    /// copy that's open, and the one in the apps folder, are older than the build until it closes. Kept on
    /// disk, so the build still goes in after Lamp itself has been quit and opened again.
    private static func heldURL(_ project: LampProject) -> URL { macFolder(project).appendingPathComponent("held-build") }
    static func holdBuild(_ project: LampProject) {
        try? AppFolder.write(Data(), to: heldURL(project), in: project.dir)
    }
    static func releaseBuild(_ project: LampProject) {
        AppFolder.remove(heldURL(project), in: project.dir)
        AppFolder.remove(reloadURL(project), in: project.dir)
    }

    /// A held build that waits for the person to press Reload (`Store.awaitReload`): a request's change that the
    /// open app can't take as it runs, which Lamp doesn't reopen the app for by itself.
    private static func reloadURL(_ project: LampProject) -> URL { macFolder(project).appendingPathComponent("reload-waiting") }
    static func awaitReload(_ project: LampProject) {
        holdBuild(project)
        try? AppFolder.write(Data(), to: reloadURL(project), in: project.dir)
    }
    static func waitsForReload(_ project: LampProject) -> Bool { FileManager.default.fileExists(atPath: reloadURL(project).path) }

    static func holdsBuild(_ project: LampProject) -> Bool { FileManager.default.fileExists(atPath: heldURL(project).path) }

    /// When Play last put a TV app on each of the person's TVs and opened it there, and from which sources: the agent
    /// is told it (`DeviceNote`), since nothing else Lamp knows says what the TV has.
    struct OnTV: Codable {
        var at: Date
        var fingerprint: String
    }
    private static func onTVURL(_ project: LampProject) -> URL { macFolder(project).appendingPathComponent("on-tv.json") }
    /// `staged` is what the copy that went to the TV was made from, read before it was sent: the sources may have
    /// changed since (an edit during a slow upload), and the TV doesn't have that. Without it, the last build's.
    static func putOnTV(_ project: LampProject, tv: String, staged: String? = nil) {
        guard let made = staged ?? builtFingerprint(project) else { return }
        var all = onTV(project)
        all[tv] = OnTV(at: Date(), fingerprint: made)
        if let data = try? JSONEncoder().encode(all) { try? AppFolder.write(data, to: onTVURL(project), in: project.dir) }
    }
    /// Every device of the person's Lamp has put the app on (a TV, the Xbox, a phone, an Android device), by its place
    /// and its id there, with when and from which sources: Reload puts a change on each again (`Store.reloadEverywhere`),
    /// since only Try On's place keeps which device it is.
    struct Placed: Codable, Hashable {
        var place: Destination
        var device: String
        var at: Date
        var fingerprint: String
    }
    private static func placedURL(_ project: LampProject) -> URL { macFolder(project).appendingPathComponent("placed.json") }
    static func putOn(_ project: LampProject, staged: String? = nil) {
        guard let device = project.device, let made = staged ?? builtFingerprint(project) else { return }
        let place = project.destination
        var all = placed(project).filter { !($0.place == place && $0.device == device) }
        all.append(Placed(place: place, device: device, at: Date(), fingerprint: made))
        if let data = try? JSONEncoder().encode(all) { try? AppFolder.write(data, to: placedURL(project), in: project.dir) }
    }
    static func placed(_ project: LampProject) -> [Placed] {
        AppFile.read(placedURL(project), in: project).flatMap { try? JSONDecoder().decode([Placed].self, from: $0) } ?? []
    }

    /// Read as everything Lamp reads in the app's folder is: the agent may leave a link or a pipe in its place.
    static func onTV(_ project: LampProject) -> [String: OnTV] {
        AppFile.read(onTVURL(project), in: project).flatMap { try? JSONDecoder().decode([String: OnTV].self, from: $0) } ?? [:]
    }
    /// What the last build was made from (`markBuilt`), the fingerprint taken before its copy was staged.
    /// When the build `builtFingerprint` names was recorded.
    static func builtDate(_ project: LampProject) -> Date? {
        (try? builtURL(project).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func builtFingerprint(_ project: LampProject) -> String? {
        AppFile.text(builtURL(project), in: project).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// What the app is built from, as one hash: the contents of Sources, its widget's folder, Package.swift and the icon design,
    /// and the attached files the app itself uses (they're copied into the bundle, so a new picture for the
    /// app needs a build; a screenshot attached for the agent to look at doesn't). Not file dates, which move
    /// when a file is rewritten unchanged. Comparing this with the one recorded at build time says whether
    /// a build is needed, including for an edit made while the last build was running.
    static func fingerprint(_ project: LampProject) -> String {
        var hasher = SHA256()
        // An app for both is a different build for each place, so moving it under Try On is a change.
        if project.platform.choosesPlace { hasher.update(data: Data(project.destination.rawValue.utf8)) }
        // So is an iOS app built for Apple TV or Vision Pro (build.sh's LAMP_FAMILY).
        if project.onIOS, project.family.isOtherOS { let family = project.family; hasher.update(data: Data(family.rawValue.utf8)) }
        // A Mac app's App Intents are kept or left out by whether it can be signed for a team, so a new team is a
        // change for an app that has them (Store.intentsCanComeBack).
        // The same for a share extension, which a Mac app keeps only when it's signed for a team (Store.shareCanComeBack).
        if project.platform == .mac, Store.usesAppIntents(project) || Template.hasShare(project) { hasher.update(data: Data(Devices.team.utf8)) }
        // What each kind's build is made from (`Target.sourceRoots`), leaving out what the build makes there (an Android
        // app's `app/build`), and whatever else it depends on (a device app's declared package step).
        let target = project.platform.target
        let roots = target.recipe.sources(project).map { project.dir.appendingPathComponent($0) }
        if let inputs = target.recipe.inputs(project) { hasher.update(data: Data(inputs.utf8)) }
        for root in roots {
            let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
                .filter { file in target.recipe.built.map { !file.path.hasPrefix(root.appendingPathComponent($0).path + "/") } ?? true }
            for file in ([root] + files).sorted(by: { $0.path < $1.path }) {
                guard let data = try? Data(contentsOf: file) else { continue }
                hasher.update(data: Data(file.path.dropFirst(project.dir.path.count).utf8))
                hasher.update(data: data)
            }
        }
        // The app's own files can be big (pictures, data files): name, size and date stand in for their contents.
        for file in Sharing.assetFiles(of: project).sorted(by: { $0.path < $1.path }) {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            hasher.update(data: Data("\(file.lastPathComponent)\n\(values?.fileSize ?? 0)\n\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Starts a new log for a launch the simulator makes (a Mac app does this itself in LampRuntime.start):
    /// the last one becomes previous-log.txt.
    /// Written on the app's folder's terms (`AppFolder`, `AppFile`): the runtime folder is the agent's to write, so a
    /// link left there must not carry the log, or what was in it, anywhere else.
    static func startLog(_ project: LampProject) {
        let log = logURL(project), previous = folder(project).appendingPathComponent("previous-log.txt")
        try? AppFolder.createDirectory(folder(project), in: project.dir)
        let last = AppFile.read(log, in: project) ?? Data()
        try? AppFolder.write(last, to: previous, in: project.dir)
        try? AppFolder.write(Data(), to: log, in: project.dir)
    }

    // MARK: - Launch

    /// How long after a launch an app that goes away counts as having died on launch: it crashed or quit by itself.
    static let launchWindow: Duration = .seconds(3)

    /// Watches a launch for those first seconds, without anyone having to wait them out: a look goes on once the app
    /// has pictured its window (`shown`), and hears of a death that comes later from the watch (`Store.watchLaunch`).
    @MainActor final class LaunchWatch {
        /// When the app was asked to open: its pictures from before are an earlier copy's.
        let opened: Date
        /// The launch window passed with the app alive, or it died and `crash` says what's known.
        private(set) var ended = false
        private(set) var crash: String?
        /// The death was told to the agent: in a look's answer, or as a note with a later one.
        var told = false
        /// Which app was opened: a wish's apps share its turn's watches.
        var app = ""
        /// Lamp is closing the app itself (a rebuild, Stop, another app taking the simulator): its going is a death only
        /// when it's surely a crash. Taken back when the app stays open (`resume`).
        private(set) var retired = false
        /// Whoever opened the app went on before the window was over (`untilShown`, `settle`), so a death from here
        /// is told later, and only one that is surely a crash counts: the person may close an app that works.
        private(set) var late = false
        private var task: Task<Void, Never>?
        /// The first seconds themselves: true when the app went in them.
        private var window: Task<Bool, Never>?
        private let alive: @MainActor () -> Bool

        /// `alive` is asked every tenth of a second; `died` says what's known once it's false, given whether it came
        /// `late` or while Lamp was closing the app (`retired`), and nil when the going doesn't count as a death after all.
        /// `confirm`, when given, is asked once more as the window ends, for an app whose life is known only by asking
        /// its device (Android's), so the verdict never rests on a reading taken before a death in the last moments.
        init(opened: Date, alive: @escaping @MainActor () -> Bool, confirm: (@MainActor () async -> Bool)? = nil,
             died: @escaping @MainActor (_ late: Bool, _ retired: Bool) async -> String?) {
            self.opened = opened
            self.alive = alive
            let window = Task {
                let clock = ContinuousClock(), start = clock.now
                while alive(), clock.now - start < Runtime.launchWindow {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if alive(), let confirm { return !(await confirm()) }
                return !alive()
            }
            self.window = window
            task = Task { [weak self] in
                let gone = await window.value
                let crash = gone ? await died(self?.late ?? true, self?.retired ?? true) : nil
                self?.crash = crash
                self?.ended = true
            }
        }

        /// Called before Lamp itself ends the app. An app already gone had died before Lamp asked, which still counts.
        func retire() { if alive() { retired = true } }
        /// The app stayed open after all (the person kept it, at its question about unsaved work).
        func resume() { retired = false }

        /// Whether the app went in its first seconds, as soon as that's known: without waiting for what's known of why,
        /// which for a Mac app Lamp was closing can mean waiting for a crash report that never comes.
        func wentAway() async -> Bool {
            await window?.value ?? false
        }

        /// What's known if the app died in its first seconds; nil once they passed with it open.
        func verdict() async -> String? {
            await task?.value
            return crash
        }

        /// Waits until the app has pictured a window since it was asked to open, or the watch has ended (a menu bar
        /// app's launch, which pictures nothing, waits the whole window). True when it died.
        func untilShown(_ project: LampProject) async -> Bool {
            while !ended, !Runtime.pictured(project, since: opened) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            late = !ended
            return ended && crash != nil
        }

        /// Waits `duration`, or less when the watch ends first: for a launch nothing reports the first picture of
        /// (the simulator's). True when it died.
        func settle(_ duration: Duration) async -> Bool {
            let clock = ContinuousClock(), start = clock.now
            while !ended, clock.now - start < duration {
                try? await Task.sleep(for: .milliseconds(100))
            }
            late = !ended
            return ended && crash != nil
        }
    }

    /// Whether the app has written a picture of a window since `date`.
    static func pictured(_ project: LampProject, since date: Date) -> Bool {
        let url = folder(project).appendingPathComponent("screenshot.png")
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast > date
    }

    /// What's known about an app that died on launch: the crash report and the last lines it printed.
    /// macOS can take a while to write the report, so this waits for it.
    static func launchReport(_ project: LampProject) async -> String {
        var crash = crash(of: project)
        for _ in 0..<40 where crash == nil {
            try? await Task.sleep(for: .milliseconds(500))
            crash = self.crash(of: project)
        }
        var parts: [String] = []
        if let crash { parts.append(crash) }
        if Privacy.sharesLog, let tail = logTail(project) { parts.append("Last lines the app printed:\n" + tail) }
        return parts.isEmpty ? "It left no crash report and printed nothing." : parts.joined(separator: "\n\n")
    }

    /// Added to a request when the current build has crashed, so the agent knows without being told.
    static func crashNote(for project: LampProject) -> String {
        guard let crash = crash(of: project) else { return "" }
        return """


        Note from Lamp: the app has crashed since it was last built. Fix the cause as part of this request.\
        \(Privacy.sharesLog ? "\nWhat it printed is in \(folderPath(project))/log.txt (the latest launch) and \(folderPath(project))/previous-log.txt (the launch before)." : "")

        \(crash)
        """
    }

    // MARK: - Screenshots

    /// Added to a request when there's a picture of the current build's window, so the agent can look
    /// at what the user sees. It isn't attached: not every model can read images.
    static func screenshotNote(for project: LampProject) -> String {
        func modified(_ url: URL) -> Date? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        guard Privacy.sharesPictures, let built = modified(builtURL(project)),
              let taken = modified(folder(project).appendingPathComponent("screenshot.png")), taken > built
        else { return "" }
        // A TV app's picture is the last look at the TV preview, and the person's TV is never pictured. A page with a window
        // on this Mac is looked at there too (`Store.pageOnMac`), so it's the generic note's.
        if project.onTV, !(PageLive.takes(project) && project.hasMac) {
            return """


            Note from Lamp: \(folderPath(project))/screenshot.png is a picture of the TV preview on this Mac (not the \
            user's TV), taken at \(taken.formatted(date: .omitted, time: .shortened)). If you can view images, look at it \
            when this request is about how the app looks or behaves.
            """
        }
        let more = (2...3).map { "screenshot-\($0).png" }
            .filter { modified(folder(project).appendingPathComponent($0)).map { $0 > built } ?? false }
        return """


        Note from Lamp: \(folderPath(project))/screenshot.png is a picture of the app's front window, taken at \
        \(taken.formatted(date: .omitted, time: .shortened)), just after it opened or when the user last switched away from it\
        \(more.isEmpty ? "" : " (other open windows: " + more.map { folderPath(project) + "/" + $0 }.joined(separator: ", ") + ")"). \
        If you can view images, look at it when this request is about how the app looks or behaves.
        """
    }

    /// The picture of the app's front window, if it was taken of the current build.
    static func currentScreenshot(of project: LampProject) -> URL? {
        func modified(_ url: URL) -> Date? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        let url = folder(project).appendingPathComponent("screenshot.png")
        guard let built = modified(builtURL(project)), let taken = modified(url), taken > built else { return nil }
        return url
    }

    /// The picture of the app the desk shows when the pointer rests on its icon: its first window after each launch,
    /// which a Mac app saves itself (`LampRuntime.preview`) and Lamp takes of the simulator for an iPhone app. One
    /// for both kinds, in the Mac copy's folder: the desk shows whichever was opened last. A starter ships its own.
    static func previewURL(_ project: LampProject) -> URL { macFolder(project).appendingPathComponent("preview.png") }

    /// Asks the running app to save fresh pictures of its windows now (see `LampRuntime` in the app).
    static func requestScreenshots(of project: LampProject) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "snapshot.\(project.id)"), object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Asks a running app with a 3D scene to show one of its props on its own, from four sides (`LampSceneView` in
    /// the app), and take pictures of that. Its answer is in prop.txt: "shown", or why not.
    static func requestProp(_ name: String, of project: LampProject) {
        try? FileManager.default.removeItem(at: folder(project).appendingPathComponent("prop.txt"))
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "prop.\(project.id)"), object: nil, userInfo: ["name": name], deliverImmediately: true)
    }

    /// The app's answer to `requestProp`, waited for up to `seconds`; nil when there's none (an app without props).
    static func propAnswer(of project: LampProject, waiting seconds: Double = 5) async -> String? {
        let url = folder(project).appendingPathComponent("prop.txt")
        for _ in 0..<Int(seconds * 4) {
            if let data = AppFile.read(url, in: project) { return String(decoding: data, as: UTF8.self) }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// What moved in the app's front window over a couple of seconds (`LampRuntime.recordMotion` in the app):
    /// in words for the agent, and the two frames that differ most. Nil when the app didn't answer (built before
    /// it could, or not running).
    static func motion(of project: LampProject) async -> (text: String, pictures: [URL])? {
        let report = folder(project).appendingPathComponent("motion.json")
        let asked = Date()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "motion.\(project.id)"), object: nil, userInfo: nil, deliverImmediately: true)
        for _ in 0..<32 {
            try? await Task.sleep(for: .milliseconds(250))
            guard AppFile.attributes(report, in: project)?.modified ?? .distantPast > asked,
                  let data = AppFile.read(report, in: project),
                  let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            if answer["error"] != nil { return ("The app had no window open to watch.", []) }
            let changes = answer["changes"] as? [Double] ?? []
            let frames = answer["frames"] as? Int ?? 0, flickers = answer["flickers"] as? Int ?? 0
            let seconds = answer["seconds"] as? Double ?? 0
            guard !changes.isEmpty else { return ("Lamp couldn't take pictures of the window to watch it.", []) }
            func percent(_ x: Double) -> String { x < 0.001 ? "0%" : x < 0.01 ? "under 1%" : "\(Int((x * 100).rounded()))%" }
            let still = changes.filter { $0 < 0.001 }.count
            var text = "Watched the front window for \(String(format: "%.1f", seconds)) s, \(frames) frames. From one frame to the next, "
                + "on average \(percent(changes.reduce(0, +) / Double(changes.count))) of the picture changed, at most \(percent(changes.max() ?? 0)); "
                + "\(still) of \(changes.count) steps changed nothing."
            text += flickers > 0
                ? " \(flickers) time\(flickers == 1 ? "" : "s") a frame changed and the next changed straight back: that's flicker, not movement. The two frames that differ most follow."
                : " Nothing changed and changed straight back, so there's no flicker. The two frames that differ most follow."
            let pictures = ["motion-1.png", "motion-2.png"].map { folder(project).appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            return (text, pictures)
        }
        return nil
    }

    /// Pictures the app has saved since `date`, frontmost window first. Waits up to `seconds` for the
    /// first one: the app takes it shortly after it opens.
    static func screenshots(of project: LampProject, since date: Date, waiting seconds: Double = 6) async -> [URL] {
        func fresh() -> [URL] {
            ["screenshot.png", "screenshot-2.png", "screenshot-3.png"].map { folder(project).appendingPathComponent($0) }
                .filter { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast > date }
        }
        for _ in 0..<Int(seconds * 4) where fresh().isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return fresh()
    }

    /// What the app says happened when it carried out a `use_app` request (see `LampDriver` in the app), and
    /// whether the person stopped it part way (`LampDriver.Handover`). It writes this after its fresh pictures,
    /// so once it's here they're ready too. nil if it never answers, or `running` turns false: the app is gone.
    @MainActor
    static func useReport(of project: LampProject, id: String, waiting seconds: Double,
                          while running: () -> Bool) async -> (report: String, stopped: Bool)? {
        let url = folder(project).appendingPathComponent("use.json")
        for _ in 0..<Int(seconds * 4) where running() {
            if let data = AppFile.read(url, in: project),
               let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: String], answer["id"] == id,
               let report = answer["report"] {
                return (report, answer["stopped"] != nil)
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// The front window as text, which a Mac app writes beside its pictures (`LampScreen` in the app): what's on
    /// it with an id for each thing, for the agent to read and act on by name. Written a moment after the
    /// pictures, so it's waited for briefly. Nil when the app wrote none since `date` (an app built before
    /// there was one, or a window with nothing named in it).
    static func screenText(of project: LampProject, since date: Date) async -> String? {
        let url = folder(project).appendingPathComponent("screen.txt")
        func fresh() -> String? {
            guard AppFile.attributes(url, in: project)?.modified ?? .distantPast > date,
                  let data = AppFile.read(url, in: project) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        for _ in 0..<6 where fresh() == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return fresh()
    }

    /// The pictures the app last saved of its windows, frontmost first.
    static func pictures(of project: LampProject) -> [URL] {
        ["screenshot.png", "screenshot-2.png", "screenshot-3.png"].map { folder(project).appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Whether the app needs building: its code or bundled files changed after the current build was made,
    /// or there's no build at all.
    static func sourcesChanged(_ project: LampProject) -> Bool {
        // A wish whose apps are all in folders of their own has nothing of its own to build.
        guard project.holdsApp else { return false }
        guard FileManager.default.fileExists(atPath: project.builtURL.path),
              let built = try? String(contentsOf: builtURL(project), encoding: .utf8), !built.isEmpty else { return true }
        return built != fingerprint(project)
    }

    /// An APK built before each place had its own record, for an app on both Android places: which of the two it was built
    /// for can't be told, so both are given a record that matches no code, once, before either has one of its own (a
    /// build calls this before it writes its record). Each is then behind, and kept current like any place built before.
    static func recordAndroidBuiltBefore(_ project: LampProject) {
        let android = project.openPlaces.filter(\.isAndroid).map(project.at)
        guard project.platform.choosesPlace, android.count > 1, android.allSatisfy({ builtFingerprint($0) == nil }),
              FileManager.default.fileExists(atPath: android[0].builtURL.path) else { return }
        for there in android { markBuilt(there, from: "built before places had records of their own") }
    }

    /// Whether the build for one of the app's places is older than its code, or there's none: a place Try On doesn't
    /// point at keeps the build it was last given until it's built again (`Store.updatePlaces`, or opening it there).
    static func behind(_ project: LampProject, at place: Destination) -> Bool { sourcesChanged(project.at(place)) }

    /// Whether the app's code is still to be built: changed since its last build, and not the code that went into the
    /// open app with its whole build still running (`Store.reloadBeforeBuilding`). That build writes what it was built
    /// from only when it's done, a minute later, and the app already runs this code meanwhile.
    static func needsBuild(_ project: LampProject) -> Bool {
        sourcesChanged(project) && LiveReload.buildingFrom(project) != fingerprint(project)
    }

    // MARK: - Log

    /// The last lines of the latest launch's output.
    static func logTail(_ project: LampProject, lines: Int = 30) -> String? {
        guard let data = AppFile.read(logURL(project), in: project, last: 8_000) else { return nil }
        let tail = String(decoding: data.suffix(8_000), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n").trimmed
        return tail.isEmpty ? nil : tail
    }

    /// How much the app has printed so far, to tell later what's new.
    static func logSize(_ project: LampProject) -> Int {
        AppFile.attributes(logURL(project), in: project)?.size ?? 0
    }

    /// What the app has printed since its log was `offset` bytes long, at most the last 30 lines. nil if nothing.
    static func log(of project: LampProject, from offset: Int) -> String? {
        guard let data = AppFile.read(logURL(project), in: project), data.count > offset else { return nil }
        let lines = String(decoding: data.dropFirst(offset).suffix(8_000), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).suffix(30).joined(separator: "\n").trimmed
        return lines.isEmpty ? nil : lines
    }

    // MARK: - Crash reports

    private static let reports = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports")

    /// The newest crash of the current build, summarized: what killed the app and the calls that led there.
    static func crash(of project: LampProject) -> String? { newestCrash(of: project)?.summary }

    /// The newest crash of the current build with when it happened, which tells one crash from the next.
    static func newestCrash(of project: LampProject) -> (date: Date, summary: String)? {
        guard let built = (try? builtURL(project).resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "ips" && $0.lastPathComponent.hasPrefix(project.exe + "-") }
            .compactMap { report($0, bundleID: project.bundleID) }
            .filter { $0.date > built }
            .max { $0.date < $1.date }
    }

    /// Whether the app crashed since `date`: macOS wrote a report for it. Not a quit, which leaves none.
    static func crashed(_ project: LampProject, since date: Date) -> Bool { crash(of: project, since: date) != nil }

    /// What macOS's newest report of a crash since `date` says, whichever build it was of.
    static func crash(of project: LampProject, since date: Date) -> String? {
        let files = (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "ips" && $0.lastPathComponent.hasPrefix(project.exe + "-") }
            .compactMap { report($0, bundleID: project.bundleID) }
            .filter { $0.date > date }
            .max { $0.date < $1.date }?.summary
    }

    /// Reads a macOS crash report (.ips): one line of JSON metadata, then the report as JSON.
    private static func report(_ url: URL, bundleID: String) -> (date: Date, summary: String)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let newline = text.firstIndex(of: "\n"),
              let body = (try? JSONSerialization.jsonObject(with: Data(text[newline...].utf8))) as? [String: Any],
              (body["bundleInfo"] as? [String: Any])?["CFBundleIdentifier"] as? String == bundleID,
              let captured = body["captureTime"] as? String, let date = captureFormat.date(from: captured)
        else { return nil }

        let exception = body["exception"] as? [String: Any] ?? [:]
        let termination = body["termination"] as? [String: Any] ?? [:]
        var reason = [exception["type"] as? String, (exception["signal"] as? String).map { "(\($0))" }]
            .compactMap { $0 }.joined(separator: " ")
        if let indicator = termination["indicator"] as? String { reason += reason.isEmpty ? indicator : ", \(indicator)" }
        var lines = ["Crashed at \(date.formatted(date: .omitted, time: .standard)): \(reason.isEmpty ? "unknown reason" : reason)"]
        for messages in (body["asi"] as? [String: [String]] ?? [:]).values { lines += messages }

        // An uncaught exception carries its own backtrace; otherwise use the thread that crashed.
        let threads = body["threads"] as? [[String: Any]] ?? []
        let crashed = threads.first { $0["triggered"] as? Bool == true }?["frames"] as? [[String: Any]]
        let frames = body["lastExceptionBacktrace"] as? [[String: Any]] ?? crashed ?? []
        let images = body["usedImages"] as? [[String: Any]] ?? []
        if !frames.isEmpty { lines.append("Calls that led there, innermost first:") }
        for frame in frames.prefix(16) {
            let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0]["name"] as? String : nil }
            var line = "  \(image ?? "?")  \(frame["symbol"] as? String ?? "?")"
            if let file = frame["sourceFile"] as? String, let number = frame["sourceLine"] as? Int {
                line += "  (\(file):\(number))"
            }
            lines.append(line)
        }
        return (date, lines.joined(separator: "\n"))
    }

    private static let captureFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS Z"
        return format
    }()
}
