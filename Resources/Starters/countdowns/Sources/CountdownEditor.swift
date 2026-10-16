import SwiftUI

/// Adding or changing one countdown, shown in the panel in place of the list: a name, a day, a symbol and a
/// color, and whether it comes back every year.
struct CountdownEditor: View {
    @EnvironmentObject private var store: CountdownStore
    @State var countdown: Countdown
    let isNew: Bool
    let done: () -> Void
    @State private var confirmsDelete = false
    @FocusState private var nameFocused: Bool

    private var canSave: Bool { !countdown.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: countdown.symbol, color: countdown.color.color, size: 30)
                Text(isNew ? "New Countdown" : "Edit Countdown").font(.headline)
            }

            TextField("Name", text: $countdown.name, prompt: Text("What are you waiting for?"))
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)

            DatePicker("Day", selection: $countdown.date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: .infinity)

            Toggle("Repeats every year", isOn: $countdown.repeatsYearly)
                .help("For birthdays and anniversaries: after the day, it counts down to the next one")

            symbolPicker
            colorPicker

            HStack {
                if !isNew {
                    Button("Delete…", role: .destructive) { confirmsDelete = true }
                }
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    countdown.name = countdown.name.trimmingCharacters(in: .whitespaces)
                    countdown.date = Calendar.current.startOfDay(for: countdown.date)
                    store.save(countdown)
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(16)
        .onAppear { nameFocused = isNew }
        .confirmationDialog("Delete “\(countdown.name)”?", isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) {
                store.delete(countdown)
                done()
            }
        }
    }

    private var symbolPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
            ForEach(CountdownSymbols.all, id: \.self) { symbol in
                let chosen = countdown.symbol == symbol
                Button { countdown.symbol = symbol } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .frame(width: 32, height: 28)
                        .foregroundStyle(chosen ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(chosen ? countdown.color.color : Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 0) {
            ForEach(CountdownColor.allCases) { color in
                let chosen = countdown.color == color
                Button { countdown.color = color } label: {
                    Circle()
                        .fill(color.color.gradient)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(chosen ? 0.8 : 0), lineWidth: 2).padding(-4))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(color.name)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}
