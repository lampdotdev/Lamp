import Foundation
import simd

/// A country's driving and signage habits. US by default; another country changes these.
struct RegionStyle: Sendable {
    /// Traffic keeps to the right.
    var drivesOnRight = true
    /// Speeds in mph, distances in feet and miles (else km/h, metres and kilometres).
    var imperial = true
    /// Two-way streets get a double yellow centre line (else double white).
    var yellowCentreLine = true
    /// Street-name blades: background and lettering, 0–1 RGB.
    var signColour: SIMD3<Float> = [0.0, 0.42, 0.22]
    var signInk: SIMD3<Float> = [1, 1, 1]

    static let us = RegionStyle()

    /// The habits of the country with this ISO code (US when unknown).
    static func forCountry(_ code: String?) -> RegionStyle {
        guard let code = code?.uppercased(), code != "US" else { return .us }
        var s = RegionStyle()
        // Where traffic keeps left.
        s.drivesOnRight = !["GB", "IE", "JP", "AU", "NZ", "IN", "ZA", "HK", "MO", "SG", "MY", "TH", "ID", "KE", "UG", "TZ",
                            "PK", "BD", "LK", "NP", "CY", "MT", "JM", "TT", "BS", "BB", "IM", "JE", "GG", "ZW", "ZM", "BW",
                            "NA", "MZ", "MW", "LS", "SZ", "MU", "FJ", "PG", "GY", "SR", "BN", "BT", "TL"].contains(code)
        // Miles an hour on the road signs.
        s.imperial = ["GB", "LR", "MM", "PR", "IM", "JE", "GG", "BS", "BZ"].contains(code)
        // Yellow centre lines: the Americas mostly; white elsewhere.
        s.yellowCentreLine = ["CA", "MX", "PR", "BR", "AR", "CL", "CO", "PE", "VE", "EC", "BO", "UY", "PY", "CR", "PA",
                              "GT", "HN", "SV", "NI", "NO", "FI"].contains(code)
        // Street-name signs: green in North America, else white with dark lettering (or blue where that's usual).
        if code == "CA" { s.signColour = [0.0, 0.42, 0.22] }
        else if ["FR", "IT", "ES", "PT", "BE", "NL", "GR", "TR"].contains(code) { s.signColour = [0.1, 0.25, 0.6] }
        else { s.signColour = [0.95, 0.95, 0.93]; s.signInk = [0.08, 0.08, 0.1] }
        return s
    }

    /// +1 where traffic keeps right, −1 where it keeps left: multiplies offsets from a road's middle line.
    var side: Float { drivesOnRight ? 1 : -1 }
    var speedUnit: String { imperial ? "MPH" : "KM/H" }
    /// Metres a second to the speed shown.
    var speedFactor: Float { imperial ? 2.237 : 3.6 }
}

/// Everything about the place the game is set in. The rest of the game reads the map from OpenStreetMap around
/// `centre`; change `current` to drive somewhere else.
struct CityConfig: Sendable {
    let name: String
    /// Added to address searches, after the city's name ("CA, USA").
    let region: String
    /// The map's centre point: local metres are measured east and north from here.
    let lat: Double, lon: Double
    /// Where the car starts: on the street nearest this point (the centre when nil), facing north along it.
    var start: (lat: Double, lon: Double)? = nil
    /// Half the size of the downtown area built first, in metres east–west and north–south; the rest streams in.
    var downtownHalf: SIMD2<Float> = [960, 730]
    var style: RegionStyle = .us
    /// What the city bus is called.
    var busName = "City Bus"

    /// Where the game is set: the last place travelled to, else downtown San Francisco. Changed only by `Game.travel`, which
    /// then builds the game afresh there.
    nonisolated(unsafe) static var current: CityConfig = (TravelPlace.saved() ?? .sanFrancisco).config

    /// The place's folder name: its name and where it is, so two places of the same name don't share one.
    var slug: String {
        let n = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return n + String(format: "-%.3f_%.3f", lat, lon)
    }

    /// The game's cache for this city (its downtown, map tiles), in Caches.
    var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DriveAnywhere", isDirectory: true).appendingPathComponent(slug, isDirectory: true)
    }
}
