import AIAgent
import Foundation
import XCTest

final class SSEParserTests: XCTestCase {
    func testSingleDataFrame() {
        var parser = SSEParser()
        let frames = parser.parse(data("data: {\"role\":\"assistant\"}\n\n"))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].jsonData, Data(#"{"role":"assistant"}"#.utf8))
        XCTAssertNil(frames[0].event)
        XCTAssertFalse(parser.isDone)
    }

    func testMultipleFramesInOneChunk() {
        var parser = SSEParser()
        let chunk = "data: one\n\ndata: two\n\ndata: three\n\n"
        let frames = parser.parse(data(chunk))

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.map { String(data: $0.jsonData!, encoding: .utf8) }, ["one", "two", "three"])
    }

    func testFramesSplitAcrossChunkBoundaries() {
        var parser = SSEParser()
        let first = parser.parse(data("data: ch"))
        XCTAssertEqual(first.count, 0)

        let second = parser.parse(data("unk1\n\n"))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(String(data: second[0].jsonData!, encoding: .utf8), "chunk1")
    }

    func testDoneSentinel() {
        var parser = SSEParser()
        let frames = parser.parse(data("data: hello\n\ndata: [DONE]\n\n"))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.jsonData, Data("hello".utf8))
        // After the sentinel the parser's most recent frame is cleared.
        XCTAssertNil(parser.jsonData)
        XCTAssertTrue(parser.isDone)
    }

    func testDoneSentinelSplit() {
        var parser = SSEParser()
        _ = parser.parse(data("data: [DO"))
        XCTAssertFalse(parser.isDone)
        _ = parser.parse(data("NE]\n\n"))
        XCTAssertTrue(parser.isDone)
        XCTAssertNil(parser.jsonData)
    }

    func testMultipleDataFieldsJoinWithNewline() {
        var parser = SSEParser()
        let frames = parser.parse(data("data: line1\ndata: line2\n\n"))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(String(data: frames[0].jsonData!, encoding: .utf8), "line1\nline2")
    }

    func testCRLFLineEndings() {
        var parser = SSEParser()
        let frames = parser.parse(data("data: crlf\r\n\r\n"))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(String(data: frames[0].jsonData!, encoding: .utf8), "crlf")
    }

    func testBadJSONPayloadIsStillCarriedRaw() {
        var parser = SSEParser()
        let frames = parser.parse(data("data: not valid json\n\n"))

        XCTAssertEqual(frames.count, 1)
        // SSEParser transports the payload verbatim; JSON validation is the
        // adapter's job, which surfaces invalidJSON there.
        XCTAssertEqual(String(data: frames[0].jsonData!, encoding: .utf8), "not valid json")
    }

    func testEmptyDataFramesAreSkipped() {
        var parser = SSEParser()
        let frames = parser.parse(data("data:\n\ndata: real\n\n"))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(String(data: frames[0].jsonData!, encoding: .utf8), "real")
    }

    func testEventFieldIsCaptured() {
        var parser = SSEParser()
        let frames = parser.parse(data("event: message\ndata: {}\n\n"))

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].event, "message")
    }

    func testParseFrameAtomic() {
        var parser = SSEParser()
        parser.parseFrame("data: atomic\n\n")

        XCTAssertEqual(parser.jsonData, Data("atomic".utf8))
        XCTAssertFalse(parser.isDone)
    }
}