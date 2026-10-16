import SwiftUI

/// The card that opens over an item when it's clicked: its cover and facts, and what the person keeps about
/// it (rating, status, notes). Every change is saved as it's made.
struct DetailCard: View {
    @EnvironmentObject private var library: Library
    let id: ShelfItem.ID

    var body: some View {
        if let item = library.item(id) {
            content(binding(for: item))
                .padding(18)
                .frame(width: 440)
        }
    }

    private func binding(for item: ShelfItem) -> Binding<ShelfItem> {
        Binding(get: { library.item(id) ?? item }, set: { library.update($0) })
    }

    private func content(_ item: Binding<ShelfItem>) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 10) {
                CoverView(item: item.wrappedValue, cover: library.covers[id])
                    .frame(width: 120, height: 180)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                Toggle("Cover Out", isOn: item.facesOut)
                    .toggleStyle(.checkbox)
                    .help("Stand it with its cover facing the room")
            }
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Title", text: item.title)
                        .font(.title2.weight(.semibold))
                    TextField(ItemKind.creator, text: item.creator)
                        .foregroundStyle(.secondary)
                    if let year = item.wrappedValue.year {
                        Text(String(year)).font(.callout).foregroundStyle(.tertiary)
                    }
                }
                .textFieldStyle(.plain)

                Stars(rating: item.rating)

                Picker("Status", selection: item.status) {
                    ForEach(ItemStatus.allCases) { Text($0.label).tag($0) }
                }
                if item.wrappedValue.status == .lent {
                    TextField("Lent to", text: item.lentTo, prompt: Text("Who has it?"))
                }
                Picker("Shelf", selection: item.shelfID) {
                    ForEach(library.shelves) { Text($0.name).tag($0.id) }
                }
                TagsField(tags: item.tags)

                TextEditor(text: item.notes)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .frame(height: 80)
                    .overlay(alignment: .topLeading) {
                        if item.wrappedValue.notes.isEmpty {
                            Text("Notes").foregroundStyle(.tertiary).padding(.leading, 11).padding(.top, 6)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Notes")
            }
        }
    }
}

/// Tags typed as one line. The text is kept as typed, so a comma just typed isn't swallowed before the next
/// tag is written; the list is worked out from it on every change.
struct TagsField: View {
    @Binding var tags: [String]
    @State private var text = ""

    var body: some View {
        TextField("Tags", text: $text, prompt: Text("Separated by commas"))
            .onAppear { text = tags.joined(separator: ", ") }
            .onChange(of: text) {
                tags = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
    }
}

/// One to five stars; clicking the star already given takes the rating away.
struct Stars: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { star in
                Button { rating = rating == star ? 0 : star } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .foregroundStyle(star <= rating ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5 stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
    }
}
