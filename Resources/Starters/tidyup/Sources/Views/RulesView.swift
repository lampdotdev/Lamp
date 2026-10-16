import SwiftUI

/// A folder's rules as sentences, each choice a menu inside the sentence ("Installers older than 30 days go
/// to the Trash"), so what the rules do reads the way it's set.
struct RulesView: View {
    @Binding var rules: FolderRules
    @State private var skipDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sentence("textformat") {
                ScopeMenu(scope: $rules.rename.scope)
                ChoiceMenu(selection: $rules.rename.mode, options: RenameRule.Mode.allCases) { mode in
                    switch mode {
                    case .keep: return "keep their names"
                    case .dateFirst: return "get the date first (\(Planner.dayFormatter.string(from: Date())) Name)"
                    case .byContent: return "are named by what's in them"
                    }
                }
            }
            sentence("folder") {
                ScopeMenu(scope: $rules.group.scope)
                ChoiceMenu(selection: $rules.group.mode, options: GroupRule.Mode.allCases) { mode in
                    switch mode {
                    case .none: return "stay where they are"
                    case .byKind: return "are grouped by kind (Images, Documents, Installers…)"
                    case .byMonth: return "are grouped by month"
                    }
                }
            }
            sentence("clock.arrow.circlepath") { oldFiles }
            sentence("hand.raised") {
                Text("Never touch")
                TextField("file types or names, like .psd, invoice", text: $skipDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onAppear { skipDraft = rules.skip.joined(separator: ", ") }
                    .onChange(of: skipDraft) { _, text in
                        if Self.entries(text) != rules.skip { rules.skip = Self.entries(text) }
                    }
                    .onChange(of: rules.skip) { _, skip in
                        // Added from the preview ("Leave This File Alone"): show it in the field.
                        if Self.entries(skipDraft) != skip { skipDraft = skip.joined(separator: ", ") }
                    }
                    .help("Separate with commas. “.psd” means a kind of file; anything else, a word in the name. Files still downloading or changed in the last minute are never touched.")
            }
            sentence("bolt") {
                Text("Tidy")
                ChoiceMenu(selection: $rules.auto, options: AutoTidy.allCases) { auto in
                    switch auto {
                    case .off: return "only when I click Tidy Now"
                    case .whenFilesArrive: return "whenever new files arrive"
                    case .daily: return "once a day, at 9:00"
                    }
                }
            }
        }
    }

    /// "Installers older than 30 days go to the Trash", or "Old files are left alone".
    @ViewBuilder private var oldFiles: some View {
        let action = ChoiceMenu(selection: $rules.old.action, options: OldFilesRule.Action.allCases) { action in
            switch action {
            case .leave: return "are left alone"
            case .archive: return "go to an Archive folder"
            case .trash: return "go to the Trash"
            }
        }
        if rules.old.action == .leave {
            Text("Old files")
            action
        } else {
            ScopeMenu(scope: $rules.old.scope)
            Text("older than")
            TextField("Days", value: days, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .accessibilityLabel("Days")
            Text(rules.old.days == 1 ? "day" : "days")
            action
        }
    }

    private var days: Binding<Int> {
        Binding(get: { rules.old.days }, set: { rules.old.days = min(max($0, 1), 3650) })
    }

    /// The skip list as the person types it; the rules take it as they go, without rewriting what's typed.
    private static func entries(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func sentence<Content: View>(_ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            content()
        }
        .frame(minHeight: 24)
    }
}

/// Which files a rule is for: all of them, or one kind.
struct ScopeMenu: View {
    @Binding var scope: FileKind?

    var body: some View {
        ChoiceMenu(selection: $scope, options: [nil] + FileKind.allCases.map(Optional.some)) { kind in
            guard let kind else { return "All files" }
            return kind.plural.prefix(1).uppercased() + kind.plural.dropFirst()
        }
    }
}

/// A choice inside a sentence: its words in the accent color, a menu of the other choices on click.
struct ChoiceMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        Menu {
            Picker(label(selection), selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(label(selection))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .tint(.accentColor)
        .accessibilityValue(label(selection))
    }
}
