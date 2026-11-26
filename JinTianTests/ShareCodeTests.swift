import XCTest

final class ShareCodeTests: XCTestCase {
    func testRoundTripExcludesRecordsAndIdentity() throws {
        let goal = Goal(name: "旅行 🌿", targetCents: 200_000, wheel: WheelConfig(minimumCents: 15, maximumCents: 9999, integersOnly: false, lowPressure: true), records: [DayRecord(day: "2026-11-01", amountCents: 12345, isSaved: true)])
        let code = try XCTUnwrap(ShareCode.encode(goal))
        let result = try XCTUnwrap(ShareCode.decode(code))
        XCTAssertEqual(result.name, goal.name); XCTAssertEqual(result.targetCents, goal.targetCents)
        XCTAssertEqual(result.wheel, goal.wheel); XCTAssertTrue(result.records.isEmpty)
        XCTAssertNotEqual(result.id, goal.id)
    }
    func testMixedTextAndLineBreaksAreAccepted() throws {
        let code = try XCTUnwrap(ShareCode.encode(Goal(name: "旅行")))
        let body = String(code.dropFirst(ShareCode.marker.count).dropLast())
        let folded = stride(from: 0, to: body.count, by: 20).map { offset -> String in
            let start = body.index(body.startIndex, offsetBy: offset)
            let end = body.index(start, offsetBy: min(20, body.count - offset))
            return String(body[start..<end])
        }.joined(separator: "\n ")
        XCTAssertNotNil(ShareCode.decode("hello 中文\n" + ShareCode.marker + folded + "#\n一起存！"))
    }
    func testMalformedVersionRangeAndOversizeAreRejected() throws {
        for text in ["", "#今天存多少#abc", "#今天存多少#?#", "#今天存多少#A#", String(repeating: "x", count: 6001)] { XCTAssertNil(ShareCode.decode(text)) }
        for json in [#"{"v":2,"name":"x","targetCents":100,"wheel":{}}"#,
                     #"{"v":1,"name":"x","targetCents":-1,"wheel":{}}"#,
                     #"{"v":1,"name":"x","targetCents":100,"wheel":{"minimumCents":9000,"maximumCents":100}}"#] {
            XCTAssertNil(ShareCode.decode(try code(json)))
        }
        XCTAssertNil(ShareCode.pack(Data(repeating: 65, count: ShareCode.maxJSONLength + 1)))
        XCTAssertNil(ShareCode.encode(Goal(name: String(repeating: "a", count: 41))))
    }
    func testZlibChecksumAndWireInteroperability() throws {
        let json = Data("hello".utf8)
        let fixture = Data([0x78, 0x9c, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x07, 0x00, 0x06, 0x2c, 0x02, 0x15])
        XCTAssertEqual(ShareCode.unpack(fixture), json)
        let packed = try XCTUnwrap(ShareCode.pack(json))
        XCTAssertEqual(ShareCode.unpack(packed), json)
        var corrupt = packed; corrupt[corrupt.count - 1] ^= 1
        XCTAssertNil(ShareCode.unpack(corrupt))
        XCTAssertNil(ShareCode.unpack(Data(packed.dropLast(4))))
    }
    func testBoundedDecoderRejectsZipBomb() {
        let fixture = Data(base64Encoded: "eJztwQENAAAAwqBs71/KHG5AAQAAAAAAAAAAQPcGh8HrmA==" )
        if let fixture { XCTAssertNil(ShareCode.unpack(fixture)) }
    }
    private func code(_ json: String) throws -> String {
        let packed = try XCTUnwrap(ShareCode.pack(Data(json.utf8)))
        let base = packed.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return ShareCode.marker + base + "#"
    }
}
