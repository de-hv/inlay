import Foundation

extension JSONEncoder {
    public static var inlayDefault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        return encoder
    }

    public func encodeToString(_ value: Encodable) -> String? {
        guard let data = try? encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
