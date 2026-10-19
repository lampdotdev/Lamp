import SwiftUI

/// What you actually love, what you burn through, and what's missing.
struct TasteMapView: View {
    @EnvironmentObject var shelf: Shelf
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your taste map").font(Hand.font(28))
                Spacer()
                if shelf.mapping {
                    ProgressView().controlSize(.small)
                } else {
                    Button { shelf.refreshTasteMapSoon(force: true) } label: { Label("Rethink", systemImage: "arrow.clockwise") }
                        .help("Have another look at your shelf")
                        .disabled(shelf.bottles.isEmpty)
                }
            }

            if shelf.bottles.isEmpty {
                Text("Nothing to map yet. Bring some bottles home and rate them.").foregroundStyle(.secondary)
            } else if !shelf.taste.summary.isEmpty {
                Text(shelf.taste.summary).font(.system(.title3, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(FlavorFamily.allCases) { family in
                    FamilyCard(family: family, bottles: shelf.bottles.filter { $0.flavor == family },
                               gap: shelf.taste.gaps.first { $0.family == family.rawValue })
                }
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your favorites").font(.headline)
                    let top = shelf.topRated.prefix(5)
                    if top.isEmpty {
                        Text("Give bottles stars and your favorites show up here.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(top)) { b in
                        HStack(spacing: 6) {
                            Text(b.name).lineLimit(1)
                            Spacer()
                            Text("🌶️ \(b.intensity)").monospacedDigit().foregroundStyle(.secondary)
                            Label("\(b.score ?? 0)", systemImage: "star.fill").labelStyle(.titleAndIcon)
                                .monospacedDigit().foregroundStyle(.orange)
                        }
                        .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gaps on the shelf").font(.headline)
                    if shelf.taste.gaps.isEmpty {
                        Text(shelf.mapping ? "Thinking…" : "No gaps worth filling. Show-off.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(shelf.taste.gaps) { gap in
                        Label(gap.line, systemImage: "circle.dashed").font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 680)
    }
}

private struct FamilyCard: View {
    let family: FlavorFamily
    let bottles: [Bottle]
    let gap: Gap?

    private var rating: Double? {
        let r = bottles.compactMap(\.score)
        return r.isEmpty ? nil : Double(r.reduce(0, +)) / Double(r.count)
    }
    private var heat: Double? {
        bottles.isEmpty ? nil : bottles.map(\.heat).reduce(0, +) / Double(bottles.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(family.title.capitalized).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            let onShelf = bottles.filter { !$0.isRetired }.count
            let done = bottles.count - onShelf
            Text(bottles.isEmpty ? "none yet" : "\(onShelf) on the shelf" + (done > 0 ? " · \(done) finished" : ""))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let heat { Text("🌶️ " + heat.formatted(.number.precision(.fractionLength(0)))).font(.caption).monospacedDigit() }
                if let rating {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                    Text(rating.formatted(.number.precision(.fractionLength(1)))).font(.caption).monospacedDigit()
                }
            }
            .frame(height: 12)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(bottles.isEmpty ? 0.4 : 1)))
        .overlay {
            if gap != nil {
                RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .foregroundStyle(.orange.opacity(0.7))
            }
        }
        .help(gap?.line ?? family.meaning)
    }
}
