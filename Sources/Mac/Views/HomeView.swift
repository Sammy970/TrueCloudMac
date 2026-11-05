import SwiftUI
import TrueCloudKit

/// Signed-in window: a sidebar with the Cloud PC, Stream, Network, Controllers, Activity and Payments panes and the account footer.
struct HomeView: View {
    enum Pane: Hashable { case cloudPC, stream, network, controllers, activity, payments, logs, about }

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.openURL) private var openURL
    @StateObject private var session: SessionService
    @State private var settings = StreamSettings.load()
    @State private var pane: Pane? = .cloudPC
    /// Kept here so results survive switching panes.
    @StateObject private var networkCheck = NetworkCheck()
    @StateObject private var controllerMonitor = ControllerMonitor()
    @StateObject private var activityModel = ActivityModel()
    @StateObject private var paymentsModel = PaymentsModel()

    @State private var confirm: ConfirmRequest?

    init(auth: AuthStore) {
        _session = StateObject(wrappedValue: SessionService(auth: auth, driver: MoonlightDriver()))
    }

    var body: some View {
        split
            .onChange(of: settings) { $0.save() }
        .onChange(of: session.phase) { phase in
            // The in-stream overlay (time left, health warnings, ⌃⌥A) lives exactly as long as the stream.
            if phase == .streaming, let host = session.streamHost {
                StreamOverlayPanel.shared.begin(host: host, profile: auth.profile)
            } else if phase != .streaming {
                StreamOverlayPanel.shared.end()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAbout)) { _ in pane = .about }
        .onAppear {
            if !previewIfRequested() { session.startPolling() }
        }
        .onDisappear { session.detach() }
        .overlay {
            if let dialog = confirm ?? session.notice.map(Self.request(for:)) {
                ConfirmOverlay(request: dialog) {
                    confirm = nil
                    session.notice = nil
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: confirm?.id)
        .animation(.easeOut(duration: 0.18), value: session.notice?.id)
    }

    @ViewBuilder
    private var split: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TRUECLOUD_SNAPSHOT"] != nil {
            // Window snapshots can't draw the glass sidebar, so lay the same views out flat.
            HStack(spacing: 0) {
                sidebar.frame(width: 220)
                Divider()
                detail
            }
        } else {
            splitView
        }
        #else
        splitView
        #endif
    }

    /// A notice is shown as an information-only dialog.
    private static func request(for notice: SessionService.Notice) -> ConfirmRequest {
        ConfirmRequest(title: notice.title, message: notice.message, confirmLabel: "OK",
                       destructive: false, symbol: "info.circle.fill", informational: true) {}
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch pane ?? .cloudPC {
        case .cloudPC:
            CloudPCPane(session: session, settings: settings, editSettings: { pane = .stream }, ask: { confirm = $0 })
        case .stream:
            StreamPane(settings: $settings, locked: session.phase == .pairing || session.phase == .streaming)
        case .about:
            ScrollView { AboutView() }
                .navigationTitle("About")
        case .network:
            NetworkPane(check: networkCheck, settings: $settings, busy: session.phase == .pairing || session.phase == .streaming,
                        host: auth.profile.map { session.endpoint.host(for: $0) } ?? "moonlight-a2.truecloud.in")
        case .controllers:
            ControllersPane(monitor: controllerMonitor)
        case .activity:
            ActivityPane(model: activityModel)
        case .payments:
            PaymentsPane(model: paymentsModel)
        case .logs:
            LogsPane()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $pane) {
            NavigationLink(value: Pane.cloudPC) {
                HStack {
                    Label("Cloud PC", systemImage: "desktopcomputer")
                    Spacer()
                    if let color = session.phase.indicatorColor {
                        Circle().fill(color).frame(width: 7, height: 7)
                            .help(session.phase.statusText)
                    }
                }
            }
            NavigationLink(value: Pane.stream) {
                Label("Stream", systemImage: "slider.horizontal.3")
            }
            NavigationLink(value: Pane.network) {
                Label("Network", systemImage: "gauge.with.dots.needle.67percent")
            }
            NavigationLink(value: Pane.controllers) {
                Label("Controllers", systemImage: "gamecontroller")
            }
            NavigationLink(value: Pane.activity) {
                Label("Activity", systemImage: "clock.arrow.circlepath")
            }
            NavigationLink(value: Pane.payments) {
                Label("Payments", systemImage: "creditcard")
            }
            NavigationLink(value: Pane.logs) {
                Label("Logs", systemImage: "doc.text.magnifyingglass")
            }
            NavigationLink(value: Pane.about) {
                Label("About", systemImage: "info.circle")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let profile = auth.profile {
                AccountFooter(profile: profile) {
                    Task { await auth.reloadProfile() }
                } dashboard: {
                    openURL(Config.dashboardURL)
                } logOut: {
                    session.detach()
                    auth.logout()
                }
            }
        }
    }

    #if DEBUG
    private static var sampleActivity: [ActivityEntry] {
        let now = Date()
        let rows: [(String, String, TimeInterval)] = [
            ("start", "Success: Start command sent", 2_400),
            ("system", "Log initialized.", 2_460),
            ("shutdown", "Success: VM stopped", 9_000),
            ("start", "Success: Start command sent", 17_000),
            ("shutdown", "Timed out waiting for stop status", 26_000),
            ("shutdown", "Success: VM stopped", 30_000),
            ("start", "Success: Start command sent", 36_000),
            ("shutdown", "Success: VM stopped", 100_000),
            ("start", "Success: Start command sent", 108_000),
            ("start", "Success: Start command sent", 120_000),
        ]
        return rows.enumerated().map { index, row in
            ActivityEntry(id: "\(index)", type: row.0, status: row.1, timestamp: now.addingTimeInterval(-row.2))
        }
    }

    private static var samplePayments: [PaymentRecord] {
        let now = Date()
        return [
            PaymentRecord(id: "p3", planName: "Regular", amount: 159_920, status: .pending, isUpgrade: true,
                          createdAt: now.addingTimeInterval(-3_600)),
            PaymentRecord(id: "p2", planName: "Regular", amount: 159_920, status: .failure, isUpgrade: true,
                          createdAt: now.addingTimeInterval(-86_400 * 9), failureReason: "Payment declined"),
            PaymentRecord(id: "p1", planName: "Basic", amount: 99_900, status: .success,
                          createdAt: now.addingTimeInterval(-86_400 * 40)),
        ]
    }
    #endif

    /// Debug builds only: `TRUECLOUD_PREVIEW=home:<phase>[:stream|network|about|controllers|activity|payments|sample|overlay|confirm-shutdown|confirm-force|confirm-unpair|notice]`
    /// shows a phase for screenshots. Returns true in preview mode (no network polling).
    private func previewIfRequested() -> Bool {
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment["TRUECLOUD_PREVIEW"],
              value.hasPrefix("home:") else { return false }
        let running = VmStatus(status: "running", uptime: 612, hasIP: true, ip: "192.168.1.20", cpu: 0.08,
                               mem: 4.2 * 1_073_741_824, maxmem: 19_327_352_832, netin: 1.8 * 1_073_741_824, netout: 0.4 * 1_073_741_824, isSunshineReady: true)
        var booting = running; booting.uptime = 38; booting.isSunshineReady = false; booting.cpu = 0.31; booting.mem = 2.1 * 1_073_741_824
        var starting = booting; starting.uptime = 9; starting.hasIP = false; starting.ip = nil; starting.cpu = 0.02; starting.mem = 0.4 * 1_073_741_824
        let phases: [String: (SessionService.Phase, VmStatus?)] = [
            "checking": (.checking, nil),
            "idle": (.idle, VmStatus(status: "stopped", maxmem: 19_327_352_832)),
            "starting": (.starting, starting), "booting": (.booting, booting), "ready": (.ready, running),
            "pairing": (.pairing, running), "streaming": (.streaming, running), "shutting": (.shuttingDown, running),
        ]
        let parts = value.dropFirst(5).split(separator: ":").map(String.init)
        if let entry = parts.first.flatMap({ phases[$0] }) { session.previewPhase(entry.0, status: entry.1) }
        if let name = parts.first, ["ready", "pairing", "streaming", "booting", "shutting"].contains(name) {
            session.previewTraffic(TrafficRate(downloadMBps: 1.42, uploadMBps: 0.18))
        }
        if parts.contains("stream") { pane = .stream }
        if parts.contains("network") { pane = .network }
        if parts.contains("about") { pane = .about }
        if parts.contains("logs") { pane = .logs }
        // `:controllers` opens the pane; add `:sample` for a sample controller mid-press, without hardware.
        if parts.contains("controllers") { pane = .controllers }
        if parts.contains("activity") { pane = .activity; activityModel.preview(Self.sampleActivity) }
        if parts.contains("payments") { pane = .payments; paymentsModel.preview(Self.samplePayments) }
        if parts.contains("sample") { controllerMonitor.showPreview() }
        if parts.contains("overlay") { StreamOverlayPanel.shared.begin(host: "moonlight-a2.truecloud.in:35450", profile: auth.profile) }
        if parts.contains("notice") {
            session.notice = .init(title: "Not Enough Time", message: "You need at least 3 minutes of plan time left to start. Upgrade or add time at truecloud.in.")
        }
        if parts.contains("confirm-shutdown") {
            confirm = ConfirmRequest(title: "Shut down your cloud PC?", message: "Windows closes down normally. Save your game first. Plan time stops counting once it's off.", confirmLabel: "Shut Down") {}
        }
        if parts.contains("confirm-force") {
            confirm = ConfirmRequest(title: "Force stop your cloud PC?", message: "This cuts power right away, like holding the power button. Unsaved progress is lost and Windows may need to repair itself. Use it only if Shut Down doesn't work.", confirmLabel: "Force Stop", symbol: "exclamationmark.octagon.fill") {}
        }
        if parts.contains("confirm-unpair") {
            confirm = ConfirmRequest(title: "Unpair all devices?", message: "Every Moonlight client paired with your cloud PC is removed, including this Mac. Pressing Play pairs this Mac again automatically.", confirmLabel: "Unpair", symbol: "link.badge.plus") {}
        }
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Account footer

private struct AccountFooter: View {
    let profile: RigProfile
    let refresh: () -> Void
    let dashboard: () -> Void
    let logOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanUsage(profile: profile, compact: true)

            HStack(spacing: 9) {
                ProfileBadge(profile: profile)
                Spacer(minLength: 0)
                Menu {
                    Text(profile.displayName.isEmpty ? "TrueCloud account" : profile.displayName)
                    Divider()
                    Button("Refresh Account", action: refresh)
                    Button("Open Dashboard…", action: dashboard)
                    Divider()
                    Button("Log Out", action: logOut)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Account")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
    }
}
