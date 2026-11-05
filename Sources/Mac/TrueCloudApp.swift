import SwiftUI
import TrueCloudKit

@main
struct TrueCloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup("TrueCloud") {
            RootView()
                .environmentObject(auth)
                .tint(.tcAccent)
                #if DEBUG
                // Snapshots are taken from a background process, so draw controls as if the window were active.
                .environment(\.controlActiveState, ProcessInfo.processInfo.environment["TRUECLOUD_SNAPSHOT"] != nil ? .key : .active)
                #endif
                .frame(minWidth: 760, minHeight: 600)
                .task {
                    if !startPreview() { await auth.restore() }
                }
        }
        .defaultSize(width: 1000, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            // The About pane (version, credits) replaces the standard About panel.
            CommandGroup(replacing: .appInfo) {
                Button("About TrueCloud") { NotificationCenter.default.post(name: .showAbout, object: nil) }
            }
        }
    }

    /// Debug builds only: `TRUECLOUD_PREVIEW=login` or `home:<phase>` renders a state for screenshots
    /// with a fake profile, without reading the Keychain or calling any API.
    private func startPreview() -> Bool {
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment["TRUECLOUD_PREVIEW"] else { return false }
        if let icon = NSImage(contentsOfFile: "TrueCloud.icns") { NSApp.applicationIconImage = icon }
        if ProcessInfo.processInfo.environment["TRUECLOUD_APPEARANCE"] == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
        // The plan ends in 25 days; `:expiring` makes it 3 and `:expired` yesterday, to see the warnings.
        let daysLeft: Double = value.contains(":expired") ? -1 : value.contains(":expiring") ? 3.2 : 25.6
        auth.previewSignIn(value == "login" ? nil : RigProfile(
            uid: "preview", displayName: "Samyak Jain", node: "truecloud-2", vmid: 754,
            moonlightHost: "moonlight-a2.truecloud.in", currentPlan: "Basic ",
            hoursRemaining: 3.95, planHours: 10, dailyLimitHours: 2, subscription: true, autoRenew: true,
            hasPairedBefore: true, expiration: Date.now.addingTimeInterval(daysLeft * 86_400)))
        return true
        #else
        return false
        #endif
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running as a bare SwiftPM executable needs this to get a Dock icon and key window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        // `TRUECLOUD_SNAPSHOT=<file.png>` saves the window once it has settled, then quits.
        if let path = ProcessInfo.processInfo.environment["TRUECLOUD_SNAPSHOT"] {
            for delay in [0.4, 1.0, 1.8] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    // Snapshot the window as the active one, so controls show their accent colours.
                    NSApp.activate(ignoringOtherApps: true)
                    let window = NSApp.windows.first(where: \.isVisible)
                    window?.makeKeyAndOrderFront(nil)
                    window?.makeMain()
                }
            }
            let delay = Double(ProcessInfo.processInfo.environment["TRUECLOUD_SNAPSHOT_DELAY"] ?? "") ?? 3.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if let view = NSApp.windows.first(where: \.isVisible)?.contentView?.superview,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Notification.Name {
    /// Opens the About pane (from the app menu).
    static let showAbout = Notification.Name("TrueCloudShowAbout")
}
