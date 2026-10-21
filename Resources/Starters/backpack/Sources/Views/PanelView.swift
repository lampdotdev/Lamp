import SwiftUI

struct PanelView: View {
    @EnvironmentObject var backpack: Backpack
    @AppStorage("showDone") private var showDone = false
    @State private var expanded: String?
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !backpack.settings.readsMail { welcome }
                    if let error = backpack.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                    if backpack.groups.isEmpty && backpack.lastChecked != nil && !backpack.isChecking {
                        allClear
                    }
                    ForEach(backpack.groups) { group in
                        section(group.title, late: group.id == "late") {
                            ForEach(group.todos) { todo in row(todo) }
                        }
                    }
                    if !backpack.recentlyDone.isEmpty { done }
                    if backpack.hasExamples && backpack.settings.readsMail == false {
                        HStack {
                            Text("These are examples.")
                            Button("Clear Examples") { withAnimation(.snappy) { backpack.clearExamples() } }
                                .buttonStyle(.link)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeight.self, value: proxy.size.height)
                })
            }
            .frame(height: min(max(contentHeight, 120), 560))
            .onPreferenceChange(ContentHeight.self) { contentHeight = $0 }
            Divider()
            footer
        }
        .frame(width: 380)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Backpack").font(.headline)
                Group {
                    if let status = backpack.status {
                        Text(status)
                    } else if let checked = backpack.lastChecked {
                        Text("Checked Mail \(checked, style: .relative) ago")
                    } else {
                        Text("What school emails ask of you")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if backpack.isChecking {
                ProgressView().controlSize(.small)
            } else if backpack.settings.readsMail {
                Button {
                    Task { await backpack.check() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Check Mail now")
                .accessibilityLabel("Check Mail now")
            }
            LampPanelWand()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Find what school emails ask of you", systemImage: "envelope.open")
                .font(.subheadline.weight(.semibold))
            Text("Backpack reads the last \(Format.lookBack(backpack.settings.lookBackDays)) of your inbox in Mail, then each new email, and lists the forms, payments and days to remember. The AI you use in Lamp reads the school emails.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Read My Mail") { Task { await backpack.startReading() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(backpack.isChecking)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private var allClear: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Nothing to do").font(.headline)
            Text("New school emails show up here as they arrive.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) { showDone.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(showDone ? 90 : 0))
                    Text("Done · \(backpack.recentlyDone.count)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDone {
                VStack(spacing: 0) {
                    ForEach(backpack.recentlyDone) { todo in row(todo) }
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, late: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(late ? Color.red : Color.secondary)
            VStack(spacing: 0) { content() }
        }
    }

    private func row(_ todo: Todo) -> some View {
        TodoRow(todo: todo, isExpanded: expanded == todo.id) {
            withAnimation(.snappy) { expanded = expanded == todo.id ? nil : todo.id }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { LampMenuBar.openSettings() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
