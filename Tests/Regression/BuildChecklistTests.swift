import XCTest
@testable import Lamp

final class BuildChecklistTests: XCTestCase {
    /// A plan a model gave for a new app, and the files it then wrote, in order: it listed Store.swift for the
    /// first part and put that code in Models.swift instead. The list must fill from the top, never showing a
    /// ticked part under one left unticked, which reads as a step skipped.
    func testTheListFillsFromTheTopWhenAListedFileGoesElsewhere() {
        var progress = TurnProgress(newApp: true)
        progress.plan = [
            PlanPart(id: 0, title: "Saved garden data", done: false, files: ["Models.swift", "Store.swift"]),
            PlanPart(id: 1, title: "Browse plants by season", done: false, files: ["PlantData.swift", "PlantsView.swift"]),
            PlanPart(id: 2, title: "Lay out beds on a grid", done: false, files: ["BedsView.swift"]),
            PlanPart(id: 3, title: "Watering, harvests and seeds", done: false,
                     files: ["WateringView.swift", "HarvestView.swift", "SeedsView.swift"]),
            PlanPart(id: 4, title: "Main window", done: false, files: ["ContentView.swift", "App.swift"]),
        ]
        for file in ["Models.swift", "PlantData.swift", "PlantsView.swift", "BedsView.swift", "WateringView.swift",
                     "HarvestView.swift", "SeedsView.swift", "ContentView.swift", "App.swift"] {
            progress.wrote(file)
            let ticks = progress.plan.map(\.done)
            XCTAssertFalse(zip(ticks, ticks.dropFirst()).contains { !$0 && $1 }, "after \(file): \(ticks)")
        }
        XCTAssertTrue(progress.plan.allSatisfy(\.done))
    }

    /// Another such plan, whose last part listed App.swift, which the model never rewrote. Once Lamp is
    /// building, that part must not sit unticked above Lamp's own row for building and opening.
    func testTheLastPartIsDoneOnceLampBuilds() {
        var progress = TurnProgress(newApp: true)
        progress.plan = [
            PlanPart(id: 0, title: "Saved garden data", done: false, files: ["Models.swift", "GardenStore.swift"]),
            PlanPart(id: 1, title: "Browse plants by season", done: false, files: ["PlantData.swift", "PlantsView.swift"]),
            PlanPart(id: 2, title: "Lay out beds on a grid", done: false, files: ["BedsView.swift"]),
            PlanPart(id: 3, title: "Watering schedule and harvest log", done: false,
                     files: ["WateringView.swift", "HarvestView.swift"]),
            PlanPart(id: 4, title: "Seed tracker and main window", done: false,
                     files: ["SeedsView.swift", "ContentView.swift", "App.swift"]),
        ]
        for file in ["Models.swift", "GardenStore.swift", "PlantData.swift", "PlantsView.swift", "BedsView.swift",
                     "WateringView.swift", "HarvestView.swift", "SeedsView.swift", "ContentView.swift"] {
            progress.wrote(file)
        }
        progress.activity = "Building…"
        XCTAssertEqual(progress.plan.map { progress.state(of: $0) }, Array(repeating: .done, count: 5))
    }
}
