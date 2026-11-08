import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LampSidebarKit

/// The mix window (an experiment, `Mix`): someone's copy of a wish dropped in, every change either of you made since
/// you last met on one timeline, yours on the left and theirs on the right. A click, or its thumb, keeps a change, lit,
/// or leaves it out, dimmed. A change a later one replaces in part shows it. Mix saves it.
/// A window of its own while it's an experiment, opened from the desk's foot.
struct MixScene: Scene {
    var body: some Scene {
        Window("Mix Copies", id: "mix") {
            MixView().environmentObject(Store.shared)
        }
        .defaultSize(width: 620, height: 680)
        .commandsRemoved()
    }
}

@MainActor
final class MixModel: ObservableObject {
    /// One window, one mix: the import's review hands it its package too (Mix… there).
    static let shared = MixModel()
    /// `preparing`: Mix was clicked and the pick is being played back (`Mix.prepare`); the pick holds still meanwhile,
    /// as it does while `mixing` saves it.
    enum Stage: Equatable { case waiting, reading, problem(String), ready, preparing, mixing }
    @Published var stage = Stage.waiting
    @Published var lineup: Mix.Lineup?
    @Published var picked: Set<String> = []
    @Published var preview = Mix.Preview()
    /// The file's review.
    @Published var review: ImportReview?
    /// The check of what this pick comes to, when that holds code no review read (`Mix.Prepared.unseen`): made on Mix,
    /// for exactly the pick then, and gone the moment the pick changes. Mix saves it only after its review is in, and
    /// only by the stricter rule of it and the file's (`mixOpening`).
    struct Check {
        let prepared: Mix.Prepared
        var review: ImportReview?
        /// Why what the mix comes to couldn't be read for a check: nothing of it can be saved then.
        var failure: String?
    }
    @Published private(set) var check: Check?
    private var checking: Task<Void, Never>?
    private var previewing: Task<Void, Never>?

    /// The reviews Mix goes by: the file's, and once Mix found code no review read, the check of this pick too. A check
    /// adds to what the file's review said and never takes any of it back: the same code read again can come back
    /// rated lower. Nil while either is still checking.
    var reviewsInForce: [ImportReview]? {
        guard let review else { return nil }
        guard let check else { return [review] }
        return check.review.map { [review, $0] }
    }

    /// How Mix is pressed (`ImportReview.opening`): the strictest of the reviews in force.
    var mixOpening: ImportReview.Opening? {
        guard let reviews = reviewsInForce else { return nil }
        let order: [ImportReview.Opening] = [.byReturn, .byClick, .anyway]
        return reviews.map(\.opening).max { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
    }

    /// Everything the reviews in force have to say, each once, the file's first (`merged`).
    var considerations: [ImportReviewCard.Consideration] {
        Self.merged((reviewsInForce ?? []).map { ImportReviewCard.considerations($0) })
    }

    /// Several reviews' considerations as one list: a thing two of them say is said once, as seriously as the more
    /// serious says it, with every distinct reason given for it ("Not checked by AI" for two different causes).
    nonisolated static func merged(_ lists: [[ImportReviewCard.Consideration]]) -> [ImportReviewCard.Consideration] {
        var all: [ImportReviewCard.Consideration] = []
        for item in lists.joined() {
            guard let index = all.firstIndex(where: { $0.text == item.text }) else { all.append(item); continue }
            let held = all[index]
            let stronger = item.weight == .warning && held.weight != .warning ? item : held
            let details = [held.detail, item.detail].compactMap { $0 }.reduce(into: [String]()) { kept, detail in
                if !kept.contains(detail) { kept.append(detail) }
            }
            all[index] = ImportReviewCard.Consideration(text: held.text, weight: stronger.weight, icon: stronger.icon,
                                                         detail: details.isEmpty ? nil : details.joined(separator: "\n"))
        }
        return all
    }
    /// The package being mixed, which is this window's to remove (`reset`): work for any other has gone stale.
    private var folder: URL?
    /// The file being unpacked, before its package is this window's: a newer open or a reset leaves it to remove itself.
    private var opening: UUID?

    /// Nothing while a mix is being saved: that one finishes first.
    func open(_ file: URL, store: Store) {
        guard stage != .mixing else { return }
        reset()
        stage = .reading
        let token = UUID()
        opening = token
        Task {
            do {
                let package = try await Task.detached { try Sharing.open(file) }.value
                guard opening == token else { try? FileManager.default.removeItem(at: package.folder); return }
                opening = nil
                folder = package.folder
                await prepare(package, store: store)
            } catch {
                guard opening == token else { return }
                opening = nil
                stage = .problem(error.localizedDescription)
            }
        }
    }

    /// A package already open (the import's review, Mix… there), which this window then owns and removes as its own.
    /// `reviewed` is that review's finished check of exactly this package, which the window shows as it is rather than
    /// checking the code a second time; nil when the review hadn't finished, and the window checks it then.
    /// False while a mix is being saved: the package stays with whoever has it.
    func adopt(_ package: Sharing.Package, reviewed: ImportReview?, store: Store) -> Bool {
        guard stage != .mixing else { return false }
        reset()
        folder = package.folder
        stage = .reading
        Task { await prepare(package, reviewed: reviewed, store: store) }
        return true
    }

    /// How the window checks a package it was given unchecked: `Sharing.review`, which tests replace to count the checks.
    nonisolated(unsafe) static var reviewForMix: @Sendable (Sharing.Package) async -> ImportReview = { await Sharing.review($0) }
    /// How it checks what a pick comes to (`Mix.checkInput`): the same review, which tests replace to see what it reads.
    nonisolated(unsafe) static var reviewForCheck: @Sendable (Sharing.Package, Sharing.Inspection) async -> ImportReview = {
        await Sharing.review($0, inspection: $1)
    }

    /// Lines the package up with the copy here, and checks it unless `reviewed` already did. Whatever comes back once
    /// another package has taken its place is dropped.
    private func prepare(_ package: Sharing.Package, reviewed: ImportReview? = nil, store: Store) async {
        do {
            guard let history = MixHistory.read(in: package.folder) else {
                throw Mix.Failure(message: "This copy came without its versions. Ask for it again, shared from a Lamp with mixing on.")
            }
            guard let project = Mix.copy(of: package, among: store.projects) else {
                throw Mix.Failure(message: "You don't have a copy of “\(package.name)” to mix it into.")
            }
            guard !store.busy.contains(project.id) else {
                throw Mix.Failure(message: "“\(project.name)” is busy right now. Try again when it's done.")
            }
            if await Versions.hasUnsavedChanges(project) {
                guard await Versions.save(project, message: "Before mixing") else { throw Mix.Failure(message: "Lamp couldn't save your copy first.") }
                store.versionsRevision += 1
            }
            let lineup = try await Mix.lineUp(package, history: history, with: project)
            guard folder == package.folder else { return }
            self.lineup = lineup
            picked = Set(lineup.changes.filter(\.here).map(\.id))
            stage = .ready
            refresh()
            let review: ImportReview
            if let reviewed { review = reviewed } else { review = await Self.reviewForMix(package) }
            if folder == package.folder { self.review = review }
        } catch {
            guard folder == package.folder else { return }
            stage = .problem(error.localizedDescription)
        }
    }

    func toggle(_ change: Mix.Change) {
        guard stage == .ready else { return }
        if picked.contains(change.id) { picked.remove(change.id) } else { picked.insert(change.id) }
        refresh()
    }

    func takeAllTheirs() {
        guard stage == .ready, let lineup else { return }
        picked.formUnion(lineup.changes.filter { $0.side == .them }.map(\.id))
        refresh()
    }

    /// Whether the pick differs from the copy as it is.
    var changesSomething: Bool {
        guard let lineup else { return false }
        return lineup.changes.contains { $0.here != picked.contains($0.id) }
    }

    var status: String {
        guard let lineup else { return "" }
        let theirs = lineup.changes.filter { $0.side == .them }
        guard !theirs.isEmpty else { return "Nothing new from them since you last shared" }
        let inCount = theirs.filter { picked.contains($0.id) }.count
        let out = lineup.changes.filter { $0.side == .you && !picked.contains($0.id) }.count
        return "\(inCount) of \(theirs.count) of theirs in" + (out > 0 ? " · \(out) of yours out" : "")
    }

    /// Plays the pick back (`Mix.prepare`) and saves it, when the file's review read all it brings. When it brings code
    /// no review read, nothing is saved: that's checked (`Check`), and Mix saves it once the check is in, by its rule.
    func mix(store: Store, done: @escaping () -> Void) {
        guard stage == .ready, let lineup, changesSomething, review != nil else { return }
        if let check {
            guard check.review != nil, check.prepared.picked == picked else { return }
            save(check.prepared, checked: check.review, in: lineup, store: store, done: done)
            return
        }
        stage = .preparing
        let picked = self.picked
        Task {
            do {
                let prepared = try await Mix.prepare(picked, in: lineup)
                guard stage == .preparing, self.lineup?.package.folder == lineup.package.folder, self.picked == picked else { return }
                if prepared.needsCheck {
                    stage = .ready
                    startCheck(prepared, in: lineup)
                } else {
                    save(prepared, checked: nil, in: lineup, store: store, done: done)
                }
            } catch {
                guard self.lineup?.package.folder == lineup.package.folder else { return }
                stage = .problem(error.localizedDescription)
            }
        }
    }

    private func save(_ prepared: Mix.Prepared, checked: ImportReview?, in lineup: Mix.Lineup, store: Store, done: @escaping () -> Void) {
        stage = .mixing
        Task {
            do {
                try await store.mix(prepared, checked: checked, in: lineup)
                guard self.lineup?.package.folder == lineup.package.folder else { return }
                reset()
                done()
            } catch {
                guard self.lineup?.package.folder == lineup.package.folder else { return }
                stage = .problem(error.localizedDescription)
            }
        }
    }

    /// Checks what a prepared pick comes to. An answer for a pick or a file that has gone since is dropped.
    private func startCheck(_ prepared: Mix.Prepared, in lineup: Mix.Lineup) {
        dropCheck()
        check = Check(prepared: prepared)
        checking = Task {
            let input: (package: Sharing.Package, inspection: Sharing.Inspection)
            do {
                input = try await Mix.checkInput(prepared, in: lineup)
            } catch {
                guard !Task.isCancelled, check?.prepared == prepared else { return }
                check?.failure = error.localizedDescription
                return
            }
            defer { try? FileManager.default.removeItem(at: input.package.folder) }
            let review = await Self.reviewForCheck(input.package, input.inspection)
            guard !Task.isCancelled, check?.prepared == prepared, check?.review == nil else { return }
            check?.review = review
        }
    }

    private func dropCheck() {
        checking?.cancel()
        checking = nil
        check = nil
    }

    func reset() {
        previewing?.cancel()
        dropCheck()
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        opening = nil
        lineup = nil
        picked = []
        preview = Mix.Preview()
        review = nil
        stage = .waiting
    }

    /// What the pick comes to, a moment after the last click. A check of the pick before it no longer holds.
    private func refresh() {
        dropCheck()
        previewing?.cancel()
        guard let lineup else { return }
        let picked = lineup.changes.filter { self.picked.contains($0.id) }
        previewing = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let preview = await Mix.preview(picked, in: lineup)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.preview = preview }
        }
    }
}

struct MixView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var model = MixModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var targeted = false

    var body: some View {
        Group {
            switch model.stage {
            case .waiting: dropZone
            case .reading: progress("Lining up both copies…")
            case .problem(let message): problem(message)
            case .ready, .preparing, .mixing:
                if let lineup = model.lineup {
                    MixTimeline(model: model, lineup: lineup, another: choose) { model.mix(store: store) { dismiss() } }
                } else {
                    dropZone
                }
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .background(Paper.page)
        .foregroundStyle(Paper.ink)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard model.stage != .mixing, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension == "lampapp" else { return }
                Task { @MainActor in model.open(url, store: store) }
            }
            return true
        }
        .onDisappear { model.reset() }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.merge").font(.system(size: 34, weight: .light)).foregroundStyle(Paper.muted)
            Text("Drop an app file someone sent you").font(.system(size: 17, weight: .medium))
            Text("A copy of one of your apps, with their changes.\nYou'll pick which to bring into yours.")
                .multilineTextAlignment(.center).foregroundStyle(Paper.muted)
            Button("Choose File…", action: choose).buttonStyle(PaperButtonStyle(.outline)).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(targeted ? Paper.ink : Paper.rule, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).padding(24))
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(Paper.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func problem(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button("Choose Another…", action: choose).buttonStyle(PaperButtonStyle(.outline))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "lampapp") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.open(url, store: store)
    }

}

/// The two copies side by side over their changes, and what to do with them: drawn from the model alone.
struct MixTimeline: View {
    @ObservedObject var model: MixModel
    let lineup: Mix.Lineup
    var another: () -> Void = {}
    let mix: () -> Void
    /// Option held: each change shows when it was made.
    @State private var optionHeld = false
    @State private var watching: Any?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let icon = NSImage(contentsOf: Icons.previewURL(lineup.project)) {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mixing into “\(lineup.project.name)”").font(.system(size: 14, weight: .semibold))
                    Text("Click a change to keep it or leave it.")
                        .font(.system(size: 12)).foregroundStyle(Paper.muted)
                }
                Spacer(minLength: 12)
                Button("Choose Another…", action: another)
                    .buttonStyle(PaperButtonStyle(.outline))
                    .disabled(model.stage != .ready)
            }
            .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 12)
            HStack(alignment: .top, spacing: 16) {
                MixSide(title: "You", name: lineup.project.name, picture: lineup.yourPicture,
                        icon: Icons.previewURL(lineup.project))
                MixSide(title: "Them", name: lineup.package.name, picture: lineup.theirPicture,
                        icon: lineup.package.folder.appendingPathComponent("icon.png"))
            }
            .padding(.horizontal, 28).padding(.bottom, 10)
            reviewLines.padding(.horizontal, 28).padding(.bottom, 6)
            Rectangle().fill(Paper.rule).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 6) {
                    if lineup.changes.isEmpty {
                        Text("Neither of you has changed anything since you last met.").foregroundStyle(Paper.muted).padding(.top, 40)
                    }
                    ForEach(lineup.changes) { change in
                        MixRow(change: change, on: model.picked.contains(change.id), replacedBy: model.preview.replaced[change.id],
                               showsTime: optionHeld) {
                            model.toggle(change)
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 14)
            }
            Rectangle().fill(Paper.rule).frame(height: 1)
            HStack(spacing: 10) {
                Text(model.status).font(.system(size: 12)).foregroundStyle(Paper.muted)
                Spacer()
                if model.stage == .mixing || model.stage == .preparing { ProgressView().controlSize(.small) }
                Button("Take All of Theirs") { model.takeAllTheirs() }
                    .buttonStyle(PaperButtonStyle(.outline))
                    .disabled(model.stage != .ready || !lineup.changes.contains { $0.side == .them && !model.picked.contains($0.id) })
                mixButton
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .onAppear {
            optionHeld = NSEvent.modifierFlags.contains(.option)
            watching = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                optionHeld = event.modifierFlags.contains(.option)
                return event
            }
        }
        .onDisappear {
            if let watching { NSEvent.removeMonitor(watching) }
            watching = nil
        }
    }

    /// Mix, by the rule the import's buttons follow (`ImportReview.opening`), from the reviews in force: Return mixes
    /// only on a review Lamp vouches for; anything less takes a click, and "Mix Anyway" when there's something to be
    /// wary of.
    @ViewBuilder private var mixButton: some View {
        let disabled = model.stage != .ready || !model.changesSomething || model.mixOpening == nil || model.check?.failure != nil
        switch model.mixOpening {
        case .byReturn:
            Button("Mix", action: mix).buttonStyle(PaperButtonStyle(.ink)).keyboardShortcut(.defaultAction).disabled(disabled)
        case .anyway:
            Button("Mix Anyway", role: .destructive, action: mix).buttonStyle(PaperButtonStyle(.ink)).disabled(disabled)
        case .byClick, nil:
            Button("Mix", action: mix).buttonStyle(PaperButtonStyle(.ink)).disabled(disabled)
        }
    }

    /// What the checks found, each thing the review has to say in its own words, as the import's review says them:
    /// red for what should stop someone, orange for what should make them think. Nothing when it found nothing.
    private var reviewLines: some View {
        let items = model.considerations
        return VStack(alignment: .leading, spacing: 4) {
            if model.review == nil {
                waiting("Checking their code…")
            } else if let check = model.check {
                if let failure = check.failure {
                    Label(failure, systemImage: "xmark.octagon.fill").foregroundStyle(Color.red)
                } else if check.review == nil {
                    waiting("Checking what this mix brings in…")
                } else {
                    Text("Checked what this mix brings in").foregroundStyle(Paper.muted)
                }
            }
            if items.count > 3 {
                ScrollView { considerations(items) }.frame(height: 84)
            } else {
                considerations(items)
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text)
        }
        .foregroundStyle(Paper.muted)
    }

    private func considerations(_ items: [ImportReviewCard.Consideration]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: item.text).fixedSize(horizontal: false, vertical: true)
                        if let detail = item.detail {
                            Text(verbatim: detail).font(.system(size: 11)).foregroundStyle(Paper.muted).lineLimit(4).help(detail)
                        }
                    }
                } icon: {
                    Image(systemName: item.icon)
                }
                .foregroundStyle(item.weight == .warning ? Color.red : Color.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A column's head: whose it is, over the latest picture of their app, or its icon and name when there's no picture.
private struct MixSide: View {
    let title: String
    let name: String
    let picture: URL?
    let icon: URL

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let picture, let image = NSImage(contentsOf: picture) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    VStack(spacing: 6) {
                        if let image = NSImage(contentsOf: icon) {
                            Image(nsImage: image).resizable().frame(width: 56, height: 56)
                        }
                        Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Paper.card)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paper.rule))
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Paper.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One change, the window's width but for its thumbs: lit when it's kept, dimmed when it's left out. On its owner's
/// side, a thumb that does what a click does: up to keep it while it's out, turned over to leave it out while it's
/// kept. Its time shows while Option is held.
private struct MixRow: View {
    let change: Mix.Change
    let on: Bool
    let replacedBy: String?
    var showsTime = false
    let toggle: () -> Void

    private static let glow = Paper.stripes[2]
    private static let thumb: CGFloat = 24

    var body: some View {
        HStack(spacing: 8) {
            if theirs { Color.clear.frame(width: Self.thumb) } else { thumb }
            card
            if theirs { thumb } else { Color.clear.frame(width: Self.thumb) }
        }
    }

    private var thumb: some View {
        Button(action: toggle) {
            Image(systemName: "hand.thumbsup").font(.system(size: 15, weight: .medium)).foregroundStyle(Paper.ink)
                .rotationEffect(.degrees(on ? 180 : 0))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
                .frame(width: Self.thumb, height: Self.thumb).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Leave it out" : "Keep it")
    }

    private var theirs: Bool { change.side == .them }

    private var card: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            thumbnail
            VStack(alignment: .center, spacing: 2) {
                Text(change.title).font(.system(size: 13)).lineLimit(2).multilineTextAlignment(.center)
                if showsTime {
                    Text(change.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 11)).foregroundStyle(Paper.muted)
                }
                if on, let replacedBy {
                    Text("Partly replaced by “\(replacedBy)”").font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Paper.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? (replacedBy != nil ? Color.orange.opacity(0.7) : Self.glow) : Paper.rule,
                                                                 lineWidth: on ? 1.5 : 1))
        .shadow(color: on && replacedBy == nil ? Self.glow.opacity(0.45) : .clear, radius: 7)
        .opacity(on ? (replacedBy != nil ? 0.75 : 1) : 0.4)
        .animation(.easeOut(duration: 0.2), value: on)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? "In" : "Out")
    }

    @ViewBuilder private var thumbnail: some View {
        if let picture = change.picture, let image = NSImage(contentsOf: picture) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
