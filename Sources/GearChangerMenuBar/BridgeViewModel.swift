import Foundation
import GearChangerAdapters
import GearChangerCore
import Observation

@MainActor
@Observable
final class BridgeViewModel {
    private(set) var isRunning = false
    private(set) var bleStatus: BLEConnectionStatus = .idle
    private(set) var batteryLevel: UInt8?
    private(set) var serverStatus: OpenBikeControlServerStatus = .stopped
    private(set) var lastShift: ShiftEvent?
    private(set) var shiftCount: Int = 0
    private(set) var errorMessage: String?

    private var bleAdapter: ThinkRiderBLEAdapter?
    private var tcpServer: OpenBikeControlTCPServer?
    private var bridge: ShiftBridge?

    var menuBarIconName: String {
        guard isRunning else { return "bicycle" }
        switch (bleStatus, serverStatus) {
        case (.connected, .listening(_, let clients)) where clients > 0:
            return "bicycle.circle.fill"
        case (.connected, _):
            return "bicycle.circle"
        default:
            return "bicycle"
        }
    }

    var bleStatusTitle: String {
        switch bleStatus {
        case .idle: return L10n.string("ble.status.idle")
        case .bluetoothOff: return L10n.string("ble.status.bluetooth_off")
        case .unauthorized: return L10n.string("ble.status.unauthorized")
        case .unsupported: return L10n.string("ble.status.unsupported")
        case .scanning: return L10n.string("ble.status.scanning")
        case .connecting(let name): return L10n.format("ble.status.connecting", name)
        case .connected(let name): return L10n.format("ble.status.connected", name)
        }
    }

    var bleStatusIsConnected: Bool {
        if case .connected = bleStatus { return true }
        return false
    }

    var batteryIconName: String {
        guard let level = batteryLevel else { return "battery.0percent" }
        switch level {
        case 88...100: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    var serverStatusTitle: String {
        switch serverStatus {
        case .stopped:
            return L10n.string("server.status.stopped")
        case .listening(let port, let clients):
            if clients == 1 {
                return L10n.format("server.status.connected.one", UInt32(port))
            } else if clients > 1 {
                return L10n.format("server.status.connected.many", clients, UInt32(port))
            }
            return L10n.format("server.status.waiting", UInt32(port))
        case .failed(let reason):
            return L10n.format("server.status.failed", reason)
        }
    }

    var serverHasClients: Bool {
        if case .listening(_, let clients) = serverStatus { return clients > 0 }
        return false
    }

    func start() async {
        guard !isRunning else { return }
        errorMessage = nil

        let logger = ConsoleLogger(verbose: false)

        let server = OpenBikeControlTCPServer(logger: logger) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.serverStatus = status
            }
        }

        let ble = ThinkRiderBLEAdapter(
            config: ThinkRiderBLEConfiguration(namePrefix: "Think VS"),
            logger: logger,
            onStatusChange: { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.bleStatus = status
                }
            },
            onBatteryLevelChange: { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.batteryLevel = level
                }
                if let level {
                    Task {
                        await server.sendDeviceStatus(batteryLevel: level, connectionState: .connectedReady)
                    }
                }
            }
        )

        let shiftBridge = ShiftBridge(
            input: ble,
            output: server,
            logger: logger
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.lastShift = event
                self?.shiftCount += 1
            }
        }

        self.bleAdapter = ble
        self.tcpServer = server
        self.bridge = shiftBridge

        do {
            try await shiftBridge.start()
            isRunning = true
        } catch {
            errorMessage = error.localizedDescription
            await shiftBridge.stop()
            self.bleAdapter = nil
            self.tcpServer = nil
            self.bridge = nil
            isRunning = false
        }
    }

    func stop() async {
        guard let bridge else { return }
        await bridge.stop()
        self.bridge = nil
        self.bleAdapter = nil
        self.tcpServer = nil
        self.isRunning = false
        self.bleStatus = .idle
        self.batteryLevel = nil
        self.serverStatus = .stopped
    }

    func reconnectBLE() {
        bleAdapter?.reconnect()
    }

    func simulateShift(_ action: ShiftAction) async {
        guard let bridge else { return }
        await bridge.handle(ShiftEvent(action: action))
    }
}
