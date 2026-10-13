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

    /// A phrase can be said again, or begin with all of the one before: it is still a phrase of its own.
    func testAShortPhraseSaidAgainAfterAPauseIsKept() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Go.", endsPhrase: true, span: 0...1)
        XCTAssertEqual(transcript.take("Go.", endsPhrase: true, span: 3...4), "Go. Go.")
        XCTAssertEqual(transcript.take("Go"), "Go. Go. Go")
        XCTAssertEqual(transcript.take("Go now."), "Go. Go. Go now.")
        XCTAssertEqual(transcript.phrases, 3)
    }

    func testALongPhraseSaidAgainLaterIsKept() {
        var transcript = Dictation.Transcript()
        let said = "Make a timer with a big start button."
        _ = transcript.take(said, endsPhrase: true, span: 0...4)
        XCTAssertEqual(transcript.take(said, endsPhrase: true, span: 8...12), said + " " + said)
        XCTAssertEqual(transcript.phrases, 2)
    }

    /// A result without times that looks like the finished phrase sent again, then marked at another time: it
    /// was a new phrase, and the finished one is kept as it was.
    func testALookalikeMarkedLaterDoesntReplaceTheFinishedPhrase() {
        var transcript = Dictation.Transcript()
        let first = "Make a timer with a big start button."
        let second = "Make a timer with a small stop button."
        _ = transcript.take(first, endsPhrase: true, span: 0...4)
        _ = transcript.take(second)
        XCTAssertEqual(transcript.take(second, endsPhrase: true, span: 8...12), first + " " + second)
        XCTAssertEqual(transcript.phrases, 2)
    }

    /// The same, sent again without times and then marked at the same time: the revision stands.
    func testALookalikeMarkedAtTheSameTimeReplacesTheFinishedPhrase() {
        var transcript = Dictation.Transcript()
        let said = "Hi, is this working? I just wanna see if if I'm able to pause."
        let fixed = "Hi, is this working? I just wanna see if I'm able to pause."
        _ = transcript.take(said, endsPhrase: true, span: 0...6)
        _ = transcript.take(fixed)
        XCTAssertEqual(transcript.take(fixed, endsPhrase: true, span: 0...6), fixed)
        XCTAssertEqual(transcript.take("And"), fixed + " And")
        XCTAssertEqual(transcript.phrases, 2)
    }

    /// A correction to a phrase's first word, with no pause, replaces it.
    func testCorrectingTheFirstWordReplacesThePhrase() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Buy a pair of pears")
        XCTAssertEqual(transcript.take("By a pair of pears"), "By a pair of pears")
        XCTAssertEqual(transcript.phrases, 1)
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

    /// Seen dictating: before marking a long phrase finished, the recognizer reworded its middle, which also
    /// made it shorter. That's the same phrase, not a new one.
    func testRewordingALongPhraseReplacesIt() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Really don't know what to say. I'm trying to find out, but do you know what they say here I leave")
        let reworded = "Really don't know what to say. I'm trying to find out but do you know I say here I live"
        XCTAssertEqual(transcript.take(reworded), reworded)
        XCTAssertEqual(transcript.take("All right"), reworded + " All right")
        XCTAssertEqual(transcript.take("Right"), reworded + " Right")
        XCTAssertEqual(transcript.take("Right, can I pause like this?"), reworded + " Right, can I pause like this?")
        XCTAssertEqual(transcript.phrases, 2)
    }

    func testAnEmptyResultLosesNothing() {
        var transcript = Dictation.Transcript()
        _ = transcript.take("Make a timer.", endsPhrase: true)
        XCTAssertEqual(transcript.take(""), "Make a timer.")
        XCTAssertEqual(transcript.take("Make it blue."), "Make a timer. Make it blue.")
    }
}
