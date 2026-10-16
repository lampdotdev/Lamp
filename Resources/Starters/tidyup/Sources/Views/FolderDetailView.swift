import SwiftUI

/// One folder: its rules as sentences at the top, then what a tidy would do (Preview) or what tidies did
/// (Activity), with Tidy Now and Undo in the toolbar.
struct FolderDetailView: View {
    enum Tab: String { case preview, activity }

    @EnvironmentObject private var model: TidyModel
    let folderID: UUID
    @SceneStorage("detailTab") private var tab = Tab.preview

    private var rules: Binding<FolderRules> {
        Binding(
            get: { model.folder(folderID)?.rules ?? FolderRules() },
            set: { rules in
                guard let index = model.folders.firstIndex(where: { $0.id == folderID }) else { return }
                model.folders[index].rules = rules
            })
    }

    var body: some View {
        if let folder = model.folder(folderID) {
            VStack(spacing: 0) {
                RulesView(rules: rules)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary)
                Divider()
                Picker("Show", selection: $tab) {
                    Text("Preview").tag(Tab.preview)
                    Text("Activity").tag(Tab.activity)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.vertical, 10)
                switch tab {
                case .preview: PreviewList(folder: folder)
                case .activity: ActivityList(folder: folder)
                }
            }
            .navigationTitle(folder.name)
            .navigationSubtitle(subtitle(folder))
            .toolbar { toolbar(folder) }
            .overlay(alignment: .bottom) { NoticeView() }
        }
    }

    private func subtitle(_ folder: WatchedFolder) -> String {
        switch folder.rules.auto {
        case .off: return ""
        case .whenFilesArrive: return "Tidies when new files arrive"
        case .daily: return "Tidies once a day"
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ folder: WatchedFolder) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.undoLastTidy(in: folderID)
            } label: {
                Label("Undo Last Tidy", systemImage: "arrow.uturn.backward")
            }
            .help("Put the files from the last tidy back where they were")
            .disabled(model.undoable(in: folder) == nil)

            Button {
                model.tidyNow(folderID)
                tab = .activity
            } label: {
                Label("Tidy Now", systemImage: "sparkles")
            }
            .help("Do what the preview shows")
            .disabled(!model.canTidy(folderID))
        }
    }
}

/// A short line after a tidy or an undo ("Moved 12 files."), gone after a few seconds.
struct NoticeView: View {
    @EnvironmentObject private var model: TidyModel

    var body: some View {
        if let notice = model.notice {
            Text(notice)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { model.notice = nil }
                }
        }
    }
}
