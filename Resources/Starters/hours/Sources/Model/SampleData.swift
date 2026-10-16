import Foundation

/// Three made-up clients and five weeks of work for them, so the app shows what it does the moment it opens.
/// Written once, on first launch; everything here is marked `isExample`, which is what Clear Examples removes.
enum SampleData {
    private static let flag = "examplesAdded"

    static func addOnce(clients: LampStore.Collection<Client>, entries: LampStore.Collection<TimeEntry>) {
        guard LampStore.load(Bool.self, from: flag) == nil else { return }
        LampStore.save(true, to: flag)
        // Someone who already has clients (data from before this flag existed) gets no examples.
        guard clients.count == 0 else { return }

        let bakery = Client(name: "Crumb & Co. Bakery", rate: 85, currency: "USD", color: "orange", isExample: true)
        let podcast = Client(name: "Night Shift Podcast", rate: 60, currency: "USD", color: "purple", isExample: true)
        let studio = Client(name: "Studio Fern", rate: 95, currency: "EUR", color: "green", isExample: true)

        let notes: [UUID: [String]] = [
            bakery.id: ["Homepage layout", "Menu page with prices", "Online ordering form", "Fixing the mobile menu",
                        "Cake gallery photos", "Launch call with Marta", "Contact form spam fix"],
            podcast.id: ["Episode 41 rough cut", "Episode 41 noise cleanup", "Episode 42 rough cut",
                         "Show notes for episode 42", "Intro music levels", "Episode 42 final mix"],
            studio.id: ["Brand guidelines draft", "Logo refinements", "Business card layout", "Review call",
                        "Icon set for the website", "Spring campaign moodboard"],
        ]
        let rotation = [bakery.id, podcast.id, studio.id, bakery.id, studio.id]
        let lengths: [Double] = [0.75, 1, 1.5, 2, 2.5, 3, 1.25]

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var made: [TimeEntry] = []
        for daysAgo in (0...34).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  !calendar.isDateInWeekend(day) else { continue }
            var hour = 9.0 + Double(daysAgo % 3) * 0.25
            for slot in 0..<(1 + (daysAgo * 7) % 3) {
                let clientID = rotation[(daysAgo + slot) % rotation.count]
                let length = lengths[(daysAgo * 3 + slot) % lengths.count]
                let start = day.addingTimeInterval(hour * 3600)
                let end = start.addingTimeInterval(length * 3600)
                // Nothing in the future: today only has what's already done.
                guard end < .now else { break }
                let pool = notes[clientID] ?? [""]
                let note = pool[(daysAgo + slot * 2) % pool.count]
                made.append(TimeEntry(clientID: clientID, start: start, end: end, note: note, isExample: true))
                hour += length + 0.5
            }
        }
        clients.put([bakery, podcast, studio])
        entries.put(made)
    }
}
