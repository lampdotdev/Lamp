import XCTest
@testable import Lamp

/// After a pause, recognition on the Mac starts over and reports only the words since the pause. What was said
/// before stays in the prompt box rather than being replaced by the newest phrase.
final class DictationTranscriptTests: XCTestCase {
    func testAPauseKeepsWhatWasSaidBeforeIt() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Make a timer")
        XCTAssertEqual(transcript.take("Make a timer with a big start button."), "Make a timer with a big start button.")
        // The pause: the next result holds only the new words.
        XCTAssertEqual(transcript.take("It"), "Make a timer with a big start button. It")
        // The recognizer marks the end of a phrase: the next one is new however it starts.
        XCTAssertEqual(transcript.take("It should beep at the end.", endsPhrase: true),
                       "Make a timer with a big start button. It should beep at the end.")
        XCTAssertEqual(transcript.take("It should be red."),
                       "Make a timer with a big start button. It should beep at the end. It should be red.")
        // Each phrase is its own Undo step in the message box.
        XCTAssertEqual(transcript.phrases, 3)
    }

    func testRevisingAPhraseReplacesItInsteadOfRepeatingIt() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Make a timer that rings for ever")
        XCTAssertEqual(transcript.take("Make a timer that rings forever"), "Make a timer that rings forever")
        XCTAssertEqual(transcript.take("Make a time"), "Make a time")
        XCTAssertEqual(transcript.phrases, 1)
    }

    func testAMarkedPhraseTheRecognizerCarriesOnIsntRepeated() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Make a timer.", endsPhrase: true)
        XCTAssertEqual(transcript.take("Make a timer. Make it blue."), "Make a timer. Make it blue.")
    }

    func testAnEmptyResultLosesNothing() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Make a timer.", endsPhrase: true)
        XCTAssertEqual(transcript.take(""), "Make a timer.")
        XCTAssertEqual(transcript.take("Make it blue."), "Make a timer. Make it blue.")
    }
}
