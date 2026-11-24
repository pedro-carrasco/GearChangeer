# GearChanger

Puente nativo para macOS escrito en **Swift 6** que conecta el mando de cambio virtual **ThinkRider VS200** por Bluetooth Low Energy (BLE) con **MyWhoosh** mediante el protocolo abierto **OpenBikeControl** (mDNS + TCP), sin dependencias externas.

## Arquitectura

El proyecto sigue una arquitectura de **Puertos y Adaptadores (Hexagonal)** dividida en tres targets de Swift Package Manager:

```text
┌──────────────────────────┐     ┌──────────────────────┐     ┌───────────────────────────────────┐
│   GearChangerAdapters    │     │   GearChangerCore    │     │        GearChangerAdapters        │
│  ThinkRiderBLEAdapter    │────▶│     ShiftBridge      │────▶│     OpenBikeControlTCPServer      │
│  (CoreBluetooth / BLE)   │     │ (Dominio + Codecs)   │     │  (Network.framework mDNS + TCP)   │
└──────────────────────────┘     └──────────────────────┘     └───────────────────────────────────┘
```

- **`GearChangerCore`**: dominio, puertos (`ShiftInputPort`, `BikeControlOutputPort`), decodificador de tramas ThinkRider VS200, codificador binario OpenBikeControl y orquestador `ShiftBridge` (con *debounce* y pulsos *press/release*). Sin dependencias del sistema operativo; 100 % testeable.
- **`GearChangerAdapters`**: adaptadores nativos de macOS (`CoreBluetooth` para BLE, `Network.framework` para `_openbikecontrol._tcp`, y `StdinSimulatorAdapter` para pruebas sin hardware).
- **`GearChangerCLI`**: ejecutable de línea de comandos con los modos `run`, `scan` y `simulate`.
- **`GearChangerMenuBar`**: app nativa de macOS para la barra de menús (`SwiftUI MenuBarExtra`, sin icono en el Dock) con estado en vivo de BLE/MyWhoosh, botones de prueba y reconexión.

## App en la barra de menús (macOS)

### Desde Xcode (desarrollo y depuración con `Cmd+R`)

Abre el proyecto Xcode (enlaza `GearChangerCore` y `GearChangerAdapters` desde el paquete local y usa [App/Info.plist](App/Info.plist)):

```bash
open GearChanger.xcodeproj
```

Selecciona el esquema **`GearChanger`** y pulsa `Cmd+R`.

### Empaquetado Release desde terminal

Genera y firma el paquete `dist/GearChanger.app` listo para abrir con doble clic o mover a `/Applications`:

```bash
./scripts/build-app.sh
open dist/GearChanger.app
```

[App/Info.plist](App/Info.plist) incluye `LSUIElement=true` (solo barra de menús) y las declaraciones de permisos de **Bluetooth**, **Red local** y Bonjour (`_openbikecontrol._tcp`).

## Requisitos

- macOS 14 (Sonoma) o superior
- Swift 6.0 o superior (Xcode / Command Line Tools)
- Permisos de **Bluetooth** y **Red local** concedidos a la terminal desde la que se ejecute
- **Importante**: el ThinkRider VS200 debe estar desemparejado del rodillo para poder conectarse al Mac, ya que solo admite una conexión BLE activa a la vez

## Uso

### 1. Probar la conexión con MyWhoosh (sin el VS200)

```bash
swift run gearchanger simulate -v
```

Abre **MyWhoosh** → **Conexiones** → **OpenBikeControl**, selecciona **`GearChanger VS200`** y envía `+` o `-` desde la terminal para verificar el cambio de marcha.

### 2. Inspeccionar el ThinkRider VS200 por BLE

```bash
swift run gearchanger scan -v
```

Lista los dispositivos BLE cercanos, se conecta al dispositivo cuyo nombre coincida con el prefijo (`Think VS` por defecto) y muestra los servicios/características GATT y las tramas hexadecimales recibidas al pulsar los botones.

### 3. Ejecutar el puente completo

```bash
swift run gearchanger run
```

Opciones disponibles:

| Flag | Descripción |
| :--- | :--- |
| `--name-prefix <str>` | Prefijo de nombre BLE del mando (por defecto: `Think VS`) |
| `--characteristic <uuid>` | Suscribirse únicamente a un UUID de característica GATT concreto |
| `--port <uint16>` | Puerto TCP fijo para OpenBikeControl (por defecto: asignado por el SO) |
| `--raw` | Mostrar en log las tramas hexadecimales crudas recibidas del VS200 |
| `-v`, `--verbose` | Activar logs de depuración |
| `-h`, `--help` | Mostrar ayuda |

### Compilación en modo Release y Tests

```bash
# Ejecutar tests unitarios
swift test

# Compilar binario optimizado (.build/release/gearchanger)
swift build -c release
```

## Notas de protocolo

- **ThinkRider VS200 (BLE)**: envía tramas de 5 bytes con checksum aditivo de 8 bits en el último byte (`sum(bytes[0..<4]) & 0xFF`):
  - Subir marcha: `f3 05 03 01 fc`
  - Bajar marcha: `f3 05 03 00 fb`
- **OpenBikeControl (mDNS + TCP)**:
  - Servicio Bonjour: `_openbikecontrol._tcp` con registros TXT (`version=1`, `service-uuids=d273f680-d548-419d-b9d1-fa0472345229`, etc.).
  - Cada pulsación del VS200 se traduce a un pulso digital OpenBikeControl: `[0x01, buttonId, 0x01]` (*press*) seguido de `[0x01, buttonId, 0x00]` (*release*) tras 50 ms (`0x01` = Shift Up, `0x02` = Shift Down).
