import XCTest
@testable import Lamp

/// A small model that can't work out an answer hands back one of the prompt's examples. Lamp treats that as
/// no answer, so the person sees what they would without the helper, not a title from someone else's app.
@MainActor
final class ParrotedAnswersTests: XCTestCase {
    func testVersionTitleFromThePromptIsNoTitle() {
        let asked = "a tip calculator that splits the bill between friends"
        XCTAssertNil(VersionTitles.title(from: "Added account shortcuts", asked: asked))
        XCTAssertNil(VersionTitles.title(from: "\"added account shortcuts.\"", asked: asked))
        XCTAssertEqual(VersionTitles.title(from: "Added bill splitting", asked: asked), "Added bill splitting")
        XCTAssertEqual(VersionTitles.title(from: "First version", asked: asked), "First version")
    }

    func testVersionTitleStandsWhenThePersonAskedForIt() {
        XCTAssertEqual(VersionTitles.title(from: "Darker sidebar", asked: "make it a darker sidebar please"), "Darker sidebar")
    }

    func testAppNameFromThePromptLeavesTheAppUntitled() {
        let asked = "a tip calculator that splits the bill between friends"
        XCTAssertNil(AppName.name(["name": "Night Shift"], asked: asked))
        XCTAssertNil(AppName.name(["name": "Brew Log", "named_by_user": true], asked: asked))
        XCTAssertEqual(AppName.name(["name": "Tip Split"], asked: asked), "Tip Split")
    }

    func testAppNameStandsWhenThePersonAskedForIt() {
        XCTAssertEqual(AppName.name(["name": "Stopwatch"], asked: "a stopwatch with lap times"), "Stopwatch")
        XCTAssertEqual(AppName.name(["name": "Brew Log", "named_by_user": true], asked: "make me an app called Brew Log"), "Brew Log")
        // Part of a longer word isn't the person saying it.
        XCTAssertNil(AppName.name(["name": "Notes"], asked: "a keynotes timer"))
    }

    func testSuggestionThatIsOnlyFillerIsNoSuggestion() {
        XCTAssertNil(NextStep.normalize("Keep going"))
        XCTAssertNil(NextStep.normalize("\"looks good\""))
        XCTAssertEqual(NextStep.normalize("add rounding to the nearest dollar"), "add rounding to the nearest dollar")
    }

    func testSketchPartFromThePromptIsRecognised() {
        XCTAssertTrue(AppAI.parrots("your habits ticked off daily", examples: AppName.exampleParts))
        XCTAssertFalse(AppAI.parrots("Bill and tip", examples: AppName.exampleParts))
    }
}
