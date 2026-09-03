import Foundation

/// One coder configuration, used for both on-disk storage and watch transfer,
/// so a value written by one process always decodes in the other.
extension JSONEncoder {
    static var walkArrow: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var walkArrow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
