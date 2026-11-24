import CoreBluetooth
import Foundation
import GearChangerCore

public struct ThinkRiderBLEConfiguration: Sendable {
    public let namePrefix: String
    public let targetCharacteristicUUID: String?
    public let scanOnly: Bool
    public let logRawPackets: Bool

    public init(
        namePrefix: String = "Think VS",
        targetCharacteristicUUID: String? = nil,
        scanOnly: Bool = false,
        logRawPackets: Bool = false
    ) {
        self.namePrefix = namePrefix
        self.targetCharacteristicUUID = targetCharacteristicUUID?.lowercased()
        self.scanOnly = scanOnly
        self.logRawPackets = logRawPackets
    }
}

public enum BLEConnectionStatus: Sendable, Equatable {
    case idle
    case bluetoothOff
    case unauthorized
    case unsupported
    case scanning
    case connecting(String)
    case connected(String)
}

/// CoreBluetooth input adapter for the ThinkRider VS200 virtual shifter.
///
/// Runs all CoreBluetooth delegate callbacks on a dedicated serial DispatchQueue.
public final class ThinkRiderBLEAdapter: NSObject, ShiftInputPort, @unchecked Sendable {
    public let events: AsyncStream<ShiftEvent>

    private let continuation: AsyncStream<ShiftEvent>.Continuation
    private let config: ThinkRiderBLEConfiguration
    private let decoder = ThinkRiderVS200Decoder()
    private let logger: any LoggerPort
    private let onStatusChange: (@Sendable (BLEConnectionStatus) -> Void)?
    private let queue = DispatchQueue(label: "com.gearchanger.ble.central")

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var discoveredPeripherals: [UUID: String] = [:]
    private var isStopped = false

    public init(
        config: ThinkRiderBLEConfiguration = ThinkRiderBLEConfiguration(),
        logger: any LoggerPort = ConsoleLogger(),
        onStatusChange: (@Sendable (BLEConnectionStatus) -> Void)? = nil
    ) {
        self.config = config
        self.logger = logger
        self.onStatusChange = onStatusChange
        var capturedContinuation: AsyncStream<ShiftEvent>.Continuation!
        self.events = AsyncStream<ShiftEvent> { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
        super.init()
    }

    public func start() async throws {
        queue.sync {
            self.isStopped = false
            self.discoveredPeripherals.removeAll()
            self.centralManager = CBCentralManager(delegate: self, queue: self.queue)
        }
        logger.info("BLE adapter initialized. Waiting for Bluetooth to power on...")
    }

    public func stop() async {
        queue.sync {
            self.isStopped = true
            self.centralManager?.stopScan()
            if let peripheral = self.connectedPeripheral {
                self.centralManager?.cancelPeripheralConnection(peripheral)
            }
            self.connectedPeripheral = nil
            self.centralManager = nil
            self.onStatusChange?(.idle)
        }
        continuation.finish()
        logger.info("BLE adapter stopped.")
    }

    public func reconnect() {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            if let peripheral = self.connectedPeripheral {
                self.centralManager?.cancelPeripheralConnection(peripheral)
                self.connectedPeripheral = nil
            }
            self.centralManager?.stopScan()
            self.beginScanning()
        }
    }

    private func beginScanning() {
        guard !isStopped, let central = centralManager, central.state == .poweredOn else { return }
        onStatusChange?(.scanning)
        if config.scanOnly {
            logger.info("Scanning for nearby BLE devices (looking for prefix '\(config.namePrefix)')...")
        } else {
            logger.info("Scanning for ThinkRider VS200 (name prefix '\(config.namePrefix)')...")
        }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

extension ThinkRiderBLEAdapter: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.info("Bluetooth powered ON.")
            beginScanning()
        case .poweredOff:
            onStatusChange?(.bluetoothOff)
            logger.warning("Bluetooth is powered OFF. Please enable Bluetooth in macOS Settings.")
        case .unauthorized:
            onStatusChange?(.unauthorized)
            logger.error("Bluetooth permission denied. Grant Bluetooth access to your terminal in System Settings > Privacy & Security > Bluetooth.")
        case .unsupported:
            onStatusChange?(.unsupported)
            logger.error("Bluetooth Low Energy is not supported on this hardware.")
        case .resetting:
            onStatusChange?(.idle)
            logger.warning("Bluetooth is resetting...")
        case .unknown:
            logger.debug("Bluetooth state unknown...")
        @unknown default:
            logger.warning("Unhandled Bluetooth state: \(central.state.rawValue)")
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? ""

        if config.scanOnly {
            if !localName.isEmpty && discoveredPeripherals[peripheral.identifier] == nil {
                discoveredPeripherals[peripheral.identifier] = localName
                let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
                    .map(\.uuidString)
                    .joined(separator: ", ") ?? "none"
                logger.info("Found BLE device: '\(localName)' | id=\(peripheral.identifier.uuidString) | RSSI=\(RSSI) | services=[\(serviceUUIDs)]")
            }
        }

        let matchesPrefix = !localName.isEmpty && localName.localizedCaseInsensitiveContains(config.namePrefix)
        guard matchesPrefix else { return }

        if config.scanOnly {
            logger.info("Matched target device '\(localName)'! Connecting to inspect GATT services & live packets...")
        } else {
            logger.info("Found ThinkRider device '\(localName)' (RSSI: \(RSSI)). Connecting...")
        }

        onStatusChange?(.connecting(localName))
        central.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? peripheral.identifier.uuidString
        onStatusChange?(.connected(name))
        logger.info("Connected to '\(name)'. Discovering GATT services...")
        peripheral.discoverServices(nil)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        logger.error("Failed to connect to \(peripheral.name ?? peripheral.identifier.uuidString): \(error?.localizedDescription ?? "unknown error")")
        connectedPeripheral = nil
        if !isStopped {
            queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.beginScanning()
            }
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        let name = peripheral.name ?? peripheral.identifier.uuidString
        if let error {
            logger.warning("Disconnected from '\(name)' (\(error.localizedDescription)). Reconnecting...")
        } else {
            logger.info("Disconnected from '\(name)'.")
        }
        connectedPeripheral = nil
        if !isStopped {
            queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.beginScanning()
            }
        }
    }
}

extension ThinkRiderBLEAdapter: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            logger.error("Error discovering services: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            logger.warning("No GATT services discovered on \(peripheral.name ?? "device").")
            return
        }

        for service in services {
            logger.debug("Discovered service: \(service.uuid.uuidString)")
            if config.scanOnly {
                logger.info("  GATT Service: \(service.uuid.uuidString)")
            }
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        if let error {
            logger.error("Error discovering characteristics for \(service.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            let uuid = characteristic.uuid.uuidString
            let props = describeProperties(characteristic.properties)
            if config.scanOnly {
                logger.info("    Characteristic: \(uuid) [\(props)] (service \(service.uuid.uuidString))")
            } else {
                logger.debug("Characteristic: \(uuid) [\(props)]")
            }

            let canNotify = characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
            guard canNotify else { continue }

            if let target = config.targetCharacteristicUUID,
               uuid.lowercased() != target
            {
                continue
            }

            logger.info("Subscribing to notifications on characteristic \(uuid)...")
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            logger.error("Failed to subscribe to \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        if characteristic.isNotifying {
            logger.info("Listening for shifts on characteristic \(characteristic.uuid.uuidString).")
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        if let error {
            logger.error("Notification error on \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value, !data.isEmpty else { return }

        if config.scanOnly || config.logRawPackets {
            logger.info("RX [\(characteristic.uuid.uuidString)] (\(data.count)B): \(data.hexString)")
        } else {
            logger.debug("RX [\(characteristic.uuid.uuidString)]: \(data.hexString)")
        }

        switch decoder.decode(data) {
        case .shift(let action):
            continuation.yield(ShiftEvent(action: action, rawPayload: data))
        case .invalidChecksum(let expected, let actual):
            logger.warning(
                "Invalid VS200 checksum on \(data.hexString) (expected 0x\(String(format: "%02x", expected)), got 0x\(String(format: "%02x", actual)))"
            )
        case .unknownFrame:
            if config.scanOnly || config.logRawPackets {
                logger.debug("Unrecognized frame: \(data.hexString)")
            }
        }
    }

    private func describeProperties(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.writeWithoutResponse) { names.append("writeNoResp") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        return names.joined(separator: ",")
    }
}
