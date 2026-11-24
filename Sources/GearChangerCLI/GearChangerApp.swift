import Foundation
import GearChangerAdapters
import GearChangerCore

enum CLICommand {
    case run
    case scan
    case simulate
    case help
}

struct CLIOptions {
    var command: CLICommand = .run
    var namePrefix: String = "Think VS"
    var characteristicUUID: String?
    var port: UInt16?
    var verbose: Bool = false
    var logRawPackets: Bool = false

    static func parse(_ args: [String]) -> CLIOptions {
        var options = CLIOptions()
        var index = 1

        if args.count > 1, !args[1].hasPrefix("-") {
            switch args[1].lowercased() {
            case "run": options.command = .run
            case "scan": options.command = .scan
            case "simulate", "sim": options.command = .simulate
            case "help": options.command = .help
            default:
                fputs("Unknown command '\(args[1])'\n", stderr)
                options.command = .help
                return options
            }
            index = 2
        }

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "-h", "--help":
                options.command = .help
                return options
            case "-v", "--verbose":
                options.verbose = true
            case "--raw":
                options.logRawPackets = true
            case "--name-prefix":
                if index + 1 < args.count {
                    options.namePrefix = args[index + 1]
                    index += 1
                }
            case "--characteristic":
                if index + 1 < args.count {
                    options.characteristicUUID = args[index + 1]
                    index += 1
                }
            case "--port":
                if index + 1 < args.count, let parsed = UInt16(args[index + 1]) {
                    options.port = parsed
                    index += 1
                }
            default:
                fputs("Unknown flag '\(arg)'\n", stderr)
                options.command = .help
                return options
            }
            index += 1
        }

        return options
    }
}

func printUsage() {
    print("""
    GearChanger — ThinkRider VS200 -> OpenBikeControl (MyWhoosh) Bridge

    USAGE:
      gearchanger [command] [options]

    COMMANDS:
      run        Connect to ThinkRider VS200 via BLE and bridge shifts to MyWhoosh via OpenBikeControl (default)
      scan       Scan nearby BLE devices, connect to ThinkRider VS200, and dump GATT UUIDs + raw hex packets
      simulate   Start the OpenBikeControl server and simulate shifts from the terminal (+ / -) to test MyWhoosh
      help       Show this help message

    OPTIONS:
      --name-prefix <str>       BLE device name filter (default: "Think VS")
      --characteristic <uuid>   Subscribe only to a specific BLE characteristic UUID
      --port <uint16>           Fixed TCP port for OpenBikeControl (default: ephemeral OS-assigned port)
      --raw                     Log raw hex packets received from the VS200
      -v, --verbose             Enable verbose debug logging
      -h, --help                Show help
    """)
}

@main
struct GearChangerApp {
    static func main() async {
        let options = CLIOptions.parse(CommandLine.arguments)
        if options.command == .help {
            printUsage()
            return
        }

        let logger = ConsoleLogger(verbose: options.verbose)

        let (stopStream, stopContinuation) = AsyncStream<Void>.makeStream()

        // Handle Ctrl+C (SIGINT) and SIGTERM cleanly
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            logger.info("Received SIGINT, shutting down...")
            stopContinuation.yield()
            stopContinuation.finish()
        }
        sigintSource.resume()

        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler {
            logger.info("Received SIGTERM, shutting down...")
            stopContinuation.yield()
            stopContinuation.finish()
        }
        sigtermSource.resume()

        switch options.command {
        case .scan:
            let bleConfig = ThinkRiderBLEConfiguration(
                namePrefix: options.namePrefix,
                targetCharacteristicUUID: options.characteristicUUID,
                scanOnly: true,
                logRawPackets: true
            )
            let bleAdapter = ThinkRiderBLEAdapter(config: bleConfig, logger: logger)
            do {
                try await bleAdapter.start()
                let consumer = Task {
                    for await event in bleAdapter.events {
                        logger.info("Decoded VS200 shift: \(event.action.rawValue) (raw: \(event.rawPayload?.hexString ?? "n/a"))")
                    }
                }
                for await _ in stopStream { break }
                consumer.cancel()
                await bleAdapter.stop()
            } catch {
                logger.error("Scan failed: \(error.localizedDescription)")
            }

        case .simulate:
            let server = OpenBikeControlTCPServer(port: options.port, logger: logger)
            let simulator = StdinSimulatorAdapter(logger: logger) {
                stopContinuation.yield()
                stopContinuation.finish()
            }
            let bridge = ShiftBridge(input: simulator, output: server, logger: logger)
            do {
                try await bridge.start()
                for await _ in stopStream { break }
                await bridge.stop()
            } catch {
                logger.error("Simulator bridge failed: \(error.localizedDescription)")
            }

        case .run:
            let server = OpenBikeControlTCPServer(port: options.port, logger: logger)
            let bleConfig = ThinkRiderBLEConfiguration(
                namePrefix: options.namePrefix,
                targetCharacteristicUUID: options.characteristicUUID,
                scanOnly: false,
                logRawPackets: options.logRawPackets
            )
            let bleAdapter = ThinkRiderBLEAdapter(config: bleConfig, logger: logger)
            let bridge = ShiftBridge(input: bleAdapter, output: server, logger: logger)
            do {
                try await bridge.start()
                logger.info("GearChanger running! Open MyWhoosh -> Connections -> OpenBikeControl and select 'GearChanger VS200'. Press Ctrl+C to stop.")
                for await _ in stopStream { break }
                await bridge.stop()
            } catch {
                logger.error("Bridge failed: \(error.localizedDescription)")
            }

        case .help:
            break
        }
    }
}
