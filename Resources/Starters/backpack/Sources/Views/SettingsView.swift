import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var backpack: Backpack
    @State private var newChild = ""
    @State private var newSchool = ""
    @State private var newOther = ""
    @State private var opensAtLogin = LampLoginItem.isEnabled
    @State private var confirmStartOver = false

    var body: some View {
        Form {
            Section("Children") {
                names($backpack.settings.children, empty: "No names yet")
                addField("First name", text: $newChild) { backpack.settings.children.append($0) }
            }

            Section {
                names($backpack.settings.schoolSenders, empty: "None yet")
                addField("Address, or @school.org for all of it", text: $newSchool) { backpack.settings.schoolSenders.append($0.lowercased()) }
            } header: {
                Text("Always from school")
            }

            Section {
                names($backpack.settings.otherSenders, empty: "None")
                addField("Address, or @example.org for all of it", text: $newOther) { backpack.settings.otherSenders.append($0.lowercased()) }
            } header: {
                Text("Never from school")
            }

            Section("Mail") {
                Picker("Look back", selection: $backpack.settings.lookBackDays) {
                    Text("1 month").tag(30)
                    Text("2 months").tag(60)
                    Text("3 months").tag(90)
                }
                Toggle("Notify me about new things to do", isOn: $backpack.settings.notify)
                    .toggleStyle(.checkbox)
                Toggle("Open at login", isOn: $opensAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: opensAtLogin) { LampLoginItem.isEnabled = opensAtLogin }
            }

            Section {
                HStack {
                    if backpack.hasExamples {
                        Button("Clear Examples") { backpack.clearExamples() }
                    }
                    Spacer()
                    Button("Start Over…") { confirmStartOver = true }
                        .disabled(!backpack.settings.readsMail || backpack.isChecking)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 520)
        .confirmationDialog("Read your inbox again from the start?", isPresented: $confirmStartOver) {
            Button("Start Over", role: .destructive) { Task { await backpack.startOver() } }
        } message: {
            Text("Everything on the list goes, done or not, and the last \(Format.lookBack(backpack.settings.lookBackDays)) of school emails are read again.")
        }
    }

    private func names(_ list: Binding<[String]>, empty: String) -> some View {
        Group {
            if list.wrappedValue.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(list.wrappedValue, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Button {
                        list.wrappedValue.removeAll { $0 == name }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove")
                    .accessibilityLabel("Remove \(name)")
                }
            }
        }
    }

    private func addField(_ prompt: String, text: Binding<String>, add: @escaping (String) -> Void) -> some View {
        TextField("Add", text: text, prompt: Text(prompt))
            .labelsHidden()
            .onSubmit {
                let value = text.wrappedValue.trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { return }
                add(value)
                text.wrappedValue = ""
            }
    }
}
