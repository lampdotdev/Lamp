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

    /// Seen dictating: the recognizer marked a phrase finished, then sent it again with a word fixed.
    func testAFinishedPhraseSentAgainRevisedIsntRepeated() {
        var transcript = Dictation.Transcript()
        let said = "Hi, is this working? I just wanna see if if I'm able to pause."
        let fixed = "Hi, is this working? I just wanna see if I'm able to pause."
        _ = transcript.take(said)
        _ = transcript.take(said, endsPhrase: true, span: 0...6)
        XCTAssertEqual(transcript.take(fixed), fixed)
        XCTAssertEqual(transcript.take(fixed, endsPhrase: true, span: 0...6), fixed)
        // The next phrase is still a phrase of its own.
        XCTAssertEqual(transcript.take("And"), fixed + " And")
        XCTAssertEqual(transcript.take("And then more.", endsPhrase: true, span: 8...10), fixed + " And then more.")
        XCTAssertEqual(transcript.phrases, 2)
    }

    func testAFinishedPhraseSentAgainWithItsFirstWordChangedIsKnownByItsTime() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Hi, is this working?", endsPhrase: true, span: 0...2)
        XCTAssertEqual(transcript.take("Hey, is this working?", endsPhrase: true, span: 0...2), "Hey, is this working?")
        XCTAssertEqual(transcript.phrases, 1)
    }

    func testAnEmptyResultLosesNothing() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Make a timer.", endsPhrase: true)
        XCTAssertEqual(transcript.take(""), "Make a timer.")
        XCTAssertEqual(transcript.take("Make it blue."), "Make a timer. Make it blue.")
    }
}
