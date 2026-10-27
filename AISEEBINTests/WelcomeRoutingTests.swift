import XCTest
@testable import AISEEBIN

/// The welcome screen's talk button: tours go to Explore, places to Navigate.
final class WelcomeRoutingTests: XCTestCase {
    func testTimeAndTourRequestsGoToExplore() {
        for text in ["I have 20 minutes", "about half an hour", "an hour please", "show me around",
                     "plan a tour", "what should I see", "give me the highlights", "10 mins"] {
            XCTAssertTrue(NavigationViewModel.isVisitRequest(text), text)
        }
    }

    func testPlaceAndQuestionRequestsGoToNavigate() {
        for text in ["take me to the orchids", "where am I", "what's nearby", "go to the plant shop",
                     "visitor centre", "repeat"] {
            XCTAssertFalse(NavigationViewModel.isVisitRequest(text), text)
        }
    }
}
