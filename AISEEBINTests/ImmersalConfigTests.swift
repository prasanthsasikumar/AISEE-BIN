import XCTest
@testable import AISEEBIN

/// A build may carry a default token so testers only type map ids; a token
/// typed on the device must still win over it.
final class ImmersalConfigTests: XCTestCase {

    func testTypedTokenWinsOverBundled() {
        XCTAssertEqual(ImmersalConfig.resolveToken(stored: "typed", bundled: "bundled"), "typed")
    }

    func testBundledTokenFillsInWhenNothingTyped() {
        XCTAssertEqual(ImmersalConfig.resolveToken(stored: nil, bundled: "bundled"), "bundled")
        XCTAssertEqual(ImmersalConfig.resolveToken(stored: "", bundled: "bundled"), "bundled")
        XCTAssertEqual(ImmersalConfig.resolveToken(stored: "  \n", bundled: "bundled"), "bundled")
    }

    func testNoTokenAnywhereResolvesEmpty() {
        XCTAssertEqual(ImmersalConfig.resolveToken(stored: nil, bundled: nil), "")
        XCTAssertEqual(ImmersalConfig.resolveToken(stored: " ", bundled: nil), "")
    }

    func testTypedMapIDsWinOverTheDefault() {
        XCTAssertEqual(ImmersalConfig.resolveMapIDsText(stored: "1, 2", bundled: "151658"), "1, 2")
    }

    func testDefaultMapIDsFillInWhenNothingParses() {
        XCTAssertEqual(ImmersalConfig.resolveMapIDsText(stored: nil, bundled: "151658"), "151658")
        XCTAssertEqual(ImmersalConfig.resolveMapIDsText(stored: "", bundled: "151658"), "151658")
        XCTAssertEqual(ImmersalConfig.resolveMapIDsText(stored: "abc", bundled: "151658"), "151658")
        XCTAssertEqual(ImmersalConfig.resolveMapIDsText(stored: "", bundled: ""), "")
    }

    func testTypedTokenIsTrimmed() {
        XCTAssertEqual(ImmersalConfig.resolveToken(stored: " abc \n", bundled: nil), "abc")
    }
}
