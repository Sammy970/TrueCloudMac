import AppKit
import Carbon.HIToolbox
import SwiftUI
import TrueCloudKit

/// The in-stream overlay on the Mac: a borderless glass panel in the top-right corner, above
/// Moonlight even in fullscreen. It never takes focus or clicks, so the stream keeps the keyboard
/// and mouse. ⌃⌥A shows or hides the card; warnings appear on their own as a toast.
@MainActor
final class StreamOverlayPanel {
    static let shared = StreamOverlayPanel()
    static let shortcut = "⌃⌥A"

    /// Moonlight's own shortcuts (Control-Option-Shift on a Mac) plus ours, listed in the card.
    static let shortcuts: [(keys: String, action: String)] = [
        ("⌃⌥⇧Z", "Release or recapture mouse and keyboard"),
        ("⌃⌥⇧M", "Switch mouse mode (game or desktop)"),
        ("⌃⌥⇧X", "Fullscreen or window"),
        ("⌃⌥⇧S", "Performance stats"),
        ("⌃⌥⇧V", "Paste Mac clipboard as text"),
        ("⌃⌥⇧D", "Minimize the stream"),
        ("⌃⌥⇧Q", "Quit the stream"),
        (shortcut, "Show or hide this card"),
    ]

    let model = StreamOverlayModel()
    private var panel: NSPanel?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var introTask: Task<Void, Never>?
    private static let size = NSSize(width: 340, height: 580)

    /// Starts the overlay when a stream begins; shows the card briefly so the shortcut is discoverable.
    func begin(host: String, profile: RigProfile?) {
        guard !model.isActive else { return }
        model.begin(host: host, profile: profile)
        showPanel()
        if !installEventTap() { registerHotKey() }
        model.cardVisible = true
        introTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.model.cardVisible = false
        }
    }

    func end() {
        guard model.isActive else { return }
        introTask?.cancel()
        model.end()
        unregisterHotKey()
        removeEventTap()
        panel?.orderOut(nil)
    }

    func toggle() {
        introTask?.cancel()
        model.cardVisible.toggle()
        if model.cardVisible { panel?.orderFrontRegardless() }
    }

    // MARK: Panel

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Top-right of the screen Moonlight is most likely on (the one with the mouse).
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        // visibleFrame keeps it below the menu bar in a window; in fullscreen the menu bar hides and it's the whole screen.
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - Self.size.width - 12, y: frame.maxY - Self.size.height - 12))
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Moonlight's fullscreen window sits at the status-bar level (25), so the overlay must be higher.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: StreamOverlayRoot(model: model, health: model.health).tint(.tcAccent))
        return panel
    }

    // MARK: Shortcut

    /// Whether ⌃⌥A also works in fullscreen. Moonlight's fullscreen mode captures system keys by
    /// switching off every global shortcut (Carbon hot keys included); an event tap still sees the
    /// keys, but macOS only allows one for apps the user trusts in Accessibility.
    static var fullscreenShortcutAllowed: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility: shows the system prompt and opens the right Settings page.
    static func requestFullscreenShortcut() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Watches key presses ahead of every app, so ⌃⌥A works even in Moonlight's fullscreen.
    /// The combination is swallowed so the cloud PC doesn't also receive Ctrl+Alt+A.
    private func installEventTap() -> Bool {
        if eventTap != nil { return true }
        guard Self.fullscreenShortcutAllowed else { return false }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Task { @MainActor in StreamOverlayPanel.shared.reenableEventTap() }
                return Unmanaged.passUnretained(event)
            }
            let modifiers = event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
            guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_A),
                  modifiers == [.maskControl, .maskAlternate] else {
                return Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                Task { @MainActor in StreamOverlayPanel.shared.toggle() }
            }
            return nil
        }, userInfo: nil) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapSource = source
        return true
    }

    private func reenableEventTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    private func removeEventTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        eventTap = nil
        eventTapSource = nil
    }

    /// Without Accessibility, a Carbon hot key still covers windowed streams.
    private func registerHotKey() {
        guard hotKey == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in StreamOverlayPanel.shared.toggle() }
            return noErr
        }, 1, &pressed, nil, &hotKeyHandler)
        let id = EventHotKeyID(signature: OSType(0x4143_4C44), id: 1) // 'ACLD'
        RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregisterHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        hotKey = nil
        hotKeyHandler = nil
    }
}

/// Card and toast stacked in the panel's top-right corner.
private struct StreamOverlayRoot: View {
    @ObservedObject var model: StreamOverlayModel
    @ObservedObject var health: StreamHealth

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if model.cardVisible {
                StreamOverlayCard(model: model, health: health, hint: StreamOverlayPanel.fullscreenShortcutAllowed
                                    ? nil : "In fullscreen, ⌃⌥A needs Accessibility: TrueCloud → Stream → Overlay.",
                                  shortcuts: StreamOverlayPanel.shortcuts)
                    // Shrinks into its corner: sliding up would push it past the panel's edge and clip its header.
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
            if let toast = model.toast {
                StreamToast(text: toast)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.cardVisible)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.toast)
    }
}
