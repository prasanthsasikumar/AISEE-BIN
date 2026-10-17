import XCTest
@testable import AISEEBIN

final class SentenceSplitTests: XCTestCase {

    func testSplitsWholeSentencesAndKeepsTheRest() {
        let (ready, rest) = ExploreViewModel.splitSentences("That's a baobab. It stores wat")
        XCTAssertEqual(ready, "That's a baobab.")
        XCTAssertEqual(rest, " It stores wat")
    }

    func testNoSentenceEndYet() {
        let (ready, rest) = ExploreViewModel.splitSentences("That's a bao")
        XCTAssertEqual(ready, "")
        XCTAssertEqual(rest, "That's a bao")
    }

    func testDecimalPointIsNotASentenceEnd() {
        XCTAssertEqual(ExploreViewModel.splitSentences("It is 2.5 m tall").ready, "")
    }
}
