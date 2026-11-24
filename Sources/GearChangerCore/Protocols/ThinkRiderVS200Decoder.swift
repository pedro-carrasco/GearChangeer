import Foundation

/// Decodes raw BLE notification payloads from the ThinkRider VS200 (advertised as "Think VS01-XXXXXXX").
///
/// Known 5-byte frame layout:
///   Byte 0: 0xF3 (header)
///   Byte 1: 0x05 (packet length = 5 bytes)
///   Byte 2: 0x03 (command = shift event)
///   Byte 3: 0x01 = Shift Up, 0x00 = Shift Down
///   Byte 4: 8-bit additive checksum of bytes[0..<4]
///
/// Verified examples:
///   Shift Up:   f3 05 03 01 fc  (0xf3 + 0x05 + 0x03 + 0x01 = 0x1fc -> 0xfc)
///   Shift Down: f3 05 03 00 fb  (0xf3 + 0x05 + 0x03 + 0x00 = 0x1fb -> 0xfb)
public struct ThinkRiderVS200Decoder: Sendable {
    public static let frameHeader: UInt8 = 0xF3
    public static let expectedLength: UInt8 = 0x05
    public static let shiftCommand: UInt8 = 0x03

    public enum DecodeResult: Sendable, Equatable {
        case shift(ShiftAction)
        case invalidChecksum(expected: UInt8, actual: UInt8)
        case unknownFrame(Data)
    }

    public init() {}

    public func decode(_ data: Data) -> DecodeResult {
        let bytes = [UInt8](data)
        guard bytes.count == 5,
              bytes[0] == Self.frameHeader,
              bytes[1] == Self.expectedLength,
              bytes[2] == Self.shiftCommand
        else {
            return .unknownFrame(data)
        }

        let expectedChecksum = Self.checksum(bytes[0..<4])
        guard bytes[4] == expectedChecksum else {
            return .invalidChecksum(expected: expectedChecksum, actual: bytes[4])
        }

        switch bytes[3] {
        case 0x01:
            return .shift(.shiftUp)
        case 0x00:
            return .shift(.shiftDown)
        default:
            return .unknownFrame(data)
        }
    }

    public static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(UInt8(0)) { $0 &+ $1 }
    }
}
