import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LampSidebarKit

/// The mix window (an experiment, `Mix`): someone's copy of a wish dropped in, every change either of you made since
/// you last met on one timeline, yours on the left and theirs on the right. A click slots a change in, lit, or out,
/// dimmed and nudged to its side; a drag does the same. A change a later one replaces in part shows it. Mix saves it.
/// A window of its own while it's an experiment, opened from the desk's foot.
struct MixScene: Scene {
    var body: some Scene {
        Window("Mix Copies", id: "mix") {
            MixView().environmentObject(Store.shared)
        }
        .defaultSize(width: 760, height: 680)
        .commandsRemoved()
    }
}

@MainActor
final class MixModel: ObservableObject {
    /// One window, one mix: the import's review hands it a file too (Mix… there).
    static let shared = MixModel()
    enum Stage: Equatable { case waiting, reading, problem(String), ready, mixing }
    @Published var stage = Stage.waiting
    @Published var lineup: Mix.Lineup?
    @Published var picked: Set<String> = []
    @Published var preview = Mix.Preview()
    @Published var review: ImportReview?
    private var previewing: Task<Void, Never>?
    private var folder: URL?

    func open(_ file: URL, store: Store) {
        reset()
        stage = .reading
        Task {
            do {
                let package = try await Task.detached { try Sharing.open(file) }.value
                folder = package.folder
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
                let review = await Sharing.review(package)
                if folder == package.folder { self.review = review }
            } catch {
                stage = .problem(error.localizedDescription)
            }
        }
    }

    func toggle(_ change: Mix.Change) {
        if picked.contains(change.id) { picked.remove(change.id) } else { picked.insert(change.id) }
        refresh()
    }

    func takeAllTheirs() {
        guard let lineup else { return }
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

    func mix(store: Store, done: @escaping () -> Void) {
        guard let lineup, changesSomething else { return }
        stage = .mixing
        Task {
            do {
                try await store.mix(picked, in: lineup)
                reset()
                done()
            } catch {
                stage = .problem(error.localizedDescription)
            }
        }
    }

    func reset() {
        previewing?.cancel()
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        lineup = nil
        picked = []
        preview = Mix.Preview()
        review = nil
        stage = .waiting
    }

    /// What the pick comes to, a moment after the last click.
    private func refresh() {
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
            case .ready, .mixing:
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
            Text("Drop a wish file someone sent you").font(.system(size: 17, weight: .medium))
            Text("A copy of one of your wishes, with their changes.\nYou'll pick which to bring into yours.")
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let icon = NSImage(contentsOf: Icons.previewURL(lineup.project)) {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mixing into “\(lineup.project.name)”").font(.system(size: 14, weight: .semibold))
                    Text("Click a change to bring it in or leave it out. Where two touch the same thing, the later one wins.")
                        .font(.system(size: 12)).foregroundStyle(Paper.muted)
                }
                Spacer(minLength: 12)
                Button("Choose Another…", action: another)
                    .buttonStyle(PaperButtonStyle(.outline))
                    .disabled(model.stage == .mixing)
            }
            .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 12)
            HStack(alignment: .top, spacing: 16) {
                MixSide(title: "You", name: lineup.project.name, picture: lineup.yourPicture,
                        icon: Icons.previewURL(lineup.project))
                MixSide(title: "Them", name: lineup.package.name, picture: lineup.theirPicture,
                        icon: lineup.package.folder.appendingPathComponent("icon.png"))
            }
            .padding(.horizontal, 28).padding(.bottom, 10)
            if let line = reviewLine { line.padding(.bottom, 6) }
            Rectangle().fill(Paper.rule).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 6) {
                    if lineup.changes.isEmpty {
                        Text("Neither of you has changed anything since you last met.").foregroundStyle(Paper.muted).padding(.top, 40)
                    }
                    ForEach(lineup.changes) { change in
                        MixRow(change: change, on: model.picked.contains(change.id), replacedBy: model.preview.replaced[change.id]) {
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
                if model.stage == .mixing { ProgressView().controlSize(.small) }
                Button("Take All of Theirs") { model.takeAllTheirs() }
                    .buttonStyle(PaperButtonStyle(.outline))
                    .disabled(model.stage == .mixing || !lineup.changes.contains { $0.side == .them && !model.picked.contains($0.id) })
                Button("Mix", action: mix)
                    .buttonStyle(PaperButtonStyle(.ink))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.stage == .mixing || !model.changesSomething || model.review == nil)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    /// What the check of their code found, in the review's own words; nothing when it found nothing.
    private var reviewLine: AnyView? {
        guard let review = model.review else {
            return AnyView(HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Checking their code…")
            }.font(.system(size: 12)).foregroundStyle(Paper.muted))
        }
        guard let first = ImportReviewCard.considerations(review).first else { return nil }
        return AnyView(Label(first.text, systemImage: first.icon)
            .font(.system(size: 12))
            .foregroundStyle(first.weight == .warning ? Color.red : Color.orange))
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

/// One change, on its owner's side: a switch's travel toward the middle and lit when it's in, back out and dimmed
/// when it's out.
private struct MixRow: View {
    let change: Mix.Change
    let on: Bool
    let replacedBy: String?
    let toggle: () -> Void

    private static let travel: CGFloat = 18
    private static let glow = Paper.stripes[2]

    var body: some View {
        HStack(spacing: 16) {
            if change.side == .you { card; Color.clear.frame(maxWidth: .infinity, maxHeight: 1) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 1); card }
        }
    }

    private var card: some View {
        HStack(spacing: 10) {
            if let picture = change.picture, let image = NSImage(contentsOf: picture) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(change.title).font(.system(size: 13)).lineLimit(2)
                Text(change.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.system(size: 11)).foregroundStyle(Paper.muted)
                if on, let replacedBy {
                    Text("Partly replaced by “\(replacedBy)”").font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Paper.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? (replacedBy != nil ? Color.orange.opacity(0.7) : Self.glow) : Paper.rule,
                                                                 lineWidth: on ? 1.5 : 1))
        .shadow(color: on && replacedBy == nil ? Self.glow.opacity(0.45) : .clear, radius: 7)
        .opacity(on ? (replacedBy != nil ? 0.75 : 1) : 0.4)
        .offset(x: on ? 0 : (change.side == .you ? -Self.travel : Self.travel))
        .animation(.spring(response: 0.26, dampingFraction: 0.6), value: on)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .gesture(DragGesture(minimumDistance: 6).onEnded { drag in
            let inward = change.side == .you ? drag.translation.width > 0 : drag.translation.width < 0
            if inward != on { toggle() }
        })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? "In" : "Out")
    }
}
