import Foundation
import GearChangerCore

/// Terminal input adapter for testing the OpenBikeControl bridge with MyWhoosh
/// without needing the physical ThinkRider VS200 connected.
///
/// Controls:
///   u / k / +  -> Shift Up
///   d / i / -  -> Shift Down
///   q          -> Quit
public final class StdinSimulatorAdapter: ShiftInputPort, @unchecked Sendable {
    public let events: AsyncStream<ShiftEvent>

    private let continuation: AsyncStream<ShiftEvent>.Continuation
    private let logger: any LoggerPort
    private let onQuit: @Sendable () -> Void
    private var readerTask: Task<Void, Never>?

    public init(
        logger: any LoggerPort = ConsoleLogger(),
        onQuit: @escaping @Sendable () -> Void = {}
    ) {
        self.logger = logger
        self.onQuit = onQuit
        var captured: AsyncStream<ShiftEvent>.Continuation!
        self.events = AsyncStream<ShiftEvent> { continuation in
            captured = continuation
        }
        self.continuation = captured
    }

    public func start() async throws {
        logger.info("Simulator ready. Type '+' (or 'u'/'k') + Enter to SHIFT UP, '-' (or 'd'/'i') + Enter to SHIFT DOWN, 'q' to quit.")
        readerTask = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let line = readLine(strippingNewline: true) else {
                    break
                }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch trimmed {
                case "+", "u", "k", "up":
                    self.continuation.yield(ShiftEvent(action: .shiftUp))
                case "-", "d", "i", "down":
                    self.continuation.yield(ShiftEvent(action: .shiftDown))
                case "q", "quit", "exit":
                    self.onQuit()
                    return
                case "":
                    continue
                default:
                    self.logger.warning("Unknown command '\(trimmed)'. Use '+', '-', or 'q'.")
                }
            }
        }
    }

    public func stop() async {
        readerTask?.cancel()
        readerTask = nil
        continuation.finish()
    }
}
