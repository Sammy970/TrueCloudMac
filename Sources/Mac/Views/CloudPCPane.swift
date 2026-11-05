import AppKit
import SwiftUI
import TrueCloudKit

/// A question the user must answer before something destructive happens.
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmLabel: String
    var destructive = true
    var symbol = "power"
    /// Information only: one OK button, no Cancel.
    var informational = false
    let action: () -> Void
}

/// The play-first pane: greeting, plan card, the drawn monitor with the cloud PC's state, and the one next action.
struct CloudPCPane: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.openURL) private var openURL
    @ObservedObject var session: SessionService
    let settings: StreamSettings
    let editSettings: () -> Void
    let ask: (ConfirmRequest) -> Void

    private let moonlightInstalled = MoonlightRunner.locate() != nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let profile = auth.profile {
                    header(profile)
                        .reveal(0)
                        .padding(.bottom, 16)
                    PlanCard(profile: profile)
                        .reveal(0.05)
                        .padding(.bottom, 22)
                }

                DisplayHero(phase: session.phase, uptime: session.status?.uptime)
                    .frame(width: 270)
                    .reveal(0.1)
                    .padding(.bottom, 18)

                VStack(spacing: 6) {
                    Text(session.phase.statusText)
                        .font(.title2.weight(.semibold))
                    Text(session.lockMessage ?? session.phase.detailText)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .id(session.phase.screenState + session.phase.statusText)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .reveal(0.14)
                .padding(.bottom, 16)

                ConnectionTrack(phase: session.phase)
                    .frame(maxWidth: 400)
                    .reveal(0.18)
                    .padding(.bottom, 16)

                Telemetry(status: session.status, phase: session.phase, traffic: session.traffic)
                    .padding(.bottom, 16)

                actions
                    .reveal(0.22)
                    .padding(.bottom, 16)

                endpointPicker
                    .reveal(0.26)
                    .padding(.bottom, 14)

                streamSummary
                    .reveal(0.3)

                if !moonlightInstalled {
                    MoonlightMissing()
                        .frame(maxWidth: 440)
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: session.phase)
        }
        .navigationTitle("Cloud PC")
    }

    // MARK: Header

    private func header(_ profile: RigProfile) -> some View {
        VStack(spacing: 3) {
            Text("\(Self.greeting), \(profile.firstName)")
                .font(.title.weight(.bold))
            Text(profile.hasPairedBefore ? "Welcome back." : "Let's get your cloud PC running.")
                .foregroundStyle(.secondary)
        }
    }

    private static var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello"
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            switch session.phase {
            case .checking:
                busy("Checking…")
            case .idle:
                primary(session.cooldown > 0 ? "Start again in \(session.cooldown)s" : "Start Cloud PC",
                        systemImage: "power") { session.start() }
                    .disabled(session.cooldown > 0)
            case .starting, .booting:
                busy(session.phase == .starting ? "Starting…" : "Booting Sunshine…")
            case .ready:
                primary("Play", systemImage: "play.fill") { session.play(settings: settings) }
                    .disabled(!moonlightInstalled)
            case .pairing:
                busy("Pairing…")
            case .streaming:
                EmptyView()
            case .shuttingDown:
                busy("Shutting down…")
            }
            if session.phase != .checking {
                secondaryRow
            }
        }
    }

    private var secondaryRow: some View {
        HStack(spacing: 8) {
            if session.phase != .idle && session.phase != .shuttingDown {
                Button(role: .destructive) { ask(shutdownRequest) } label: {
                    Label("Shut Down", systemImage: "power").foregroundStyle(.red)
                }
                .secondaryGlassButton()
            }
            Menu {
                Button { Task { await session.refreshStatus() } } label: { Label("Refresh Status", systemImage: "arrow.clockwise") }
                Divider()
                Button { ask(unpairRequest) } label: { Label("Unpair All Devices…", systemImage: "link.badge.plus") }
                Button(role: .destructive) { ask(forceStopRequest) } label: { Label("Force Stop…", systemImage: "exclamationmark.octagon") }
                    .disabled(session.phase == .idle)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .secondaryGlassButton()
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .controlSize(.regular)
    }

    private var shutdownRequest: ConfirmRequest {
        ConfirmRequest(title: "Shut down your cloud PC?",
                       message: "Windows closes down normally. Save your game first. Plan time stops counting once it's off.",
                       confirmLabel: "Shut Down", symbol: "power") { session.shutDown() }
    }

    private var forceStopRequest: ConfirmRequest {
        ConfirmRequest(title: "Force stop your cloud PC?",
                       message: "This cuts power right away, like holding the power button. Unsaved progress is lost and Windows may need to repair itself. Use it only if Shut Down doesn't work.",
                       confirmLabel: "Force Stop", symbol: "exclamationmark.octagon.fill") { session.forceStop() }
    }

    private var unpairRequest: ConfirmRequest {
        ConfirmRequest(title: "Unpair all devices?",
                       message: "Every Moonlight client paired with your cloud PC is removed, including this Mac. Pressing Play pairs this Mac again automatically.",
                       confirmLabel: "Unpair", symbol: "link.badge.plus") { session.unpairAll() }
    }

    private func primary(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 220)
        }
        .primaryGlassButton()
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    private func busy(_ title: String) -> some View {
        Button {} label: {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(title).font(.body.weight(.semibold))
            }
            .frame(width: 220)
        }
        .primaryGlassButton()
        .controlSize(.large)
        .disabled(true)
    }

    // MARK: Endpoint

    @ViewBuilder
    private var endpointPicker: some View {
        if let profile = auth.profile {
            VStack(spacing: 6) {
                Picker("Endpoint", selection: $session.endpoint) {
                    ForEach(Endpoint.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                .disabled(session.phase == .pairing || session.phase == .streaming)
                Text(session.endpoint.streamAddress(for: profile))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: Stream summary

    private var streamSummary: some View {
        HStack(spacing: 6) {
            Text(settings.summary)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Change…", action: editSettings)
                .textLinkStyle()
        }
        .font(.callout)
    }
}

extension StreamSettings {
    /// "1080p · 16:9 · 60 FPS · 20 Mbps · HEVC"
    var summary: String {
        let res = resolution == "2160" ? "4K" : "\(resolution)p"
        let mbps = (Int(bitrate) ?? 0) / 1000
        return [res, aspect.rawValue, "\(fps) FPS", "\(mbps) Mbps", hevc ? "HEVC" : "H.264"].joined(separator: " · ")
    }
}

// MARK: - Plan card

private struct PlanCard: View {
    let profile: RigProfile
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            content
            if let banner { banner }
        }
        .padding(18)
        .frame(maxWidth: 520)
        .glassSurface(cornerRadius: 22)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Label(profile.planName, systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.tcAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.tcAccent.opacity(0.14), in: Capsule())
                Text(profile.isUnlimited ? "Unlimited" : PlanUsage.duration(profile.minutesLeft ?? 0))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("play time left")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .offset(y: -6)
            }
            .frame(minWidth: 130, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                if !profile.isUnlimited {
                    VStack(alignment: .leading, spacing: 5) {
                        AccentBar(value: profile.hoursRemaining / max(profile.planHours, 0.01))
                        Text("of \(RigProfile.clock(hours: profile.planHours)) plan time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
                HStack(spacing: 0) {
                    stat("Daily quota", profile.dailyLimitHours > 360 ? "Unlimited" : RigProfile.clock(hours: profile.dailyLimitHours))
                    stat("Renewal", profile.subscription ? (profile.autoRenew ? "Auto-renews" : "Manual") : "Inactive")
                    if let end = profile.expiration {
                        stat("Valid until", PlanUsage.dateText(end), tint: PlanUsage.validityTint(of: profile))
                    }
                }
            }
        }
    }

    /// Red when the plan has ended, orange in its last days, like the dashboard's banners.
    private var banner: AnyView? {
        guard let end = profile.expiration else { return nil }
        let date = PlanUsage.dateText(end)
        if profile.isExpired() {
            return AnyView(notice("Your plan ended on \(date). Renew it at truecloud.in to keep playing.",
                                  symbol: "xmark.octagon.fill", tint: .red))
        }
        if profile.isExpiringSoon(), let days = profile.daysUntilExpiry() {
            let when = days < 1 ? "today" : days == 1 ? "in 1 day" : "in \(days) days"
            return AnyView(notice("Your plan ends \(when) (\(date)).", symbol: "exclamationmark.triangle.fill", tint: .orange))
        }
        return nil
    }

    private func notice(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Renew") { openURL(Config.dashboardURL.appendingPathComponent("plans")) }
                .textLinkStyle()
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.3)))
    }

    private func stat(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit().foregroundStyle(tint ?? Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Telemetry

/// Uptime, CPU and memory of the running cloud PC, then its network speed and data used.
private struct Telemetry: View {
    let status: VmStatus?
    let phase: SessionService.Phase
    let traffic: TrafficRate

    var body: some View {
        if let status, status.isRunning, phase != .shuttingDown {
            // Two rows so a narrow window never has to fit six chips side by side
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    chip("clock", Self.uptime(status.uptime))
                    chip("cpu", "\(Int((status.cpu * 100).rounded()))%")
                    chip("memorychip", String(format: "%.1f / %.0f GB", status.mem / 1_073_741_824, status.maxmem / 1_073_741_824))
                }
                HStack(spacing: 8) {
                    chip("arrow.down", String(format: "%.2f MB/s", traffic.downloadMBps))
                    chip("arrow.up", String(format: "%.2f MB/s", traffic.uploadMBps))
                    chip("arrow.up.arrow.down", "\(TrafficMeter.text(bytes: status.netin + status.netout)) used")
                }
            }
            .transition(.opacity)
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCapsule()
    }

    static func uptime(_ seconds: Int) -> String {
        seconds >= 3600 ? "\(seconds / 3600)h \(seconds % 3600 / 60)m" : "\(seconds / 60)m \(seconds % 60)s"
    }
}

// MARK: - Moonlight missing

private struct MoonlightMissing: View {
    private let command = "brew install --cask moonlight"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Moonlight is required to stream").font(.callout.weight(.semibold))
                Text("Install it, then reopen TrueCloud.").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Text(command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.orange.opacity(0.25)))
    }
}

// MARK: - Confirm dialog

/// An in-window confirmation: dimmed backdrop and a glass card. Esc cancels.
struct ConfirmOverlay: View {
    let request: ConfirmRequest
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
            VStack(spacing: 14) {
                Image(systemName: request.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(request.destructive ? Color.red : Color.tcAccent)
                    .frame(width: 52, height: 52)
                    .background((request.destructive ? Color.red : Color.tcAccent).opacity(0.14), in: Circle())
                Text(request.title).font(.headline).multilineTextAlignment(.center)
                Text(request.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if !request.informational {
                        Button("Cancel", action: dismiss)
                            .secondaryGlassButton()
                            .keyboardShortcut(.cancelAction)
                    }
                    Button {
                        dismiss()
                        request.action()
                    } label: {
                        Text(request.confirmLabel).font(.body.weight(.semibold)).padding(.horizontal, 6)
                    }
                    .primaryGlassButton()
                    .tint(request.destructive ? .red : .tcAccent)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(width: 340)
            .glassSurface(cornerRadius: 24)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.background.opacity(0.6)))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
        }
        .transition(.opacity)
    }
}
