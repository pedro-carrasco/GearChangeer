import Foundation

/// OpenBikeControl protocol constants (https://openbikecontrol.org).
public enum OpenBikeControlSpec {
    public static let mdnsServiceType = "_openbikecontrol._tcp"
    public static let protocolVersion = "1"

    public static let serviceUUID = "d273f680-d548-419d-b9d1-fa0472345229"
    public static let buttonStateCharacteristicUUID = "d273f681-d548-419d-b9d1-fa0472345229"
    public static let hapticFeedbackCharacteristicUUID = "d273f682-d548-419d-b9d1-fa0472345229"
    public static let appInfoCharacteristicUUID = "d273f683-d548-419d-b9d1-fa0472345229"
}

public enum OpenBikeControlMessageType: UInt8, Sendable {
    case buttonState = 0x01
    case deviceStatus = 0x02
    case hapticFeedback = 0x03
    case appInfo = 0x04
}

/// Standard OpenBikeControl Button IDs (drivetrain/shifting range 0x01..0x0F).
public enum OpenBikeControlButton: UInt8, Sendable, Equatable {
    case shiftUp = 0x01
    case shiftDown = 0x02

    public static func from(_ action: ShiftAction) -> OpenBikeControlButton {
        switch action {
        case .shiftUp: return .shiftUp
        case .shiftDown: return .shiftDown
        }
    }
}

public enum OpenBikeControlButtonState: UInt8, Sendable, Equatable {
    case released = 0x00
    case pressed = 0x01
}

public enum OpenBikeControlConnectionState: UInt8, Sendable, Equatable {
    case disconnected = 0x00
    case connectedReady = 0x01
}

public struct OpenBikeControlDeviceMetadata: Sendable, Equatable {
    public let id: String
    public let name: String
    public let manufacturer: String
    public let model: String

    public init(
        id: String = "gearchanger-vs200",
        name: String = "GearChanger VS200",
        manufacturer: String = "GearChanger",
        model: String = "ThinkRider VS200 Bridge"
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
    }

    public var txtRecordDictionary: [String: String] {
        [
            "version": OpenBikeControlSpec.protocolVersion,
            "id": id,
            "name": name,
            "manufacturer": manufacturer,
            "model": model,
            "service-uuids": OpenBikeControlSpec.serviceUUID
        ]
    }
}

/// Encodes and inspects OpenBikeControl binary messages shared across TCP and BLE transports.
public struct OpenBikeControlCodec: Sendable {
    public init() {}

    /// Encodes a Button State message: [0x01, buttonId, state]
    public func encodeButtonState(
        button: OpenBikeControlButton,
        state: OpenBikeControlButtonState
    ) -> Data {
        Data([
            OpenBikeControlMessageType.buttonState.rawValue,
            button.rawValue,
            state.rawValue
        ])
    }

    /// Encodes multiple button state pairs in a single packet: [0x01, id1, state1, id2, state2, ...]
    public func encodeButtonStates(
        _ states: [(OpenBikeControlButton, OpenBikeControlButtonState)]
    ) -> Data {
        var bytes: [UInt8] = [OpenBikeControlMessageType.buttonState.rawValue]
        bytes.reserveCapacity(1 + states.count * 2)
        for (button, state) in states {
            bytes.append(button.rawValue)
            bytes.append(state.rawValue)
        }
        return Data(bytes)
    }

    /// Encodes a Device Status message: [0x02, batteryLevel (0..100), connectionState]
    public func encodeDeviceStatus(
        batteryLevel: UInt8,
        connectionState: OpenBikeControlConnectionState
    ) -> Data {
        let clampedBattery = min(batteryLevel, 100)
        return Data([
            OpenBikeControlMessageType.deviceStatus.rawValue,
            clampedBattery,
            connectionState.rawValue
        ])
    }
}
