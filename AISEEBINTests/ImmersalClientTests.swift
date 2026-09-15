import XCTest
@testable import AISEEBIN

/// Response handling for `/localizeb64`, stubbed at the URL layer.
///
/// Written after a live request to the real endpoint showed that Immersal
/// returns its reason with an HTTP **400**, not a 200 — so a client that reads
/// the status code first discards exactly the information a field failure needs.
final class ImmersalClientTests: XCTestCase {

    private func client() -> ImmersalClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        var client = ImmersalClient(token: "t", mapIDs: [1, 2])
        client.session = URLSession(configuration: configuration)
        return client
    }

    private func localize(_ client: ImmersalClient) async -> ImmersalLocalizeResult {
        await client.localize(pngData: Data([0x89, 0x50]), fx: 800, fy: 800, ox: 480, oy: 360)
    }

    override func tearDown() {
        StubProtocol.stub = nil
        super.tearDown()
    }

    /// The bug this file exists for.
    func testAuthFailureReportsImmersalsReasonNotTheStatusCode() async {
        StubProtocol.stub = (400, #"{"error":"auth"}"#)
        let result = await localize(client())
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "auth")
    }

    func testMapCountRejectionSurvivesTheSameWay() async {
        StubProtocol.stub = (400, #"{"error":"map count"}"#)
        let result = await localize(client())
        XCTAssertEqual(result.error, "map count")
    }

    func testSuccessfulLocalizationParsesPoseAndMap() async {
        StubProtocol.stub = (200, #"""
        {"error":"none","success":true,"map":4242,
         "px":1.5,"py":0.25,"pz":-3.0,
         "r00":1,"r01":0,"r02":0,"r10":0,"r11":1,"r12":0,"r20":0,"r21":0,"r22":1}
        """#)
        let result = await localize(client())
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.mapID, 4242)
        XCTAssertEqual(result.pose?.px, 1.5)
        XCTAssertEqual(result.pose?.pz, -3.0)
        XCTAssertEqual(result.pose?.r, [1, 0, 0, 0, 1, 0, 0, 0, 1])
    }

    /// "The request was fine, the place was not recognised." Not an error, and it
    /// must never be mistaken for a pose at the origin.
    func testUnrecognisedPlaceIsAFailureWithoutAPose() async {
        StubProtocol.stub = (200, #"{"error":"none","success":false}"#)
        let result = await localize(client())
        XCTAssertFalse(result.success)
        XCTAssertNil(result.pose)
    }

    /// A truncated pose is discarded rather than half-read.
    func testPartialPoseIsRejected() async {
        StubProtocol.stub = (200, #"{"error":"none","success":true,"px":1,"py":2,"pz":3,"r00":1}"#)
        let result = await localize(client())
        XCTAssertFalse(result.success)
        XCTAssertNil(result.pose)
    }

    func testUndecodableBodyKeepsTheStatusCodeForDiagnosis() async {
        StubProtocol.stub = (502, "<html>gateway</html>")
        let result = await localize(client())
        XCTAssertEqual(result.error, "http 502, undecodable body")
    }

    func testTransportFailureIsDistinguishableSoTheFrameCanBeReplayed() async {
        StubProtocol.stub = nil   // makes the stub throw
        let result = await localize(client())
        XCTAssertTrue(ImmersalClient.isTransportFailure(result.error), result.error)
    }
}

/// Answers every request with `stub`, or throws if there is none.
private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var stub: (status: Int, body: String)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
