import AppKit
import GearChangerCore
import SwiftUI

final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep GearChanger strictly in the menu bar without a Dock icon
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

@main
struct GearChangerMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate
    @State private var viewModel: BridgeViewModel

    init() {
        let vm = BridgeViewModel()
        _viewModel = State(initialValue: vm)
        Task { @MainActor in
            await vm.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.menuBarIconName)
                .accessibilityLabel("GearChanger")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarContentView: View {
    let viewModel: BridgeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            statusSection

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            shiftSection

            Divider()

            controlsSection
        }
        .padding(14)
        .frame(width: 290)
    }

    private var header: some View {
        HStack {
            Image(systemName: "bicycle")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("GearChanger")
                    .font(.headline)
                Text(L10n.string("app.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(L10n.string(viewModel.isRunning ? "status.badge.active" : "status.badge.paused"))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    (viewModel.isRunning ? Color.green : Color.secondary).opacity(0.18),
                    in: Capsule()
                )
                .foregroundStyle(viewModel.isRunning ? .green : .secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusRow(
                title: L10n.string("section.ble.title"),
                detail: viewModel.bleStatusTitle,
                color: bleDotColor
            )
            StatusRow(
                title: L10n.string("section.server.title"),
                detail: viewModel.serverStatusTitle,
                color: serverDotColor
            )
        }
    }

    private var shiftSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("section.last_shift.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = viewModel.lastShift {
                    let label = L10n.string(last.action == .shiftUp ? "shift.up" : "shift.down")
                    Text("\(label) · \(last.timestamp.formatted(date: .omitted, time: .standard))")
                        .font(.caption.monospacedDigit())
                        .fontWeight(.medium)
                } else {
                    Text(L10n.string("section.last_shift.none"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.simulateShift(.shiftDown) }
                } label: {
                    Label(L10n.string("button.test_down"), systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.isRunning)

                Button {
                    Task { await viewModel.simulateShift(.shiftUp) }
                } label: {
                    Label(L10n.string("button.test_up"), systemImage: "arrow.up.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.isRunning)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        if viewModel.isRunning {
                            await viewModel.stop()
                        } else {
                            await viewModel.start()
                        }
                    }
                } label: {
                    Label(
                        L10n.string(viewModel.isRunning ? "button.stop" : "button.start"),
                        systemImage: viewModel.isRunning ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRunning ? .orange : .accentColor)

                Button {
                    viewModel.reconnectBLE()
                } label: {
                    Label(L10n.string("button.reconnect"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isRunning)
            }

            Button(role: .destructive) {
                Task {
                    await viewModel.stop()
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Text(L10n.string("button.quit"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.top, 2)
        }
    }

    private var bleDotColor: Color {
        switch viewModel.bleStatus {
        case .connected: return .green
        case .scanning, .connecting: return .orange
        case .bluetoothOff, .unauthorized, .unsupported: return .red
        case .idle: return .secondary
        }
    }

    private var serverDotColor: Color {
        switch viewModel.serverStatus {
        case .listening(_, let clients) where clients > 0: return .green
        case .listening: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }
}

private struct StatusRow: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
