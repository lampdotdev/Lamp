import SwiftUI
import CoreLocation

/// Settings, in tabs as the system's own apps have them.
struct SettingsView: View {
    @EnvironmentObject var watcher: Watcher

    var body: some View {
        TabView {
            LeaguesTab()
                .tabItem { Label("Leagues", systemImage: "trophy") }
            WatchTab()
                .tabItem { Label("Where to Watch", systemImage: "play.tv") }
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(minWidth: 520, idealWidth: 620, maxWidth: .infinity, minHeight: 440, idealHeight: 600, maxHeight: .infinity)
        .modifier(GrayToolbar())
    }
}

// MARK: - Leagues

private struct LeaguesTab: View {
    @EnvironmentObject var watcher: Watcher
    @State private var selection: String?
    @State private var editing: League?
    @State private var addingAny = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Double-click a league to define what counts as a worthwhile game")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(League.allCases) { league in
                        LeagueListRow(league: league,
                                      isOn: binding(for: league),
                                      custom: watcher.customCriteria(for: league))
                            .tag(league.rawValue)
                    }
                    ForEach(watcher.moments.filter { $0.league == nil }) { moment in
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.orange)
                                .frame(width: 26, height: 26)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Any league")
                                Text(moment.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag("any|" + moment.id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let league = League(rawValue: id) {
                        Button("Edit What Counts…") { editing = league }
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let league = League(rawValue: id) { editing = league }
                }
                Divider()
                HStack(spacing: 0) {
                    Button { addingAny = true } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .help("Watch for a moment in any league")
                    .accessibilityLabel("Add a moment for any league")
                    Divider().frame(height: 14)
                    Button { removeSelected() } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(!canRemove)
                    .help("Remove")
                    .accessibilityLabel("Remove")
                    Spacer()
                    if let error = watcher.interestError {
                        Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                    }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsBackground.color, ignoresSafeAreaEdges: [])
        .sheet(item: $editing) { league in
            CriteriaSheet(league: league,
                          text: watcher.customCriteria(for: league) ?? league.defaultCriteria,
                          prompt: examplePrompt(league)) { watcher.setMoment($0, league: league) }
        }
        .sheet(isPresented: $addingAny) {
            AnyMomentSheet { watcher.addMoment($0, league: nil) }
        }
    }

    private var canRemove: Bool {
        guard let selection else { return false }
        if selection.hasPrefix("any|") { return true }
        return watcher.settings.leagues.contains(selection)
    }

    /// Removes an any-league moment, or stops watching the selected league.
    private func removeSelected() {
        guard let selection else { return }
        if selection.hasPrefix("any|") {
            let id = String(selection.dropFirst(4))
            if let moment = watcher.moments.first(where: { $0.id == id }) { watcher.removeMoment(moment) }
            self.selection = nil
        } else if let league = League(rawValue: selection) {
            binding(for: league).wrappedValue = false
        }
    }

    private func binding(for league: League) -> Binding<Bool> {
        Binding {
            watcher.settings.leagues.contains(league.rawValue)
        } set: { on in
            if on {
                if !watcher.settings.leagues.contains(league.rawValue) { watcher.settings.leagues.append(league.rawValue) }
            } else {
                watcher.settings.leagues.removeAll { $0 == league.rawValue }
            }
        }
    }

    private func examplePrompt(_ league: League) -> String {
        switch league {
        case .nba, .wnba: "e.g. Someone heading for 50 points"
        case .nfl, .cfb: "e.g. A team down two scores in the 4th"
        case .mcbb, .wcbb: "e.g. A big underdog leading late"
        case .nhl: "e.g. A goalie pulled in a one-goal game"
        case .mlb: "e.g. A no-hitter through 6"
        case .epl, .mls, .ucl, .laliga: "e.g. A late winner in a big match"
        }
    }
}

private struct LeagueListRow: View {
    let league: League
    @Binding var isOn: Bool
    let custom: String?

    var body: some View {
        HStack(spacing: 12) {
            LeagueLogo(league: league)
                .opacity(isOn ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 1) {
                Text(league.name)
                    .foregroundStyle(isOn ? .primary : .secondary)
                Text(custom ?? "Built-in description")
                    .font(.caption)
                    .foregroundStyle(custom == nil ? .tertiary : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if custom != nil {
                Text("Custom")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            Toggle(league.name, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// What counts as a good game in one league, in the person's words: a sheet like the system's.
private struct CriteriaSheet: View {
    let league: League
    @State var text: String
    let prompt: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isDefault: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == league.defaultCriteria
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LeagueLogo(league: league, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(league.name).font(.title3.weight(.semibold))
                    Text(isDefault ? "Built-in description" : "Your own description")
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("A worthwhile game is…").font(.callout.weight(.medium))
                TextField("What counts as a worthwhile game", text: $text, prompt: Text(prompt), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)
                Text("Describe it in your own words. Clear it to go back to the built-in description.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Reset to Default") { text = league.defaultCriteria }
                    .disabled(isDefault)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

/// A moment to watch for in every league.
private struct AnyMomentSheet: View {
    let add: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .frame(width: 52, height: 52)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Any league").font(.title3.weight(.semibold))
                    Text("A moment to hear about wherever it happens").foregroundStyle(.secondary)
                }
            }
            TextField("Moment", text: $text, prompt: Text("e.g. My alma mater in a close game"), axis: .vertical)
                .labelsHidden()
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    add(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

// MARK: - Where to Watch

private struct WatchTab: View {
    @EnvironmentObject var watcher: Watcher
    @State private var cityText = ""
    @State private var locating = false
    @State private var locationError: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Your location", text: $cityText, prompt: Text("City, e.g. Chicago, IL"))
                        .onSubmit { findCity() }
                    if locating {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button {
                            useMyLocation()
                        } label: {
                            Image(systemName: "location")
                        }
                        .buttonStyle(.borderless)
                        .help("Use my current location")
                        .accessibilityLabel("Use my current location")
                    }
                }
                if let locationError {
                    Text(locationError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text("Your location decides which local channels you get and which games are blacked out on league passes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(["Streaming", "Live TV", "League passes"], id: \.self) { group in
                Section(group == "Streaming" ? "Your services" : group) {
                    ForEach(Service.allCases.filter { $0.group == group }) { service in
                        Toggle(isOn: serviceBinding(service)) {
                            HStack(spacing: 10) {
                                Group {
                                    if NetworkLogos.url(for: service.name) != nil {
                                        NetworkBadge(name: service.name, size: 20, showName: false)
                                    } else {
                                        Image(systemName: service == .antenna ? "antenna.radiowaves.left.and.right" : "tv")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 20, height: 20)
                                Text(service.name)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                }
            }

            Section {
                Toggle("Only alert me about games I can watch", isOn: Binding(
                    get: { watcher.settings.onlyWatchable ?? false },
                    set: { watcher.settings.onlyWatchable = $0 }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(watcher.settings.myServices.isEmpty)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SettingsBackground.color, ignoresSafeAreaEdges: [])
        .onAppear {
            cityText = watcher.settings.homeName ?? ""
            tidyHomeName()
        }
    }

    private func useMyLocation() {
        locating = true
        locationError = nil
        Task {
            defer { locating = false }
            do {
                let place = try await LampLocation.current()
                setHome(place, fallbackName: "Current location")
            } catch {
                locationError = error.localizedDescription
            }
        }
    }

    private func findCity() {
        let text = cityText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != watcher.settings.homeName else { return }
        locating = true
        locationError = nil
        Task {
            defer { locating = false }
            do {
                let place = try await LampLocation.find(text)
                setHome(place, fallbackName: text)
            } catch {
                locationError = error.localizedDescription
            }
        }
    }

    private func setHome(_ place: LampLocation.Place, fallbackName: String) {
        Task {
            let name = await Self.cityAndState(place.latitude, place.longitude) ?? fallbackName
            saveHome(name: name, latitude: place.latitude, longitude: place.longitude)
        }
    }

    /// "Brooklyn, NY": the town and state (or country outside the US) for a spot on the map.
    static func cityAndState(_ latitude: Double, _ longitude: Double) async -> String? {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude)).first
        else { return nil }
        let town = mark.locality ?? mark.subAdministrativeArea
        let region = mark.isoCountryCode == "US" ? mark.administrativeArea : (mark.administrativeArea ?? mark.country)
        let parts = [town, region].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Tidies a name saved before it was just the city and state.
    private func tidyHomeName() {
        guard let lat = watcher.settings.homeLatitude, let lon = watcher.settings.homeLongitude else { return }
        Task {
            if let name = await Self.cityAndState(lat, lon), name != watcher.settings.homeName {
                saveHome(name: name, latitude: lat, longitude: lon)
            }
        }
    }

    private func saveHome(name: String, latitude: Double, longitude: Double) {
        cityText = name
        var s = watcher.settings
        s.homeName = name
        s.homeLatitude = latitude
        s.homeLongitude = longitude
        watcher.settings = s
    }

    private func serviceBinding(_ service: Service) -> Binding<Bool> {
        Binding {
            watcher.settings.services?.contains(service.rawValue) ?? false
        } set: { on in
            var list = watcher.settings.services ?? []
            list.removeAll { $0 == service.rawValue }
            if on { list.append(service.rawValue) }
            watcher.settings.services = list
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject var watcher: Watcher
    @State private var openAtLogin = LampLoginItem.isEnabled

    var body: some View {
        Form {
            Section("Alerts") {
                Toggle("Notify me when a game gets good", isOn: $watcher.settings.notify)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            Section {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: openAtLogin) { _, on in
                        LampLoginItem.isEnabled = on
                        openAtLogin = LampLoginItem.isEnabled
                    }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SettingsBackground.color, ignoresSafeAreaEdges: [])
    }
}

/// The gray behind settings, as in System Settings; the boxes on it stay lighter.
enum SettingsBackground {
    static let color = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.12, alpha: 1)
            : NSColor(white: 0.925, alpha: 1)
    })
}

/// The tab bar in the same gray as the page under it.
private struct GrayToolbar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .toolbarBackground(SettingsBackground.color, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}
