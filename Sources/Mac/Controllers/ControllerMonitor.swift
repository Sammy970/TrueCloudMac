import CoreHaptics
import Foundation
import GameController
import IOKit.hid

/// A connected controller as the Controllers pane shows it.
struct ConnectedController: Identifiable, Equatable {
    enum Verdict: Equatable {
        /// Moonlight will use it: its ID is in SDL's lists, or macOS itself drives it.
        case ready(knownAs: String?)
        /// Connected, but neither SDL's lists nor macOS know it, so Moonlight may not use it.
        case unknown
    }

    let id: String
    var name: String
    var vendorID: Int?
    var productID: Int?
    var transport: String?
    var battery: Float?
    var charging = false
    var style = PadStyle.xbox
    /// False for gamepads only seen through IOKit: macOS shows no live input for them.
    var live: Bool
    var canVibrate = false
    var state = PadState()
    var verdict: Verdict

    var ids: String? {
        guard let vendorID, let productID else { return nil }
        return String(format: "%04X:%04X", vendorID, productID)
    }
}

/// Watches connected game controllers for the Controllers pane: live input through Apple's GameController
/// framework, and every USB/Bluetooth gamepad through IOKit, each checked against the controllers Moonlight
/// recognises on a Mac.
///
/// Moonlight on a Mac reads controllers through SDL, not Apple's framework, so recognising one takes either an
/// SDL mapping for its ID (`KnownControllers`), an SDL driver for its maker (Xbox, PlayStation, Switch, Steam),
/// or macOS supporting it natively (SDL then uses Apple's framework too).
@MainActor
final class ControllerMonitor: ObservableObject {
    @Published private(set) var controllers: [ConnectedController] = []

    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var hidManager: IOHIDManager?
    private var preview = false

    /// Makers whose controllers SDL drives itself, whatever the model: Microsoft, Sony, Nintendo, Valve.
    private static let sdlDriverVendors: Set<Int> = [0x045E, 0x054C, 0x057E, 0x28DE]

    func start() {
        guard !preview else { return }
        GCController.shouldMonitorBackgroundEvents = true
        if observers.isEmpty {
            let center = NotificationCenter.default
            for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                })
            }
        }
        openHID()
        refresh()
        // Sixty times a second while the pane is open; the drawing only redraws when something changed.
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Screenshot mode: a sample Xbox controller mid-press, without any hardware.
    func showPreview() {
        preview = true
        var state = PadState()
        state.pressed = [.a, .rightShoulder]
        state.leftStick = CGPoint(x: 0.55, y: 0.35)
        state.rightTrigger = 0.7
        controllers = [ConnectedController(
            id: "preview", name: "Xbox Wireless Controller", vendorID: 0x045E, productID: 0x02E0,
            transport: "Bluetooth", battery: 0.8, style: .xbox, live: true, canVibrate: true, state: state,
            verdict: .ready(knownAs: "Xbox Wireless Controller"))]
    }

    // MARK: Listing

    private func refresh() {
        let hid = hidDevices()
        var claimed = Set<String>()
        var list: [ConnectedController] = []

        for (index, controller) in GCController.controllers().enumerated() {
            guard controller.extendedGamepad != nil else { continue }
            let name = controller.vendorName ?? "Controller"
            // Apple's framework doesn't expose IDs; match the IOKit device by name to get them.
            let match = hid.first { $0.name == name && !claimed.contains($0.key) }
            if let match { claimed.insert(match.key) }
            let style = PadStyle(controller)
            list.append(ConnectedController(
                id: "gc-\(index)-\(name)", name: name, vendorID: match?.vendor, productID: match?.product,
                transport: match?.transport,
                // Controllers that don't report battery read 0% with an unknown state; show nothing for those.
                battery: controller.battery.flatMap { $0.batteryState == .unknown ? nil : $0.batteryLevel },
                charging: controller.battery?.batteryState == .charging, style: style, live: true,
                canVibrate: controller.haptics != nil,
                // macOS drives it natively, so SDL does too.
                verdict: .ready(knownAs: match.flatMap { Self.knownName(vendor: $0.vendor, product: $0.product) })))
        }

        for device in hid where !claimed.contains(device.key) {
            let known = Self.knownName(vendor: device.vendor, product: device.product)
            let verdict: ConnectedController.Verdict = known != nil || Self.sdlDriverVendors.contains(device.vendor)
                ? .ready(knownAs: known) : .unknown
            list.append(ConnectedController(
                id: "hid-\(device.key)", name: device.name, vendorID: device.vendor, productID: device.product,
                transport: device.transport, live: false, verdict: verdict))
        }

        // Keep each controller's last input when the list refreshes.
        for i in list.indices {
            if let old = controllers.first(where: { $0.id == list[i].id }) { list[i].state = old.state }
        }
        if list != controllers { controllers = list }
        Log.info("[controllers] \(list.map { "\($0.name) [\($0.ids ?? "no ID")] \($0.verdict)" })")
    }

    static func knownName(vendor: Int, product: Int) -> String? {
        KnownControllers.names[UInt32(vendor) << 16 | UInt32(product)]
    }

    // MARK: Live input

    private func poll() {
        let pads = GCController.controllers().compactMap(\.extendedGamepad)
        var changed = false
        var updated = controllers
        var live = 0
        for i in updated.indices where updated[i].live {
            guard live < pads.count else { break }
            let state = PadState(pads[live])
            live += 1
            if state != updated[i].state {
                updated[i].state = state
                changed = true
            }
        }
        if changed { controllers = updated }
    }

    // MARK: Vibration

    private var hapticEngine: CHHapticEngine?

    /// A short buzz on the controller, to check its motors.
    func vibrate(_ controller: ConnectedController) {
        guard controller.live, controller.canVibrate,
              let index = controllers.filter(\.live).firstIndex(where: { $0.id == controller.id }) else { return }
        let gcControllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        guard index < gcControllers.count, let haptics = gcControllers[index].haptics,
              let engine = haptics.createEngine(withLocality: .default) else { return }
        do {
            try engine.start()
            let buzz = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            ], relativeTime: 0, duration: 0.5)
            let player = try engine.makePlayer(with: CHHapticPattern(events: [buzz], parameters: []))
            try player.start(atTime: 0)
            hapticEngine = engine
        } catch {
            Log.info("[controllers] vibration failed: \(error.localizedDescription)")
        }
    }

    // MARK: IOKit

    private struct HIDDevice {
        let key: String
        let name: String
        let vendor: Int
        let product: Int
        let transport: String?
    }

    private func openHID() {
        guard hidManager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let usages = [kHIDUsage_GD_GamePad, kHIDUsage_GD_Joystick, kHIDUsage_GD_MultiAxisController].map {
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: $0] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, usages as CFArray)
        // Listing devices doesn't need them opened (or Input Monitoring permission); this only reads their properties.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let changed: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<ControllerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, changed, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, changed, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        hidManager = manager
    }

    private func hidDevices() -> [HIDDevice] {
        guard let manager = hidManager, let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.compactMap { device in
            func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
            guard let vendor = property(kIOHIDVendorIDKey) as? Int, let product = property(kIOHIDProductIDKey) as? Int else { return nil }
            let location = property(kIOHIDLocationIDKey) as? Int ?? 0
            return HIDDevice(
                key: "\(vendor)-\(product)-\(location)",
                name: property(kIOHIDProductKey) as? String ?? "Gamepad",
                vendor: vendor, product: product,
                transport: (property(kIOHIDTransportKey) as? String).map { $0 == "USB" ? "USB" : $0.contains("Bluetooth") ? "Bluetooth" : $0 })
        }
        .sorted { $0.key < $1.key }
    }
}
