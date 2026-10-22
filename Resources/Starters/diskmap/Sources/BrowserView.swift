import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var model: DiskModel
    let folder: Node
    @State private var hovered: (outer: Node, inner: Node?)?

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                PathBar(folder: folder)
                Divider()
                TreemapView(folder: folder, revision: model.revision, pending: model.pendingSize(in: folder), selection: $model.selection, hovered: $hovered) { outer, inner in
                    if outer.kind == .folder {
                        model.open(outer)
                        if let inner { model.selection = [inner.id] }
                    } else {
                        model.reveal(outer)
                    }
                }
                .padding(8)
                .contextMenu {
                    // The selection when the pointer is on part of it, else just what's under the pointer.
                    if let node = hovered?.outer {
                        ItemMenu(nodes: model.selection.contains(node.id) ? model.selectedNodes : [node])
                    }
                }
                Divider()
                statusLine
            }
            .frame(minHeight: 280, idealHeight: 460, maxHeight: .infinity)
            .layoutPriority(1)

            ItemTable(folder: folder)
                .frame(minHeight: 140, idealHeight: 220, maxHeight: .infinity)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if let h = hovered {
                Text(h.inner.map { "\(h.outer.title) › \($0.title)" } ?? h.outer.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formatBytes((h.inner ?? h.outer).size))
                    .foregroundStyle(.secondary)
                Text(share((h.inner ?? h.outer).size))
                    .foregroundStyle(.tertiary)
            } else if model.scanning {
                ProgressView().controlSize(.small)
                Text("Measuring… \(model.scannedFiles.formatted()) files · \(formatBytes(model.scannedBytes))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if folder.parent != nil {
                    Text("·").foregroundStyle(.tertiary)
                    Text(folder.isComplete ? "This folder is done" : "This folder is still growing")
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("\(formatBytes(folder.size)) in \(folder.fileCount.formatted()) files")
                    .foregroundStyle(.secondary)
                if model.isPartial {
                    Text("·").foregroundStyle(.tertiary)
                    Text("Stopped early").foregroundStyle(.orange)
                        .help("Measuring was stopped, so some folders are smaller than they really are. Rescan to finish.")
                }
                if !model.notAsked.isEmpty && folder.parent == nil {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(notAskedList) not measured")
                        .foregroundStyle(.secondary)
                        .help("macOS asks before an app looks in these folders, so Disk Map waits until you ask for them.")
                    Button("Measure Them") { model.measureAsking() }
                        .buttonStyle(.link)
                        .help("Measure these folders too. macOS asks once for each.")
                }
                if model.unreadableCount > 0 && folder.parent == nil {
                    Text("·").foregroundStyle(.tertiary)
                    Button("\(model.unreadableCount.formatted()) folders couldn't be read") {
                        model.openFullDiskAccessSettings()
                    }
                    .buttonStyle(.link)
                    .help("Give Disk Map Full Disk Access in System Settings to measure these too, then rescan.")
                }
            }
            Spacer()
            if model.scanning {
                Button("Stop") { model.stopScan() }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .help("Stop measuring and keep what's been found so far")
            } else {
                Text("Double-click to open")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// "Desktop, Documents and 2 more", in the words people know these folders by.
    private var notAskedList: String {
        let order = ["Desktop", "Documents", "Downloads", "iCloud Drive", "cloud drives", "Photos", "Music", "TV",
                     "other apps' data"]
        let words = ["Mobile Documents": "iCloud Drive", "CloudStorage": "cloud drives",
                     "Containers": "other apps' data", "Group Containers": "other apps' data",
                     "iTunes": "Music", "Photo Booth Library": "Photo Booth"]
        let names = Set(model.notAsked.map { $0.hasSuffix(".photoslibrary") ? "Photos" : words[$0] ?? $0 })
            .sorted { (order.firstIndex(of: $0) ?? order.count, $0) < (order.firstIndex(of: $1) ?? order.count, $1) }
        if names.count <= 2 { return names.formatted(.list(type: .and)) }
        return "\(names[0]), \(names[1]) and \(names.count - 2) more"
    }

    private func share(_ size: Int64) -> String {
        guard folder.size > 0 else { return "" }
        return (Double(size) / Double(folder.size)).formatted(.percent.precision(.fractionLength(1)))
    }
}

struct PathBar: View {
    @EnvironmentObject var model: DiskModel
    let folder: Node

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                let chain = folder.ancestors
                ForEach(Array(chain.enumerated()), id: \.offset) { i, node in
                    if i > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button { model.go(to: node) } label: {
                        Text(node.title)
                            .fontWeight(node === folder ? .semibold : .regular)
                            .foregroundStyle(node === folder ? .primary : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(node === folder)
                }
                Text(formatBytes(folder.size))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }
}

struct ItemMenu: View {
    @EnvironmentObject var model: DiskModel
    let nodes: [Node]

    var body: some View {
        let real = nodes.filter(\.isRealItem)
        if nodes.count == 1, let node = nodes.first {
            if node.kind == .folder && !node.children.isEmpty {
                Button("Open") { model.open(node) }
            }
            if node.kind == .file {
                Button("Open") { model.openItems([node]) }
            }
            Button(node.isRealItem ? "Show in Finder" : "Open Folder in Finder") { model.reveal(node) }
                .disabled(node.kind == .hidden)
            Button("Copy Path") { model.copyPath([node]) }
                .disabled(node.kind == .hidden)
        } else {
            Button("Open \(real.count) Items") { model.openItems(real) }
                .disabled(real.isEmpty)
            Button("Show \(real.count) Items in Finder") { model.reveal(real) }
                .disabled(real.isEmpty)
            Button("Copy Paths") { model.copyPath(real) }
                .disabled(real.isEmpty)
        }
        let trashable = nodes.filter(\.canTrash)
        if !trashable.isEmpty {
            Divider()
            Button(trashable.count == 1 ? "Move to Trash…" : "Move \(trashable.count) Items to Trash…") { requestTrash(trashable) }
        }
    }
}

/// One table row, captured with its numbers at a moment so the table updates while measuring.
struct ItemRow: Identifiable, Equatable {
    let node: Node
    let size: Int64
    let fileCount: Int
    let measuring: Bool
    var id: Node.ID { node.id }

    static func == (a: ItemRow, b: ItemRow) -> Bool {
        a.node === b.node && a.size == b.size && a.fileCount == b.fileCount && a.measuring == b.measuring
    }
}

struct ItemTable: View {
    @EnvironmentObject var model: DiskModel
    let folder: Node

    var body: some View {
        let _ = model.revision
        let rows = folder.sortedChildren.map {
            ItemRow(node: $0, size: $0.size, fileCount: $0.fileCount, measuring: $0.kind == .folder && !$0.isComplete)
        }
        let total = folder.size
        Table(rows, selection: $model.selection) {
            TableColumn("Name") { row in
                HStack(spacing: 6) {
                    ItemIcon(node: row.node)
                    Text(row.node.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if row.node.notAsked {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.secondary)
                            .help("Not measured: macOS asks before Disk Map looks in here. Measure Them in the status line asks.")
                    }
                    if row.node.unreadable {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .help("Disk Map isn't allowed to look inside this folder.")
                    }
                    if row.measuring && model.scanning {
                        ProgressView().controlSize(.mini)
                            .help("Still measuring")
                    }
                }
            }
            .width(min: 180, ideal: 320)
            TableColumn("Size") { row in
                Text(row.node.notAsked ? "—" : formatBytes(row.size))
                    .monospacedDigit()
                    .foregroundStyle(row.measuring && model.scanning ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn("Share") { row in
                ShareBar(fraction: total > 0 ? Double(row.size) / Double(total) : 0)
            }
            .width(min: 80, ideal: 140)
            TableColumn("Files") { row in
                Text(row.node.kind == .hidden ? "—" : row.fileCount.formatted())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 70, max: 100)
        }
        .contextMenu(forSelectionType: Node.ID.self) { ids in
            let nodes = rows.filter { ids.contains($0.id) }.map(\.node)
            if !nodes.isEmpty { ItemMenu(nodes: nodes) }
        } primaryAction: { ids in
            let nodes = rows.filter { ids.contains($0.id) }.map(\.node)
            if nodes.count == 1, let node = nodes.first {
                if node.kind == .folder && !node.children.isEmpty { model.open(node) } else { model.reveal(node) }
            } else {
                model.openItems(nodes)
            }
        }
    }
}

struct ItemIcon: View {
    let node: Node

    var body: some View {
        switch node.kind {
        case .folder, .file:
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                .resizable()
                .frame(width: 16, height: 16)
        case .smallFiles:
            Image(systemName: "doc.on.doc").foregroundStyle(.secondary).frame(width: 16)
        case .hidden:
            Image(systemName: "gearshape.2").foregroundStyle(.secondary).frame(width: 16)
        }
    }
}

struct ShareBar: View {
    let fraction: Double

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
