import Foundation

/// What the list holds before the person lets Backpack read their Mail: a made-up family's week at Oakwood
/// Elementary, dated from the first launch so it always looks current. Each is marked `isExample`, and they go
/// when Backpack first reads the inbox or when the person clears them.
enum Examples {
    static func addOnce(to todos: LampStore.Collection<Todo>) {
        guard LampStore.load(Bool.self, from: "examplesAdded") != true else { return }
        LampStore.save(true, to: "examplesAdded")
        todos.put(make(from: .now))
    }

    static func make(from now: Date) -> [Todo] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int? = nil, _ minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            guard let hour else { return date }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
        }
        let alvarez = "Ms. Alvarez <alvarez@oakwood.example.org>"
        let chen = "Mr. Chen <chen@oakwood.example.org>"
        let office = "Oakwood Elementary <office@oakwood.example.org>"
        let pta = "Oakwood PTA <pta@oakwood.example.org>"
        let field = "Aquarium field trip next week!"
        return [
            Todo(title: "Return library books", kind: .bring, due: day(-1), child: "Leo", from: chen,
                 subject: "Library day reminder", received: day(-6),
                 quote: "Library books are due back next week so everyone can check out new ones."),
            Todo(title: "Sign the aquarium field trip form", kind: .form, due: day(2), child: "Maya", from: alvarez,
                 subject: field, received: day(-3),
                 quote: "Please sign and return the permission slip before the trip."),
            Todo(title: "Send $12 for the aquarium trip", kind: .pay, due: day(2), child: "Maya", from: alvarez,
                 subject: field, received: day(-3),
                 quote: "The trip costs $12, which covers the bus and entry. Cash or check is fine."),
            Todo(title: "Pajama day", kind: .event, due: day(4), child: "Leo", from: chen,
                 subject: "Pajama day is coming", received: day(-2),
                 quote: "It's pajama day soon! Kids can wear their comfiest PJs and bring a stuffed animal."),
            Todo(title: "Bring a family photo", kind: .bring, due: day(6), child: "Leo", from: chen,
                 subject: "All About Me board", received: day(-2),
                 quote: "Please send in one family photo for our All About Me board. We'll send it home in June."),
            Todo(title: "Book a parent–teacher conference", kind: .task, due: day(9), child: "Maya", from: office,
                 subject: "Conference sign-ups are open", received: day(-1),
                 quote: "Sign up for a 15-minute conference slot online before slots fill up."),
            Todo(title: "Early dismissal at 12:30", kind: .event, due: day(12, 12, 30), hasTime: true, from: office,
                 subject: "Early dismissal for staff training", received: day(-1),
                 quote: "School will dismiss at 12:30 PM for staff training. After-care is open as usual."),
            Todo(title: "Volunteer for the book fair", kind: .task, from: pta,
                 subject: "Book fair helpers wanted", received: day(-4),
                 quote: "We need a few more helpers for the book fair. Even one hour makes a difference!"),
            Todo(title: "Order school pictures", kind: .pay, due: day(-2), child: "Maya", from: office,
                 subject: "Picture day photos are ready", received: day(-9),
                 quote: "Picture packages can be ordered online for a few more days.", done: day(-3, 20, 15)),
        ].map { todo in
            var todo = todo
            todo.isExample = true
            return todo
        }
    }
}
