import Foundation

/// Decodes standard Bluetooth GATT Battery Service (0x180F) / Battery Level (0x2A19) payloads.
///
/// Format: single unsigned 8-bit integer representing battery percentage (0...100).
public struct BLEBatteryLevelDecoder: Sendable {
    public static let batteryServiceUUID = "180F"
    public static let batteryLevelCharacteristicUUID = "2A19"

    public init() {}

    public func decode(_ data: Data) -> UInt8? {
        guard let rawLevel = data.first else { return nil }
        return min(rawLevel, 100)
    }
}
