import Foundation
import GearChangerAdapters
import GearChangerCore
import Observation

@MainActor
@Observable
final class BridgeViewModel {
    private(set) var isRunning = false
    private(set) var bleStatus: BLEConnectionStatus = .idle
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
        case .idle: return "Detenido"
        case .bluetoothOff: return "Bluetooth apagado"
        case .unauthorized: return "Sin permiso de Bluetooth"
        case .unsupported: return "BLE no soportado"
        case .scanning: return "Buscando ThinkRider VS200..."
        case .connecting(let name): return "Conectando a \(name)..."
        case .connected(let name): return "Conectado (\(name))"
        }
    }

    var bleStatusIsConnected: Bool {
        if case .connected = bleStatus { return true }
        return false
    }

    var serverStatusTitle: String {
        switch serverStatus {
        case .stopped:
            return "Detenido"
        case .listening(let port, let clients):
            if clients > 0 {
                let label = clients == 1 ? "1 cliente conectado" : "\(clients) clientes conectados"
                return "Conectado — \(label) (:\(port))"
            }
            return "Esperando a MyWhoosh (:\(port))"
        case .failed(let reason):
            return "Error: \(reason)"
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

        let ble = ThinkRiderBLEAdapter(
            config: ThinkRiderBLEConfiguration(namePrefix: "Think VS"),
            logger: logger
        ) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.bleStatus = status
            }
        }

        let server = OpenBikeControlTCPServer(logger: logger) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.serverStatus = status
            }
        }

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
