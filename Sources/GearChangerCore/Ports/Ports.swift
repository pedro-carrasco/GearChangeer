import Foundation

/// Input port: anything capable of producing gear shift events (BLE shifter, keyboard simulator, etc.).
public protocol ShiftInputPort: Sendable {
    var events: AsyncStream<ShiftEvent> { get }
    func start() async throws
    func stop() async
}

/// Output port: anything capable of transmitting OpenBikeControl messages to a cycling app (TCP/mDNS, BLE, mock).
public protocol BikeControlOutputPort: Sendable {
    func start() async throws
    func stop() async
    func sendButtonState(button: OpenBikeControlButton, state: OpenBikeControlButtonState) async
    func sendDeviceStatus(batteryLevel: UInt8, connectionState: OpenBikeControlConnectionState) async
}

public protocol LoggerPort: Sendable {
    func info(_ message: String)
    func debug(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}

public struct ConsoleLogger: LoggerPort {
    public let verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    public func info(_ message: String) {
        print("[INFO] \(message)")
        fflush(stdout)
    }

    public func debug(_ message: String) {
        guard verbose else { return }
        print("[DEBUG] \(message)")
        fflush(stdout)
    }

    public func warning(_ message: String) {
        print("[WARN] \(message)")
        fflush(stdout)
    }

    public func error(_ message: String) {
        fputs("[ERROR] \(message)\n", stderr)
        fflush(stderr)
    }
}
