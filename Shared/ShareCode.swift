import Foundation
import Compression

enum ShareCode {
    static let marker = "#今天存多少#"
    static let maxTextLength = 6000
    static let maxJSONLength = 4096
    private struct Payload: Codable { var v: Int; var name: String; var targetCents: Int; var wheel: WheelConfig }

    static func encode(_ goal: Goal) -> String? {
        guard goal.wheel.isValid, (0...Money.limit).contains(goal.targetCents), goal.name.count <= 40,
              let json = try? JSONEncoder().encode(Payload(v: 1, name: goal.name, targetCents: goal.targetCents, wheel: goal.wheel)),
              let packed = pack(json) else { return nil }
        let base = packed.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return marker + base + "#"
    }
    static func decode(_ text: String) -> Goal? {
        guard text.count <= maxTextLength, let start = text.range(of: marker) else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.firstIndex(of: "#") else { return nil }
        let raw = rest[..<end].filter { !$0.isWhitespace }
        guard !raw.isEmpty, raw.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }), raw.count % 4 != 1 else { return nil }
        var base = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        guard let packed = Data(base64Encoded: base), let json = unpack(packed),
              let p = try? JSONDecoder().decode(Payload.self, from: json), p.v == 1,
              p.name.count <= 40, (0...Money.limit).contains(p.targetCents), p.wheel.isValid,
              ["mint", "peach", "violet"].contains(p.wheel.theme) else { return nil }
        return Goal(name: p.name, targetCents: p.targetCents, wheel: p.wheel)
    }
    private static func adler(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for v in bytes { a = (a + UInt32(v)) % 65521; b = (b + a) % 65521 }
        return (b << 16) | a
    }
    static func pack(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maxJSONLength else { return nil }
        let source = [UInt8](data)
        var destination = [UInt8](repeating: 0, count: maxJSONLength + 512)
        let capacity = destination.count
        let count = source.withUnsafeBufferPointer { src in
            destination.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, capacity, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0 else { return nil }
        let check = adler(source)
        return Data([0x78, 0x9c] + Array(destination.prefix(count)) + [UInt8((check >> 24) & 255), UInt8((check >> 16) & 255), UInt8((check >> 8) & 255), UInt8(check & 255)])
    }
    static func unpack(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 7, bytes.count <= maxTextLength, bytes[0] & 15 == 8,
              bytes[0] >> 4 <= 7, (Int(bytes[0]) * 256 + Int(bytes[1])) % 31 == 0, bytes[1] & 32 == 0 else { return nil }
        let source = Array(bytes[2..<(bytes.count - 4)])
        var destination = [UInt8](repeating: 0, count: maxJSONLength + 1)
        let capacity = destination.count
        let count = source.withUnsafeBufferPointer { src in
            destination.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, capacity, src.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0, count <= maxJSONLength else { return nil }
        let json = Array(destination.prefix(count)), tail = Array(bytes.suffix(4))
        let check = tail.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard adler(json) == check else { return nil }
        return Data(json)
    }
}
