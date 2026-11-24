import Foundation

public enum ShiftAction: String, Sendable, Equatable {
    case shiftUp
    case shiftDown
}

public struct ShiftEvent: Sendable, Equatable {
    public let action: ShiftAction
    public let timestamp: Date
    public let rawPayload: Data?

    public init(action: ShiftAction, timestamp: Date = Date(), rawPayload: Data? = nil) {
        self.action = action
        self.timestamp = timestamp
        self.rawPayload = rawPayload
    }
}

public extension Data {
    /// Returns lowercase space-separated hex representation (e.g. "f3 05 03 01 fc").
    var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    /// Initializes Data from a hex string (spaces optional, e.g. "f3 05 03 01 fc" or "f3050301fc").
    init?(hexString: String) {
        let cleaned = hexString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "0x", with: "")
        guard cleaned.count.isMultiple(of: 2) else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)

        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }
        self.init(bytes)
    }
}
