# GearChanger

A native macOS bridge written in **Swift 6** that connects the **ThinkRider VS200** virtual shifter over Bluetooth Low Energy (BLE) to **MyWhoosh** using the open **OpenBikeControl** protocol (mDNS + TCP), with zero third-party dependencies.

Includes both a lightweight CLI and a native macOS menu bar app localized in **English (`en`)** and **Spanish (`es`)**.

## Architecture

The project follows a **Ports & Adapters (Hexagonal)** architecture organized into Swift Package Manager targets:

```text
┌──────────────────────────┐     ┌──────────────────────┐     ┌───────────────────────────────────┐
│   GearChangerAdapters    │     │   GearChangerCore    │     │        GearChangerAdapters        │
│  ThinkRiderBLEAdapter    │────▶│     ShiftBridge      │────▶│     OpenBikeControlTCPServer      │
│  (CoreBluetooth / BLE)   │     │ (Domain + Codecs)    │     │  (Network.framework mDNS + TCP)   │
└──────────────────────────┘     └──────────────────────┘     └───────────────────────────────────┘
```

- **`GearChangerCore`**: domain types, ports (`ShiftInputPort`, `BikeControlOutputPort`), ThinkRider VS200 packet decoder, OpenBikeControl binary codec, and the `ShiftBridge` actor (with debounce and press/release pulses). Zero OS dependencies; 100% unit-testable.
- **`GearChangerAdapters`**: native macOS adapters (`CoreBluetooth` for BLE, `Network.framework` for `_openbikecontrol._tcp`, and `StdinSimulatorAdapter` for hardware-free testing).
- **`GearChangerCLI`**: command-line executable with `run`, `scan`, and `simulate` modes.
- **`GearChangerMenuBar` / `GearChanger.xcodeproj`**: native macOS menu bar app (`SwiftUI MenuBarExtra`, no Dock icon) showing live BLE & MyWhoosh status, test shift buttons, and reconnect controls.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6.0 or later (Xcode / Command Line Tools)
- **Bluetooth** and **Local Network** permissions granted to the app (or terminal when running the CLI)
- **Important**: unpair the ThinkRider VS200 from your trainer before connecting it to your Mac, as the shifter only accepts one active BLE connection at a time

## Menu Bar App (macOS)

### Running from Xcode (`Cmd+R`)

Open the Xcode project (links `GearChangerCore` and `GearChangerAdapters` from the local Swift package and uses [App/Info.plist](App/Info.plist)):

```bash
open GearChanger.xcodeproj
```

Select the **`GearChanger`** scheme and press `Cmd+R`.

### Packaging a Universal Release `.app` and `.zip` from Terminal

Build a **Universal Binary (`arm64` + `x86_64`)** `dist/GearChanger.app`, ad-hoc sign it, and package `dist/GearChanger-macOS-universal.zip` ready for GitHub Releases:

```bash
./scripts/build-app.sh
open dist/GearChanger.app
```

[App/Info.plist](App/Info.plist) sets `LSUIElement=true` (menu bar only) and declares **Bluetooth**, **Local Network**, and Bonjour (`_openbikecontrol._tcp`) usage, localized via `en.lproj` and `es.lproj`.

## CLI Usage

### 1. Test MyWhoosh connection without the VS200

```bash
swift run gearchanger simulate -v
```

Open **MyWhoosh** → **Connections** → **OpenBikeControl**, select **`GearChanger VS200`**, and type `+` or `-` in the terminal to verify virtual shifting.

### 2. Inspect ThinkRider VS200 BLE packets

```bash
swift run gearchanger scan -v
```

Lists nearby BLE devices, connects to the device matching the name prefix (`Think VS` by default), and prints discovered GATT services/characteristics along with live hex payloads.

### 3. Run the full bridge

```bash
swift run gearchanger run
```

Available flags:

| Flag | Description |
| :--- | :--- |
| `--name-prefix <str>` | BLE device name filter (default: `Think VS`) |
| `--characteristic <uuid>` | Subscribe only to a specific GATT characteristic UUID |
| `--port <uint16>` | Fixed TCP port for OpenBikeControl (default: OS-assigned ephemeral port) |
| `--raw` | Log raw hex frames received from the VS200 |
| `-v`, `--verbose` | Enable verbose debug logging |
| `-h`, `--help` | Show help |

### Tests & Release Build

```bash
# Run unit tests
swift test

# Build optimized CLI binary (.build/release/gearchanger)
swift build -c release
```

## Protocol Notes

- **ThinkRider VS200 (BLE)**: sends 5-byte frames with an 8-bit additive checksum in the last byte (`sum(bytes[0..<4]) & 0xFF`):
  - Shift Up: `f3 05 03 01 fc`
  - Shift Down: `f3 05 03 00 fb`
- **OpenBikeControl (mDNS + TCP)**:
  - Bonjour service: `_openbikecontrol._tcp` with TXT records (`version=1`, `service-uuids=d273f680-d548-419d-b9d1-fa0472345229`, etc.).
  - Each VS200 notification is translated into a digital OpenBikeControl button pulse: `[0x01, buttonId, 0x01]` (press) followed by `[0x01, buttonId, 0x00]` (release) after 50 ms (`0x01` = Shift Up, `0x02` = Shift Down).

## License

Copyright 2026 Pedro Carrasco. Licensed under the [Apache License 2.0](LICENSE).
