import SwiftUI
import MapKit

/// A place to set the game in, as kept between launches: what it's called, where it is, and its country (for
/// which side of the road and what the signs look like).
struct TravelPlace: Codable, Hashable, Identifiable {
    var name: String
    var region: String
    var lat: Double
    var lon: Double
    var country: String?

    var id: String { String(format: "%@|%.4f|%.4f", name, lat, lon) }

    static let newYork = TravelPlace(name: "New York", region: "NY, USA", lat: 40.7580, lon: -73.9855, country: "US")
    /// Where a new game starts: Market Street, downtown.
    static let sanFrancisco = TravelPlace(name: "San Francisco", region: "CA, USA", lat: 37.7880, lon: -122.4075, country: "US")

    /// Some places to go without searching.
    static let suggestions: [TravelPlace] = [
        sanFrancisco,
        newYork,
        TravelPlace(name: "London", region: "England, UK", lat: 51.5100, lon: -0.1340, country: "GB"),
        TravelPlace(name: "Paris", region: "France", lat: 48.8700, lon: 2.3310, country: "FR"),
        TravelPlace(name: "Rome", region: "Italy", lat: 41.8986, lon: 12.4769, country: "IT"),
        TravelPlace(name: "Tokyo", region: "Japan", lat: 35.6595, lon: 139.7005, country: "JP"),
        TravelPlace(name: "Sydney", region: "NSW, Australia", lat: -33.8688, lon: 151.2093, country: "AU"),
    ]

    /// The game's settings for this place.
    var config: CityConfig {
        return CityConfig(name: name, region: region, lat: lat, lon: lon, start: (lat, lon),
                          style: .forCountry(country), busName: "\(name) Bus")
    }

    // MARK: Kept between launches

    static func saved() -> TravelPlace? { LampStore.load(TravelPlace.self, from: "place") }

    static var recent: [TravelPlace] { LampStore.load([TravelPlace].self, from: "recentPlaces") ?? [] }

    /// Saved as where the game is, and first in the recent places.
    func remember() {
        LampStore.save(self, to: "place")
        var list = Self.recent.filter { $0.id != id }
        list.insert(self, at: 0)
        LampStore.save(Array(list.prefix(8)), to: "recentPlaces")
    }
}

/// Go anywhere: search for a city, a neighbourhood, a landmark or an address, or pick a recent place.
struct TravelSheet: View {
    @ObservedObject var nav: NavModel
    @State private var query = ""
    @State private var found: [TravelPlace] = []
    @State private var searching = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Travel").font(.title2.weight(.semibold))
                Text("The map of wherever you pick is downloaded and built around you.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("A city, landmark or address", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if let first = found.first { go(first) } }
            }
            .padding(16)
            Divider()
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    let recent = TravelPlace.recent
                    if !recent.isEmpty {
                        Section("Recent") { ForEach(recent) { row($0) } }
                    }
                    Section("Places") { ForEach(TravelPlace.suggestions.filter { s in !recent.contains { $0.id == s.id } }) { row($0) } }
                } else if searching && found.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("Searching…").foregroundStyle(.secondary) }
                } else if found.isEmpty {
                    Text(failed ? "Couldn't search right now. Check the internet connection." : "No places found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(found) { row($0) }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Text("Now in \(CityConfig.current.name)").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { nav.travelOpen = false }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 480)
        .task(id: query) { await search() }
    }

    private func row(_ p: TravelPlace) -> some View {
        Button { go(p) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.body.weight(.medium))
                Text(p.region).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func go(_ p: TravelPlace) {
        nav.travelOpen = false
        nav.onTravel?(p)
    }

    /// Apple Maps' search, a moment after typing stops.
    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { found = []; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.address, .pointOfInterest]
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            failed = false
            var seen = Set<String>()
            found = response.mapItems.compactMap { item -> TravelPlace? in
                let mark = item.placemark
                let c = mark.coordinate
                let name = item.name ?? mark.locality ?? q
                var where_ = [mark.locality, mark.administrativeArea, mark.country].compactMap { $0 }
                if where_.first == name { where_.removeFirst() }
                let p = TravelPlace(name: name, region: where_.joined(separator: ", "), lat: c.latitude, lon: c.longitude,
                                    country: mark.isoCountryCode)
                return seen.insert(p.id).inserted ? p : nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
            found = []
        }
    }
}
