import SwiftUI

/// Check a controller before playing: a drawn gamepad that mirrors every press, its details, and whether
/// Moonlight will recognise it when you stream.
struct ControllersPane: View {
    @ObservedObject var monitor: ControllerMonitor
    @Environment(\.openURL) private var openURL
    @State private var selectedID: String?

    private var selected: ConnectedController? {
        monitor.controllers.first { $0.id == selectedID } ?? monitor.controllers.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check your controller").font(.title2.weight(.semibold))
                    Text("Press its buttons and move the sticks: everything that reaches your Mac lights up here, so you know it'll work before you start the cloud PC.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .reveal(0)

                if monitor.controllers.count > 1 {
                    Picker("Controller", selection: Binding(get: { selected?.id ?? "" }, set: { selectedID = $0 })) {
                        ForEach(monitor.controllers) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if let controller = selected {
                    card(controller).reveal(0.06)
                } else {
                    empty.reveal(0.06)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: monitor.controllers.map(\.id))
        }
        .navigationTitle("Controllers")
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    // MARK: Controller

    private func card(_ controller: ConnectedController) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.tcAccent.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.name).font(.headline)
                    Text(details(controller))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                verdictBadge(controller.verdict)
            }

            if controller.live {
                GamepadView(state: controller.state, style: controller.style)
                    .frame(maxWidth: 400)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                readout(controller.state)
                if controller.canVibrate {
                    Button {
                        monitor.vibrate(controller)
                    } label: {
                        Label("Test Vibration", systemImage: "waveform")
                    }
                    .secondaryGlassButton()
                }
            } else {
                GamepadView(state: PadState(), dimmed: true)
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)
                Text("macOS doesn't show live input for this controller, so its buttons can't light up here. Moonlight reads it directly when you stream.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .unknown = controller.verdict {
                advice
            }
        }
        .padding(20)
        .glassSurface(cornerRadius: 20)
    }

    private func details(_ c: ConnectedController) -> String {
        var parts: [String] = []
        if let ids = c.ids { parts.append(ids) }
        if let transport = c.transport { parts.append(transport) }
        if let battery = c.battery {
            parts.append("Battery \(Int((battery * 100).rounded()))%\(c.charging ? ", charging" : "")")
        }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func verdictBadge(_ verdict: ConnectedController.Verdict) -> some View {
        switch verdict {
        case .ready:
            Label("Ready to play", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCapsule(tint: .green.opacity(0.15))
                .help("Moonlight recognises this controller, so it'll work on your cloud PC.")
        case .unknown:
            Label("May not work", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCapsule(tint: .orange.opacity(0.15))
        }
    }

    private var advice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Moonlight doesn't know this controller").font(.callout.weight(.semibold))
                Text("If it has a mode switch, try its X-input or Xbox mode: most controllers then pass as an Xbox controller, which works everywhere. A USB cable or the controller's own dongle often helps too.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The exact numbers, for checking stick drift and how far the triggers travel.
    private func readout(_ s: PadState) -> some View {
        HStack(spacing: 0) {
            value("Left stick", String(format: "%+.2f  %+.2f", s.leftStick.x, s.leftStick.y))
            Divider().frame(height: 30)
            value("Right stick", String(format: "%+.2f  %+.2f", s.rightStick.x, s.rightStick.y))
            Divider().frame(height: 30)
            value("Triggers", String(format: "%.2f  %.2f", s.leftTrigger, s.rightTrigger))
        }
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .help("Sticks at rest should read close to +0.00. A value that stays away from zero is stick drift.")
    }

    private func value(_ title: String, _ text: String) -> some View {
        VStack(spacing: 3) {
            Text(text).font(.system(.callout, design: .monospaced).weight(.medium))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Empty

    private var empty: some View {
        VStack(spacing: 18) {
            GamepadView(state: PadState(), dimmed: true)
                .frame(maxWidth: 340)
            VStack(spacing: 6) {
                Text("No controller connected").font(.headline)
                Text("Turn on your controller and connect it with Bluetooth or a USB cable. It shows up here the moment your Mac sees it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Bluetooth Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { openURL(url) }
            }
            .secondaryGlassButton()
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 20)
    }
}
