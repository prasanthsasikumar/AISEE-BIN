import CoreVideo
import UIKit
import XCTest
@testable import AISEEBIN

@MainActor
final class AskServiceTests: XCTestCase {

    private func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        return buffer!
    }

    private func context(jpeg: Data? = nil) -> AskService.Context {
        AskService.Context(jpeg: jpeg, mapSlug: "m", places: [], venueInfo: nil,
                           audience: "nonsighted", camera: "glasses", venue: "AHLab")
    }

    // MARK: - Picture

    func testGlassesAreThePictureSourceOnlyWhenTheyPositionAndAreConnected() {
        XCTAssertEqual(AskPicture.source(positioning: .glasses, glassesConnected: true), .glasses)
        XCTAssertEqual(AskPicture.source(positioning: .lanyard, glassesConnected: true), .glasses)
        XCTAssertEqual(AskPicture.source(positioning: .glasses, glassesConnected: false), .phone)
        XCTAssertEqual(AskPicture.source(positioning: .phone, glassesConnected: true), .phone)
    }

    func testGlassesPictureIsShrunkToTheQuestionSize() throws {
        let data = try XCTUnwrap(AskPicture.jpeg(source: .glasses, glassesFrame: pixelBuffer(width: 720, height: 1280),
                                                 frameAge: 0, phone: { nil }))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(image.size.width, image.size.height) * image.scale, 768, accuracy: 1)
        XCTAssertLessThan(image.size.width, image.size.height, "a portrait frame stays portrait")
    }

    func testNoGlassesFrameYetMeansNoPictureRatherThanThePocket() {
        let phone = Data([1, 2, 3])
        XCTAssertNil(AskPicture.jpeg(source: .glasses, glassesFrame: nil, frameAge: 0, phone: { phone }))
        XCTAssertEqual(AskPicture.jpeg(source: .phone, glassesFrame: nil, frameAge: 0, phone: { phone }), phone)
    }

    func testAStaleGlassesFrameIsNotSentAsWhatTheVisitorIsFacing() {
        let frame = pixelBuffer(width: 720, height: 1280)
        XCTAssertNotNil(AskPicture.jpeg(source: .glasses, glassesFrame: frame, frameAge: 2.9, phone: { nil }))
        XCTAssertNil(AskPicture.jpeg(source: .glasses, glassesFrame: frame, frameAge: 3.1, phone: { nil }))
        XCTAssertNil(AskPicture.jpeg(source: .glasses, glassesFrame: frame, frameAge: .infinity, phone: { nil }))
    }

    // MARK: - Asking

    private func stream(_ chunks: [String], failing: Bool = false) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish(throwing: failing ? ExploreClientError.http(502) : nil)
        }
    }

    func testAQuestionWithoutAPictureIsStillSentAndAnswered() async {
        var spoken: [String] = []
        var asked: [(String, AskService.Context)] = []
        let service = AskService(asker: { question, context, _ in
            asked.append((question, context))
            return self.stream(["It is a cactus. ", "About waist high"])
        }, speak: { text, _ in spoken.append(text) })

        let done = expectation(description: "answered")
        var updates: [AskService.Update] = []
        service.ask(question: "what is this", context: context(jpeg: nil)) { update in
            updates.append(update)
            if case .finished = update { done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 2)

        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(asked[0].0, "what is this")
        XCTAssertNil(asked[0].1.jpeg)
        XCTAssertEqual(asked[0].1.audience, "nonsighted")
        XCTAssertEqual(spoken, ["It is a cactus.", "About waist high"])
        XCTAssertEqual(updates.first, .thinking)
        XCTAssertEqual(updates.last, .finished(answer: "It is a cactus. About waist high"))
        XCTAssertFalse(service.isAnswering)
    }

    func testAFailedAnswerIsSpokenAsAnApology() async {
        var spoken: [(String, Bool)] = []
        let service = AskService(asker: { _, _, _ in self.stream([], failing: true) },
                                 speak: { spoken.append(($0, $1)) })
        let done = expectation(description: "failed")
        service.ask(question: "what is this", context: context()) { if $0 == .failed { done.fulfill() } }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(spoken.map(\.0), [AskService.failureText])
        XCTAssertEqual(spoken.map(\.1), [false], "an apology must not cut off a turn instruction")
    }

    func testAFollowUpCarriesTheEarlierTurn() async {
        var histories: [[AskTurn]] = []
        let service = AskService(asker: { _, _, history in
            histories.append(history)
            return self.stream(["A fern."])
        }, speak: { _, _ in })
        for question in ["what is this", "how old is it"] {
            let done = expectation(description: question)
            service.ask(question: question, context: context()) { if case .finished = $0 { done.fulfill() } }
            await fulfillment(of: [done], timeout: 2)
        }
        XCTAssertEqual(histories[0].count, 0)
        XCTAssertEqual(histories[1].map(\.q), ["what is this"])
    }
}
