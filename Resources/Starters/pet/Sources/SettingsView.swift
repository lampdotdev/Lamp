import SwiftUI

/// The Settings window: the pet's name and reminder, and the habits it eats.
struct SettingsView: View {
    var body: some View {
        TabView {
            PetSettings()
                .tabItem { Label("Pet", systemImage: "pawprint") }
            HabitSettings()
                .tabItem { Label("Habits", systemImage: "checklist") }
        }
        .frame(width: 480, height: 400)
    }
}

private struct PetSettings: View {
    @EnvironmentObject private var pet: PetModel
    @State private var opensAtLogin = LampLoginItem.isEnabled
    @State private var confirmingClear = false

    private var reminderTime: String {
        let time = Calendar.current.date(bySettingHour: PetRules.reminderHour, minute: 0, second: 0, of: Date()) ?? Date()
        return time.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $pet.state.name)
                Toggle("Remind me when \(pet.displayName) is hungry", isOn: $pet.state.remindersOn)
                    .onChange(of: pet.state.remindersOn) { pet.updateReminder() }
                    .help("A gentle notification at \(reminderTime) if it has had less than half its food")
                Toggle("Open at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { LampLoginItem.isEnabled = opensAtLogin }
            }
            if pet.hasExamples {
                Section {
                    Button("Clear Examples…") { confirmingClear = true }
                        .confirmationDialog("Remove the sample habits and history?", isPresented: $confirmingClear) {
                            Button("Clear Examples", role: .destructive) { pet.clearExamples() }
                        } message: {
                            Text("Habits you added stay. \(pet.displayName)'s streak starts over from your own days.")
                        }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct HabitSettings: View {
    @EnvironmentObject private var pet: PetModel
    @State private var deleting: Habit?

    var body: some View {
        VStack(spacing: 0) {
            if pet.state.habits.isEmpty {
                ContentUnavailableView("No Habits", systemImage: "fork.knife",
                                       description: Text("Each habit is food for \(pet.displayName)."))
            } else {
                Form {
                    ForEach($pet.state.habits) { $habit in
                        HabitEditor(habit: $habit) { deleting = habit }
                    }
                }
                .formStyle(.grouped)
            }
            Divider()
            HStack {
                Button {
                    pet.addHabit()
                } label: {
                    Label("Add Habit", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Spacer()
            }
            .padding(10)
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let deleting { pet.deleteHabit(deleting) }
            }
        } message: {
            Text("What \(pet.displayName) ate of it today is taken off too.")
        }
    }
}

/// One habit's name, symbol and servings a day.
private struct HabitEditor: View {
    @EnvironmentObject private var pet: PetModel
    @Binding var habit: Habit
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("Symbol", selection: $habit.symbol) {
                ForEach(symbols, id: \.self) { symbol in
                    Image(systemName: symbol).tag(symbol)
                }
            }
            .labelsHidden()
            .fixedSize()
            .help("Symbol")
            TextField("Habit", text: $habit.name)
                .labelsHidden()
            Stepper("×\(habit.timesPerDay)", value: $habit.timesPerDay, in: 1...12)
                .monospacedDigit()
                .help("Times a day")
                .onChange(of: habit.timesPerDay) { pet.updateReminder() }
            Button(action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this habit")
            .accessibilityLabel("Delete \(habit.name)")
        }
    }

    /// The usual choices, plus whatever symbol the habit already has.
    private var symbols: [String] {
        Habit.symbolChoices.contains(habit.symbol) ? Habit.symbolChoices : [habit.symbol] + Habit.symbolChoices
    }
}
