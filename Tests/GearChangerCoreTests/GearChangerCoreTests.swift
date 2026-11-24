import Foundation
import Testing
@testable import GearChangerCore

@Suite("ThinkRider VS200 Decoder Tests")
struct ThinkRiderVS200DecoderTests {
    let decoder = ThinkRiderVS200Decoder()

    @Test("Decodes valid Shift Up packet (f3 05 03 01 fc)")
    func decodesShiftUp() throws {
        let packet = try #require(Data(hexString: "f3 05 03 01 fc"))
        #expect(decoder.decode(packet) == .shift(.shiftUp))
    }

    @Test("Decodes valid Shift Down packet (f3 05 03 00 fb)")
    func decodesShiftDown() throws {
        let packet = try #require(Data(hexString: "f3 05 03 00 fb"))
        #expect(decoder.decode(packet) == .shift(.shiftDown))
    }

    @Test("Rejects corrupted checksum")
    func rejectsBadChecksum() throws {
        let packet = try #require(Data(hexString: "f3 05 03 01 ff"))
        #expect(decoder.decode(packet) == .invalidChecksum(expected: 0xFC, actual: 0xFF))
    }

    @Test("Returns unknownFrame for unrelated BLE payload")
    func rejectsUnknownFrame() throws {
        let packet = try #require(Data(hexString: "aa bb cc"))
        #expect(decoder.decode(packet) == .unknownFrame(packet))
    }
}

@Suite("BLE Battery Level Decoder Tests")
struct BLEBatteryLevelDecoderTests {
    let decoder = BLEBatteryLevelDecoder()

    @Test("Decodes standard 0x2A19 battery percentage byte")
    func decodesBatteryLevel() {
        #expect(decoder.decode(Data([0])) == 0)
        #expect(decoder.decode(Data([85])) == 85)
        #expect(decoder.decode(Data([100])) == 100)
    }

    @Test("Clamps values above 100 to 100")
    func clampsAbove100() {
        #expect(decoder.decode(Data([255])) == 100)
    }

    @Test("Returns nil for empty payload")
    func returnsNilForEmptyData() {
        #expect(decoder.decode(Data()) == nil)
    }
}

@Suite("OpenBikeControl Codec Tests")
struct OpenBikeControlCodecTests {
    let codec = OpenBikeControlCodec()

    @Test("Encodes Shift Up pressed as [0x01, 0x01, 0x01]")
    func encodesShiftUpPressed() {
        let data = codec.encodeButtonState(button: .shiftUp, state: .pressed)
        #expect([UInt8](data) == [0x01, 0x01, 0x01])
    }

    @Test("Encodes Shift Down released as [0x01, 0x02, 0x00]")
    func encodesShiftDownReleased() {
        let data = codec.encodeButtonState(button: .shiftDown, state: .released)
        #expect([UInt8](data) == [0x01, 0x02, 0x00])
    }

    @Test("Encodes Device Status message as [0x02, battery, state]")
    func encodesDeviceStatus() {
        let data = codec.encodeDeviceStatus(batteryLevel: 80, connectionState: .connectedReady)
        #expect([UInt8](data) == [0x02, 0x50, 0x01])
    }

    @Test("Clamps battery level above 100")
    func clampsBattery() {
        let data = codec.encodeDeviceStatus(batteryLevel: 250, connectionState: .connectedReady)
        #expect([UInt8](data) == [0x02, 0x64, 0x01])
    }

    @Test("Builds standard OpenBikeControl mDNS TXT record")
    func buildsTxtRecord() {
        let meta = OpenBikeControlDeviceMetadata()
        let txt = meta.txtRecordDictionary
        #expect(txt["version"] == "1")
        #expect(txt["service-uuids"] == "d273f680-d548-419d-b9d1-fa0472345229")
        #expect(txt["name"] == "GearChanger VS200")
    }
}

actor MockInputPort: ShiftInputPort {
    nonisolated let events: AsyncStream<ShiftEvent>
    private let continuation: AsyncStream<ShiftEvent>.Continuation

    init() {
        var captured: AsyncStream<ShiftEvent>.Continuation!
        self.events = AsyncStream<ShiftEvent> { captured = $0 }
        self.continuation = captured
    }

    func start() async throws {}
    func stop() async { continuation.finish() }

    func emit(_ action: ShiftAction, at date: Date = Date()) {
        continuation.yield(ShiftEvent(action: action, timestamp: date))
    }
}

actor MockOutputPort: BikeControlOutputPort {
    struct SentButton: Equatable, Sendable {
        let button: OpenBikeControlButton
        let state: OpenBikeControlButtonState
    }

    private(set) var sentButtons: [SentButton] = []

    func start() async throws {}
    func stop() async {}

    func sendButtonState(button: OpenBikeControlButton, state: OpenBikeControlButtonState) async {
        sentButtons.append(SentButton(button: button, state: state))
    }

    func sendDeviceStatus(batteryLevel: UInt8, connectionState: OpenBikeControlConnectionState) async {}
}

@Suite("ShiftBridge Integration Tests")
struct ShiftBridgeTests {
    @Test("Translates a single ShiftEvent into Press + Release pulse")
    func translatesShiftToPulse() async throws {
        let input = MockInputPort()
        let output = MockOutputPort()
        let bridge = ShiftBridge(
            input: input,
            output: output,
            logger: ConsoleLogger(verbose: false),
            pulseDuration: .milliseconds(10),
            debounceInterval: 0.01
        )

        try await bridge.start()
        let t0 = Date()
        await input.emit(.shiftUp, at: t0)
        try await Task.sleep(for: .milliseconds(40))
        await input.emit(.shiftDown, at: t0.addingTimeInterval(0.1))
        try await Task.sleep(for: .milliseconds(40))
        await bridge.stop()

        let sent = await output.sentButtons
        #expect(sent == [
            .init(button: .shiftUp, state: .pressed),
            .init(button: .shiftUp, state: .released),
            .init(button: .shiftDown, state: .pressed),
            .init(button: .shiftDown, state: .released)
        ])
    }

    @Test("Debounces duplicate shift events arriving within debounce interval")
    func debouncesDuplicateEvents() async throws {
        let input = MockInputPort()
        let output = MockOutputPort()
        let bridge = ShiftBridge(
            input: input,
            output: output,
            logger: ConsoleLogger(verbose: false),
            pulseDuration: .milliseconds(5),
            debounceInterval: 0.1
        )

        let t0 = Date()
        await bridge.handle(ShiftEvent(action: .shiftUp, timestamp: t0))
        await bridge.handle(ShiftEvent(action: .shiftUp, timestamp: t0.addingTimeInterval(0.02)))

        let sent = await output.sentButtons
        #expect(sent.count == 2)
        #expect(sent[0] == .init(button: .shiftUp, state: .pressed))
        #expect(sent[1] == .init(button: .shiftUp, state: .released))
    }
}
