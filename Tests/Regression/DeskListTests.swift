import XCTest
@testable import Lamp

final class DeskListTests: XCTestCase {
    private func wish(_ name: String) -> LampProject {
        LampProject(id: name.lowercased(), name: name, exe: name, dir: URL(fileURLWithPath: "/tmp/\(name)"))
    }

    private func entry(_ project: LampProject, identity: String? = nil, original: String? = nil, starter: Bool = false,
                       author: String? = nil, changed: TimeInterval = 0) -> DeskEntry {
        DeskEntry(id: project.id, author: author, isStarter: starter, arrived: starter || original != nil,
                  changed: Date(timeIntervalSince1970: changed), identity: identity, original: original)
    }

    /// A remix made here comes right after its original, whatever the sort puts between them, and says it's the person's.
    func testRemixesSitUnderTheirOriginal() {
        let york = wish("New York"), snowy = wish("Snowy"), buzzer = wish("Buzzer")
        let entries = [york.id: entry(york, identity: "A", starter: true, author: "Mr.doob"),
                       snowy.id: entry(snowy, identity: "B", original: "A"),
                       buzzer.id: entry(buzzer, starter: true)]
        let rows = DeskList.rows([snowy, buzzer, york], entries: entries, by: .name, ascending: true)
        XCTAssertEqual(rows.map(\.id), ["buzzer", "new york", "snowy"])
        XCTAssertEqual(rows.map(\.nested), [false, false, true])
        XCTAssertEqual(rows.map(\.madeBy), ["Lamp", "Mr.doob", "You"])
    }

    /// Sorting by when they changed puts the latest first, and a remix still follows its original.
    func testSortingByChangedKeepsRemixesWithTheirOriginal() {
        let a = wish("A"), b = wish("B"), c = wish("C")
        let entries = [a.id: entry(a, identity: "1", changed: 10), b.id: entry(b, changed: 20), c.id: entry(c, original: "1", changed: 30)]
        let rows = DeskList.rows([a, b, c], entries: entries, by: .changed, ascending: false)
        XCTAssertEqual(rows.map(\.id), ["b", "a", "c"])
    }

    /// A wish whose original isn't on this desk came from someone else; one with no chain was made here.
    func testWhoMadeIt() {
        let shared = wish("Shared"), mine = wish("Mine")
        let entries = [shared.id: entry(shared, original: "elsewhere"), mine.id: entry(mine)]
        let rows = DeskList.rows([shared, mine], entries: entries, by: .name, ascending: true)
        XCTAssertEqual(rows.map(\.madeBy), ["You", "Shared"])
    }
}
