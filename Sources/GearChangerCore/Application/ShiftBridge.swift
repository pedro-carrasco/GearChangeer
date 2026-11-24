import Foundation

/// Application service bridging any ShiftInputPort to any BikeControlOutputPort.
///
/// Handles:
/// - Debouncing accidental double-triggers from BLE hardware
/// - Translating single-shot shift notifications (like ThinkRider VS200) into
///   OpenBikeControl digital button pulses: Press (0x01) -> delay -> Release (0x00).
public actor ShiftBridge {
    private let input: any ShiftInputPort
    private let output: any BikeControlOutputPort
    private let logger: any LoggerPort
    private let pulseDuration: Duration
    private let debounceInterval: TimeInterval
    private let onShift: (@Sendable (ShiftEvent) -> Void)?

    private var lastEventTimestamp: Date?
    private var bridgeTask: Task<Void, Never>?

    public init(
        input: any ShiftInputPort,
        output: any BikeControlOutputPort,
        logger: any LoggerPort = ConsoleLogger(),
        pulseDuration: Duration = .milliseconds(50),
        debounceInterval: TimeInterval = 0.04,
        onShift: (@Sendable (ShiftEvent) -> Void)? = nil
    ) {
        self.input = input
        self.output = output
        self.logger = logger
        self.pulseDuration = pulseDuration
        self.debounceInterval = debounceInterval
        self.onShift = onShift
    }

    public func start() async throws {
        try await output.start()
        try await input.start()

        bridgeTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.input.events {
                if Task.isCancelled { break }
                await self.handle(event)
            }
        }
    }

    public func stop() async {
        bridgeTask?.cancel()
        bridgeTask = nil
        await input.stop()
        await output.stop()
    }

    public func handle(_ event: ShiftEvent) async {
        if let last = lastEventTimestamp,
           event.timestamp.timeIntervalSince(last) < debounceInterval
        {
            logger.debug("Debounced duplicate event: \(event.action.rawValue)")
            return
        }
        lastEventTimestamp = event.timestamp

        let button = OpenBikeControlButton.from(event.action)
        let arrow = event.action == .shiftUp ? "UP (+)" : "DOWN (-)"
        logger.info("Shift \(arrow) -> OpenBikeControl button 0x\(String(format: "%02x", button.rawValue))")
        onShift?(event)

        await output.sendButtonState(button: button, state: .pressed)
        try? await Task.sleep(for: pulseDuration)
        await output.sendButtonState(button: button, state: .released)
    }
}
