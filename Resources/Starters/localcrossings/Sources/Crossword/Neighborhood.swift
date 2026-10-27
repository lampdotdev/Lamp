import Foundation
import MapKit
import CoreLocation

/// The places around one spot as the map knows them: what the crossword's answers are made of. It's gathered
/// once for a place and kept, so a day's puzzle never waits on the network; a new one is gathered when the
/// person is somewhere else or this one is a few weeks old.
struct Neighborhood: Codable, Equatable {
    /// A named place: a café, a park, a museum.
    struct Spot: Codable, Hashable {
        var name: String
        /// What it is, in plain words: "Café", "Park", "Theater".
        var kind: String
        var street: String?
    }

    /// An answer and clue the AI chose for this place (`Polish`), in the order it chose them: the first ones
    /// are those anyone living here would know.
    struct Curated: Codable, Hashable {
        var answer: String
        var clue: String
    }

    var latitude: Double
    var longitude: Double
    /// The smallest name the map has for the part of town ("Park Slope", or the borough when that's all it has).
    var area: String?
    var town: String?
    var spots: [Spot]
    /// Every street a place here is on, with how many are on it: the busiest is the main drag.
    var streets: [String: Int]
    var gathered: Date
    var curated: [Curated] = []

    /// What the masthead calls it: "The Park Slope Crossword".
    var title: String { area ?? town ?? "Neighborhood" }

    func distance(to latitude: Double, _ longitude: Double) -> Double {
        CLLocation(latitude: self.latitude, longitude: self.longitude)
            .distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    /// Still good for a spot: close enough to be the same neighborhood, and gathered in the last few weeks.
    func covers(_ latitude: Double, _ longitude: Double) -> Bool {
        distance(to: latitude, longitude) < 1_500 && Date().timeIntervalSince(gathered) < 21 * 86_400
    }
}

/// Asks the map what's around a spot. Everything goes out at once (a few searches for places, a few for the
/// streets' names) and comes back in about half a second, from Apple's map, with no key.
enum Survey {
    struct Failure: LocalizedError {
        var errorDescription: String? { "The map couldn't be reached. Check the internet connection and try again." }
    }

    /// Somewhere with too few named places for a puzzle: a few houses on a country road.
    struct TooQuiet: LocalizedError {
        var errorDescription: String? { "The map doesn't name enough places around here for a puzzle. Try the nearest town." }
    }

    private static let food: [MKPointOfInterestCategory] = [.restaurant, .cafe, .bakery, .brewery, .winery, .nightlife]
    private static let outdoors: [MKPointOfInterestCategory] = [.park, .nationalPark, .beach, .marina, .zoo]
    private static let culture: [MKPointOfInterestCategory] = [.museum, .library, .theater, .movieTheater, .stadium, .university]

    static func gather(latitude: Double, longitude: Double) async throws -> Neighborhood {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        // Five spots, the center and four 600 m away, so places come from the whole neighborhood and not one block.
        let points = [center] + [(600.0, 0.0), (-600, 0), (0, 600), (0, -600)].map { offset(center, north: $0.0, east: $0.1) }

        async let found: [Neighborhood.Spot] = withTaskGroup(of: [Neighborhood.Spot].self) { group in
            for point in points { group.addTask { await places(near: point, within: 450, food) } }
            group.addTask { await places(near: center, within: 1_500, outdoors) }
            group.addTask { await places(near: center, within: 1_500, culture) }
            var all: [Neighborhood.Spot] = []
            for await batch in group { all += batch }
            return all
        }
        async let marks: [(Int, CLPlacemark)] = withTaskGroup(of: (Int, CLPlacemark)?.self) { group in
            for (index, point) in points.enumerated() {
                group.addTask { await placemark(at: point).map { (index, $0) } }
            }
            var all: [(Int, CLPlacemark)] = []
            for await mark in group { if let mark { all.append(mark) } }
            return all
        }

        let spots = Array(Set(await found)).sorted { $0.name < $1.name }
        let named = await marks.sorted { $0.0 < $1.0 }.map(\.1)
        guard !spots.isEmpty || !named.isEmpty else { throw Failure() }

        var streets: [String: Int] = [:]
        for street in spots.compactMap(\.street) + named.compactMap(\.thoroughfare) { streets[street, default: 0] += 1 }
        let middle = named.first
        return Neighborhood(latitude: latitude, longitude: longitude,
                            area: middle?.subLocality ?? middle?.locality, town: middle?.locality,
                            spots: spots, streets: streets, gathered: Date())
    }

    /// Where a typed place is ("Montpelier, VT"), and what to call it.
    static func find(_ text: String) async throws -> (latitude: Double, longitude: Double, name: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        guard let item = try await MKLocalSearch(request: request).start().mapItems.first else {
            throw Failure()
        }
        let mark = item.placemark
        return (mark.coordinate.latitude, mark.coordinate.longitude,
                mark.subLocality ?? mark.locality ?? item.name ?? text)
    }

    /// The city in this Mac's time zone ("America/New_York" is New York): somewhere to begin before the person
    /// has said where they are, and when they'd rather not.
    static func timeZoneCity() async throws -> (latitude: Double, longitude: Double, name: String) {
        let city = TimeZone.current.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
        return try await find(city ?? "New York")
    }

    private static func offset(_ c: CLLocationCoordinate2D, north: Double, east: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude + north / 111_000,
                               longitude: c.longitude + east / (111_000 * cos(c.latitude * .pi / 180)))
    }

    private static func places(near point: CLLocationCoordinate2D, within radius: Double,
                               _ categories: [MKPointOfInterestCategory]) async -> [Neighborhood.Spot] {
        let request = MKLocalPointsOfInterestRequest(center: point, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap { item in
            guard let name = item.name, let category = item.pointOfInterestCategory else { return nil }
            return Neighborhood.Spot(name: name, kind: kinds[category] ?? "Place", street: item.placemark.thoroughfare)
        }
    }

    private static let kinds: [MKPointOfInterestCategory: String] = [
        .restaurant: "Restaurant", .cafe: "Café", .bakery: "Bakery", .brewery: "Brewery", .winery: "Winery",
        .nightlife: "Bar", .park: "Park", .nationalPark: "Park", .beach: "Beach", .marina: "Marina", .zoo: "Zoo",
        .museum: "Museum", .library: "Library", .theater: "Theater", .movieTheater: "Cinema", .stadium: "Stadium",
        .university: "College",
    ]

    private static func placemark(at point: CLLocationCoordinate2D) async -> CLPlacemark? {
        try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: point.latitude, longitude: point.longitude)).first
    }
}
