import Foundation
import GearChangerCore
import Network

public enum OpenBikeControlServerStatus: Sendable, Equatable {
    case stopped
    case listening(port: UInt16, clientCount: Int)
    case failed(String)
}

/// OpenBikeControl TCP + mDNS (Bonjour) output adapter for MyWhoosh.
///
/// Publishes `_openbikecontrol._tcp` via macOS native Network.framework (`NWListener`),
/// accepts persistent TCP connections from MyWhoosh, and streams OpenBikeControl binary frames.
public final class OpenBikeControlTCPServer: BikeControlOutputPort, @unchecked Sendable {
    private let metadata: OpenBikeControlDeviceMetadata
    private let port: UInt16?
    private let codec = OpenBikeControlCodec()
    private let logger: any LoggerPort
    private let onStatusChange: (@Sendable (OpenBikeControlServerStatus) -> Void)?
    private let queue = DispatchQueue(label: "com.gearchanger.openbikecontrol.tcp")

    private var listener: NWListener?
    private var boundPort: UInt16 = 0
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var startContinuation: CheckedContinuation<Void, any Error>?

    public init(
        metadata: OpenBikeControlDeviceMetadata = OpenBikeControlDeviceMetadata(),
        port: UInt16? = nil,
        logger: any LoggerPort = ConsoleLogger(),
        onStatusChange: (@Sendable (OpenBikeControlServerStatus) -> Void)? = nil
    ) {
        self.metadata = metadata
        self.port = port
        self.logger = logger
        self.onStatusChange = onStatusChange
    }

    public func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.startContinuation = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.includePeerToPeer = true

                    let nwListener: NWListener
                    if let port = self.port, let nwPort = NWEndpoint.Port(rawValue: port) {
                        nwListener = try NWListener(using: parameters, on: nwPort)
                    } else {
                        nwListener = try NWListener(using: parameters)
                    }

                    let txtRecord = NWTXTRecord(self.metadata.txtRecordDictionary)
                    nwListener.service = NWListener.Service(
                        name: self.metadata.name,
                        type: OpenBikeControlSpec.mdnsServiceType,
                        domain: nil,
                        txtRecord: txtRecord
                    )

                    nwListener.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            let boundPort = nwListener.port?.rawValue ?? 0
                            self.boundPort = boundPort
                            self.onStatusChange?(.listening(port: boundPort, clientCount: self.connections.count))
                            self.logger.info(
                                "OpenBikeControl server READY on port \(boundPort) | mDNS: \(OpenBikeControlSpec.mdnsServiceType) ('\(self.metadata.name)')"
                            )
                            if let cont = self.startContinuation {
                                self.startContinuation = nil
                                cont.resume()
                            }
                        case .failed(let error):
                            self.onStatusChange?(.failed(error.localizedDescription))
                            self.logger.error("OpenBikeControl listener failed: \(error.localizedDescription)")
                            if let cont = self.startContinuation {
                                self.startContinuation = nil
                                cont.resume(throwing: error)
                            }
                        case .waiting(let error):
                            self.logger.warning("OpenBikeControl listener waiting: \(error.localizedDescription)")
                        case .cancelled:
                            self.onStatusChange?(.stopped)
                            self.logger.info("OpenBikeControl listener cancelled.")
                        default:
                            break
                        }
                    }

                    nwListener.newConnectionHandler = { [weak self] connection in
                        self?.handleNewConnection(connection)
                    }

                    self.listener = nwListener
                    nwListener.start(queue: self.queue)
                } catch {
                    if let cont = self.startContinuation {
                        self.startContinuation = nil
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    public func stop() async {
        queue.sync {
            for (_, connection) in self.connections {
                connection.cancel()
            }
            self.connections.removeAll()
            self.listener?.cancel()
            self.listener = nil
            self.boundPort = 0
            self.onStatusChange?(.stopped)
        }
        logger.info("OpenBikeControl server stopped.")
    }

    public func sendButtonState(
        button: OpenBikeControlButton,
        state: OpenBikeControlButtonState
    ) async {
        let payload = codec.encodeButtonState(button: button, state: state)
        broadcast(payload)
    }

    public func sendDeviceStatus(
        batteryLevel: UInt8,
        connectionState: OpenBikeControlConnectionState
    ) async {
        let payload = codec.encodeDeviceStatus(
            batteryLevel: batteryLevel,
            connectionState: connectionState
        )
        broadcast(payload)
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let endpointDesc = String(describing: connection.endpoint)
        connections[id] = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onStatusChange?(.listening(port: self.boundPort, clientCount: self.connections.count))
                self.logger.info("Client connected (MyWhoosh): \(endpointDesc) | active clients: \(self.connections.count)")
                let status = self.codec.encodeDeviceStatus(batteryLevel: 100, connectionState: .connectedReady)
                self.send(status, to: connection)
                self.receiveLoop(on: connection)
            case .failed(let error):
                self.logger.warning("Client \(endpointDesc) failed: \(error.localizedDescription)")
                self.connections.removeValue(forKey: id)
                self.onStatusChange?(.listening(port: self.boundPort, clientCount: self.connections.count))
                connection.cancel()
            case .cancelled:
                self.connections.removeValue(forKey: id)
                self.onStatusChange?(.listening(port: self.boundPort, clientCount: self.connections.count))
                self.logger.info("Client disconnected: \(endpointDesc) | active clients: \(self.connections.count)")
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.logger.debug("RX from MyWhoosh (\(data.count)B): \(data.hexString)")
            }
            if let error {
                self.logger.debug("Receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.receiveLoop(on: connection)
        }
    }

    private func broadcast(_ data: Data) {
        queue.async {
            if self.connections.isEmpty {
                self.logger.debug("TX skipped (no connected MyWhoosh client): \(data.hexString)")
                return
            }
            self.logger.debug("TX -> \(self.connections.count) client(s): \(data.hexString)")
            for (_, connection) in self.connections {
                self.send(data, to: connection)
            }
        }
    }

    private func send(_ data: Data, to connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.logger.warning("Failed to send \(data.hexString): \(error.localizedDescription)")
            }
        })
    }
}
