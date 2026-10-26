import Foundation

/// What the page asks of this Mac, iPhone or iPad with `LampNative.call(name, args)` in Web/: the person's own
/// calendars and photos, read with Lamp's building blocks in LampSupport.swift. Each is asked for only when the person
/// turns it on in the page's settings, so the system asks for access then and not as the screen opens.
enum Native {
    @MainActor static func register() {
        // The calendars' names, for the settings sheet.
        LampNative.on("calendars") { _ in try await LampCalendar.calendars() }

        // Events from a week ago to six weeks ahead, in the page's shape (js/data.js): ISO dates, the calendar's name.
        LampNative.on("events") { args in
            let now = Date()
            let from = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: now)) ?? now
            let to = Calendar.current.date(byAdding: .day, value: args["days"] as? Int ?? 42, to: now) ?? now
            let names = args["calendars"] as? [String]
            let iso = ISO8601DateFormatter()
            return try await LampCalendar.events(from: from, to: to, calendars: names?.isEmpty == false ? names : nil).map { event in
                ["id": event.id, "title": event.title, "start": iso.string(from: event.start), "end": iso.string(from: event.end),
                 "allDay": event.isAllDay ? "1" : "", "loc": event.location ?? "", "notes": event.notes ?? "", "calendar": event.calendar]
            }
        }

        // The person's albums with something in them, for the settings sheet.
        LampNative.on("albums") { _ in
            guard try await LampPhotos.authorize() else { throw Refused() }
            return try await LampPhotos.albums().filter { $0.count > 0 }.map { ["id": $0.id, "title": $0.title, "count": String($0.count)] }
        }

        // Pictures from one album (Favorites unless named), newest first, each a JPEG small enough for a screen across
        // the room, with the date and whether it's tall.
        LampNative.on("photos") { args in
            guard try await LampPhotos.authorize() else { throw Refused() }
            let limit = min(args["limit"] as? Int ?? 30, 60)
            let album = try await LampPhotos.albums().first { $0.id == args["album"] as? String }
            let found = if let album { try await LampPhotos.photos(in: album, limit: limit * 2) } else { try await LampPhotos.favorites(limit: limit * 2) }
            let photos = found.filter { !$0.isVideo }.prefix(limit)
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            var out: [[String: String]] = []
            for photo in photos {
                guard let image = await LampPhotos.image(photo, size: 1600), let cg = image.lampCGImage,
                      let jpeg = LampImage.lampJPEG(cg, quality: 0.8) else { continue }
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
