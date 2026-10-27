import EventKit
import Foundation

/// What the page asks of this Mac, iPhone or iPad with `LampNative.call(name, args)` in Web/: the person's own
/// calendars and photos, read with Lamp's building blocks in LampSupport.swift. Each is asked for only when the person
/// turns it on in the page's settings, so the system asks for access then and not as the screen opens.
enum Native {
    @MainActor static func register() {
        // The calendars, for the settings sheet: each with its own id and where it's from, since two can share a name
        // (a "Family" in iCloud and a "Family" subscribed to from Google).
        LampNative.on("calendars") { _ in try await Calendars.list() }

        // Events from a week ago to `days` ahead from the chosen calendars, in the page's shape (js/data.js).
        LampNative.on("events") { args in
            try await Calendars.events(in: args["calendars"] as? [String] ?? [], days: args["days"] as? Int ?? 42)
        }

        // The person's albums with something in them, for the settings sheet.
        LampNative.on("albums") { _ in
            guard try await LampPhotos.authorize() else { throw Refused() }
            return try await LampPhotos.albums().filter { $0.count > 0 }.map { ["id": $0.id, "title": $0.title, "count": String($0.count)] }
        }

        // Pictures from one album (Favorites unless named), newest first, each a JPEG small enough for a screen across
        // the room and to send on to the screen's other copies (js/sync.js), with the date and whether it's tall.
        LampNative.on("photos") { args in
            guard try await LampPhotos.authorize() else { throw Refused() }
            let limit = min(args["limit"] as? Int ?? 24, 40)
            let album = try await LampPhotos.albums().first { $0.id == args["album"] as? String }
            let found = if let album { try await LampPhotos.photos(in: album, limit: limit * 2) } else { try await LampPhotos.favorites(limit: limit * 2) }
            let photos = found.filter { !$0.isVideo }.prefix(limit)
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            var out: [[String: String]] = []
            for photo in photos {
                guard let image = await LampPhotos.image(photo, size: 1280), let cg = image.lampCGImage,
                      let jpeg = LampImage.lampJPEG(cg, quality: 0.72) else { continue }
                out.append(["id": photo.id, "src": "data:image/jpeg;base64," + jpeg.base64EncodedString(),
                            "o": photo.height > photo.width ? "p" : "l", "date": photo.date.map(day.string(from:)) ?? "",
                            "fav": photo.isFavorite ? "1" : ""])
            }
            return out
        }
    }

    struct Refused: LocalizedError {
        var errorDescription: String? { "Photos isn't allowed." }
    }
}

/// The person's calendars, read with EventKit off the main thread: EventKit waits on the system's calendar service, which
/// holds it while it asks for access. Calendars are chosen by their identifier; a name saved by an earlier version still
/// finds its calendar.
enum Calendars {
    nonisolated(unsafe) private static let store = EKEventStore()

    private static func authorize() async throws {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return }
        guard try await store.requestFullAccessToEvents() else { throw Refused(what: "Calendars") }
    }

    static func list() async throws -> [[String: String]] {
        try await authorize()
        return await Task.detached {
            store.calendars(for: .event).map { ["id": $0.calendarIdentifier, "title": $0.title, "source": $0.source?.title ?? ""] }
        }.value
    }

    static func events(in chosen: [String], days: Int) async throws -> [[String: String]] {
        try await authorize()
        return await Task.detached {
            // [] (saved by an earlier version) is every calendar; otherwise the ones chosen, and none when nothing matches.
            let all = store.calendars(for: .event)
            let calendars = chosen.isEmpty ? all : all.filter { chosen.contains($0.calendarIdentifier) || chosen.contains($0.title) }
            guard !calendars.isEmpty else { return [] }
            let now = Date()
            let from = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: now)) ?? now
            let to = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
            let iso = ISO8601DateFormatter()
            return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: calendars))
                .sorted { $0.startDate < $1.startDate }
                .map { e in
                    ["id": e.eventIdentifier ?? UUID().uuidString, "title": e.title ?? "", "start": iso.string(from: e.startDate),
                     "end": iso.string(from: e.endDate), "allDay": e.isAllDay ? "1" : "", "loc": e.location ?? "", "notes": e.notes ?? "",
                     "calendar": e.calendar.title]
                }
        }.value
    }

    struct Refused: LocalizedError {
        let what: String
        var errorDescription: String? { "\(what) isn't allowed." }
    }
}

