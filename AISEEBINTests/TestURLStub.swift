import Foundation

/// Answers every request on a `URLSession` built with it as a protocol class:
/// with `stub` set, that status and body; with `stub` nil, a not-connected
/// error, the shape of a phone with no network.
final class TestURLStub: URLProtocol {
    nonisolated(unsafe) static var stub: (status: Int, body: String)?
    nonisolated(unsafe) static var data: (status: Int, body: Data)?
    /// Every URL requested, for asserting on query strings.
    nonisolated(unsafe) static var requests: [URL] = []

    static func reset() { stub = nil; data = nil; requests = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url { Self.requests.append(url) }
        let answer: (status: Int, body: Data)?
        if let data = Self.data { answer = data }
        else if let stub = Self.stub { answer = (stub.status, Data(stub.body.utf8)) }
        else { answer = nil }
        guard let answer else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
