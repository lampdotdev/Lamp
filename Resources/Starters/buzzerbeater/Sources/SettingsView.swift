import SwiftUI
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject var watcher: Watcher
    @State private var favorites = ""
    @State private var openAtLogin = LampLoginItem.isEnabled
    @State private var cityText = ""
    @State private var locating = false
    @State private var locationError: String?

    var body: some View {
        Form {
            Section {
                ForEach(watcher.settings.enabledLeagues) { league in
                    LeagueRow(league: league,
                              moment: momentBinding(league),
                              prompt: examplePrompt(league),
                              remove: { binding(for: league).wrappedValue = false })
                }
                let others = League.allCases.filter { !watcher.settings.leagues.contains($0.rawValue) }
                if !others.isEmpty {
                    Menu {
                        ForEach(others) { league in
                            Button(league.name) { binding(for: league).wrappedValue = true }
                        }
                    } label: {
                        Label("Add League", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                ForEach(watcher.moments.filter { $0.league == nil }) { moment in
                    HStack {
                        Text("Any league: \(moment.text)").font(.callout)
                        Spacer()
                        Button {
                            watcher.removeMoment(moment)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove")
                        .accessibilityLabel("Remove \(moment.text)")
                    }
                }
                if let error = watcher.interestError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Leagues")
            } footer: {
                Text("Click a league to see what counts as a good game, and change it in your own words. Clear it or press Reset to go back to the original.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Alerts") {
                Toggle("Notify me when a game gets good", isOn: $watcher.settings.notify)
            }

            Section {
                HStack {
                    TextField("Your location", text: $cityText, prompt: Text("City, e.g. Chicago, IL"))
                        .onSubmit { findCity() }
                    if locating {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            useMyLocation()
                        } label: {
                            Image(systemName: "scope")
                        }
                        .buttonStyle(.borderless)
                        .help("Use my current location")
                        .accessibilityLabel("Use my current location")
                    }
                }
                if let locationError {
                    Text(locationError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Where you watch")
            } footer: {
                Text("Your location decides which local channels you get and which games are blacked out on league passes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(["Streaming", "Live TV", "League passes"], id: \.self) { group in
                Section(group == "Streaming" ? "Your services" : group) {
                    ForEach(Service.allCases.filter { $0.group == group }) { service in
                        Toggle(service.name, isOn: serviceBinding(service))
                    }
                }
            }

            Section {
                Toggle("Only alert me about games I can watch", isOn: Binding(
                    get: { watcher.settings.onlyWatchable ?? false },
                    set: { watcher.settings.onlyWatchable = $0 }))
                    .disabled(watcher.settings.myServices.isEmpty)
            }

            Section {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        LampLoginItem.isEnabled = on
                        openAtLogin = LampLoginItem.isEnabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 640)
        .onAppear {
            cityText = watcher.settings.homeName ?? ""
            tidyHomeName()
        }
        .onDisappear { saveFavorites() }
    }

    private func momentBinding(_ league: League) -> Binding<String> {
        Binding {
            watcher.customCriteria(for: league) ?? league.defaultCriteria
        } set: { text in
            watcher.setMoment(text, league: league)
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

    private func saveFavorites() {
        let trimmed = favorites.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (watcher.settings.favoriteTeams ?? "") {
            watcher.settings.favoriteTeams = trimmed.isEmpty ? nil : trimmed
        }
    }

    private func binding(for league: League) -> Binding<Bool> {
        Binding {
            watcher.settings.leagues.contains(league.rawValue)
        } set: { on in
            if on {
                watcher.settings.leagues.append(league.rawValue)
            } else {
                watcher.settings.leagues.removeAll { $0 == league.rawValue }
            }
        }
    }
}

/// A league with its criteria, folded away until clicked.
private struct LeagueRow: View {
    let league: League
    @Binding var moment: String
    let prompt: String
    let remove: () -> Void
    @State private var expanded = false
    @State private var draft = ""
    @FocusState private var editing: Bool

    private var isCustom: Bool { moment != league.defaultCriteria }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    if expanded { finish() } else { draft = moment }
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text(league.name)
                        if !expanded && isCustom {
                            Text("Custom")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .help(moment)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(league.name), \(expanded ? "hide" : "show") what counts as a good game")

                Button(action: remove) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Stop watching \(league.name)")
                .accessibilityLabel("Remove \(league.name)")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("What counts as a good game", text: $draft,
                              prompt: Text(prompt), axis: .vertical)
                        .labelsHidden()
                        .font(.callout)
                        .focused($editing)
                        .onSubmit(finish)
                        .onChange(of: draft) { _, text in
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { moment = text }
                        }
                        .onChange(of: editing) { _, now in if !now { finish() } }
                        .accessibilityLabel("What counts as a good game in \(league.name)")
                    if isCustom {
                        Button("Reset to Default") {
                            moment = ""
                            draft = league.defaultCriteria
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .padding(.leading, 18)
                .onDisappear(perform: finish)
            }
        }
        .padding(.vertical, 2)
    }

    /// An emptied box goes back to the built-in criteria.
    private func finish() {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            moment = ""
            draft = league.defaultCriteria
        }
    }
}
