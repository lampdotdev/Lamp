import SwiftUI

/// What drops down from the menu bar: the pet, its name and mood, how full it is, and today's habits to feed it.
struct PanelView: View {
    @EnvironmentObject private var pet: PetModel
    /// The name is text until it's clicked: a field would take the cursor each time the panel opens.
    @State private var renaming = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            picture
            Divider()
            food
            Divider()
            footer
        }
        .frame(width: 330)
    }

    // MARK: Name and mood

    private var header: some View {
        VStack(spacing: 2) {
            Group {
                if renaming {
                    TextField("Name", text: $pet.state.name)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .focused($nameFocused)
                        .onSubmit { renaming = false }
                        .onChange(of: nameFocused) { _, focused in if !focused { renaming = false } }
                        .onAppear { nameFocused = true }
                } else {
                    Text(pet.state.name.isEmpty ? "Your pet" : pet.state.name)
                        .onTapGesture { renaming = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Rename") { renaming = true }
                }
            }
            .font(.system(.title2, design: .rounded, weight: .bold))
            .accessibilityLabel("Pet's name")
            .help("Click to rename your pet")
            HStack(spacing: 10) {
                Text(pet.mood.title)
                if pet.streak > 0 {
                    Label("\(pet.streak)-day streak", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                        .help("Happy days in a row")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
    }

    // MARK: The pet

    private var picture: some View {
        VStack(spacing: 8) {
            PetView(mood: pet.mood, streak: pet.streak, meal: pet.lastMeal, size: 190)
                .accessibilityElement()
                .accessibilityLabel("\(pet.displayName), \(pet.mood.title.lowercased())")
            Text(pet.mood.line)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
            FullnessBar(fullness: pet.fullness)
                .padding(.horizontal, 40)
            if let next = PetAccessory.next(after: pet.streak), !pet.state.habits.isEmpty {
                let days = next.daysNeeded - pet.streak
                Text("\(days) more happy \(days == 1 ? "day" : "days") for \(next.name)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            RadialGradient(colors: [PetLook.body.opacity(0.25), .clear], center: .center, startRadius: 10, endRadius: 170)
        )
    }

    // MARK: Today's habits

    @ViewBuilder private var food: some View {
        if pet.state.habits.isEmpty {
            VStack(spacing: 8) {
                Text("Nothing to eat yet")
                    .font(.headline)
                Text("Add a habit, and \(pet.displayName) eats each time you do it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Add a Habit…") {
                    pet.addHabit()
                    LampMenuBar.openSettings()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's food")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                ForEach(pet.state.habits) { habit in
                    HabitRow(habit: habit)
                }
            }
            .padding(10)
        }
    }

    // MARK: Buttons

    private var footer: some View {
        HStack {
            if pet.hasExamples {
                Button("Clear Examples") { pet.clearExamples() }
                    .help("Remove the sample habits and history")
            }
            Spacer()
            Button {
                LampMenuBar.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            .keyboardShortcut(",")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit")
            .accessibilityLabel("Quit")
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// How full the pet is, as a row of little hearts filling up.
private struct FullnessBar: View {
    let fullness: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(PetLook.cheek)
            Gauge(value: fullness) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(PetLook.cheek)
                .animation(.spring(duration: 0.6), value: fullness)
        }
        .accessibilityElement()
        .accessibilityLabel("Fullness")
        .accessibilityValue("\(Int((fullness * 100).rounded())) percent")
    }
}
