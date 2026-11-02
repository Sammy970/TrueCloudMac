import SwiftUI

/// Stream settings, grouped like System Settings. Locked while pairing or streaming.
struct StreamPane: View {
    @Binding var settings: StreamSettings
    let locked: Bool
    @State private var shortcutAllowed = StreamOverlayPanel.fullscreenShortcutAllowed

    private static let bitrates = ["5000", "10000", "20000", "30000", "40000", "50000"]

    var body: some View {
        Form {
            if locked {
                Section {
                    Label("Settings are locked while you're streaming.", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Resolution", selection: $settings.resolution) {
                    Text("720p").tag("720")
                    Text("1080p").tag("1080")
                    Text("1440p").tag("1440")
                    Text("4K").tag("2160")
                }
                Picker("Aspect ratio", selection: $settings.aspect) {
                    ForEach(AspectRatio.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $settings.fullscreen) {
                    Text("Fullscreen")
                    Text("Also sends system shortcuts like ⌘Tab to the cloud PC.")
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Streams at \(settings.pixelSize). Use 16:10 to fill a MacBook screen.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Frame rate", selection: $settings.fps) {
                    Text("30").tag("30")
                    Text("60").tag("60")
                    Text("120").tag("120")
                }
                .pickerStyle(.segmented)
                Picker("Bitrate", selection: $settings.bitrate) {
                    ForEach(Self.bitrates, id: \.self) { Text("\(Int($0)! / 1000) Mbps").tag($0) }
                }
            } header: {
                Text("Performance")
            } footer: {
                Text("Uses up to \(settings.gigabytesPerHour) GB of data per hour. Lower the bitrate if the picture stutters.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    if shortcutAllowed {
                        Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { StreamOverlayPanel.requestFullscreenShortcut() }
                    }
                } label: {
                    Text("\(StreamOverlayPanel.shortcut) in fullscreen")
                    Text("Shows time left and Moonlight's shortcuts over the stream. Works in a window as it is; fullscreen needs Accessibility permission for TrueCloud.")
                }
            } header: {
                Text("Overlay")
            }

            Section("Codec") {
                Toggle(isOn: $settings.hevc) {
                    Text("HEVC (H.265)")
                    Text("Sharper picture at the same bitrate.")
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            // Picks up the permission once it's granted in System Settings.
            let allowed = StreamOverlayPanel.fullscreenShortcutAllowed
            if allowed != shortcutAllowed { shortcutAllowed = allowed }
        }
        .disabled(locked)
        .navigationTitle("Stream")
    }
}

extension StreamSettings {
    /// Pixel size Moonlight streams at, e.g. "1920 × 1080".
    var pixelSize: String {
        // Same sizes as AspectRatio.moonlightArgs: 16:10 keeps the 16:9 width and grows taller.
        let height = Int(resolution) ?? 1080
        let wide = height * 16 / 9
        switch aspect {
        case .wide: return "\(wide) × \(height)"
        case .tall: return "\(wide) × \(wide * 10 / 16)"
        case .ultrawide: return "\([720: 1680, 1080: 2560, 1440: 3440, 2160: 5120][height] ?? wide) × \(height)"
        }
    }

    /// Upper bound of data use, from the bitrate (kbit/s → GB per hour).
    var gigabytesPerHour: String {
        let gb = Double(Int(bitrate) ?? 0) * 1000 * 3600 / 8 / 1_000_000_000
        return gb.formatted(.number.precision(.fractionLength(0...1)))
    }
}
