import AppKit
import Combine
import FlingKit

/// While the panel is open, the Mac keyboard drives the TV — the same keys as the
/// Windows / Linux builds: arrows (hold to repeat), Return = OK, Delete = Back,
/// Home, + / − volume — or W A S D (E = OK, Q = Back) when that scheme is picked, Space (play/pause while casting, OK otherwise),
/// Shift+← / → seek, ⌘V pastes the clipboard text on the TV. Not paired yet but casting: ← / → seek, Space pauses.
/// On the remote's Numbers page the digit keys type digits on the TV.
///
/// Works like ScrollRemote: a local monitor, only for events in the panel's
/// window, never while a text field ("Type on TV", pairing code) is being
/// edited, never with ⌘ / ⌃ / ⌥ held.
///
/// Fling is a menu-bar (accessory) app, so macOS keeps the keyboard on the
/// frontmost app even with the panel open. The app is activated while the
/// panel is shown and handed back when it closes; Esc closes the panel.
@MainActor
final class KeyRemote {
    private let state: AppState
    private let isTarget: (NSEvent) -> Bool
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var activatedByUs = false
    private weak var popover: NSPopover?
    private var enabledSink: AnyCancellable?

    // Virtual key codes (layout-independent, so a Russian layout works the same)
    private enum K {
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        static let ret: UInt16 = 36, enter: UInt16 = 76, delete: UInt16 = 51, fwdDelete: UInt16 = 117
        static let space: UInt16 = 49, home: UInt16 = 115
        static let equal: UInt16 = 24, minus: UInt16 = 27, padPlus: UInt16 = 69, padMinus: UInt16 = 78
        static let escape: UInt16 = 53, v: UInt16 = 9
        // WASD scheme (+ E = OK, Q = Back); key positions, so any layout works
        static let w: UInt16 = 13, a: UInt16 = 0, s: UInt16 = 1, d: UInt16 = 2, q: UInt16 = 12, e: UInt16 = 14
        static let none: UInt16 = 0xFFFF
    }

    /// The chosen scheme drives the d-pad; the other one's keys are left alone.
    private static func remap(_ key: UInt16, _ scheme: KeyScheme) -> UInt16 {
        switch scheme {
        case .arrows:
            return key
        case .wasd:
            switch key {
            case K.w: return K.up
            case K.a: return K.left
            case K.s: return K.down
            case K.d: return K.right
            case K.e: return K.ret
            case K.q: return K.delete
            case K.up, K.down, K.left, K.right: return K.none
            default: return key
            }
        }
    }
    private static let repeatable: Set<UInt16> = [K.left, K.right, K.up, K.down,
                                                  K.equal, K.minus, K.padPlus, K.padMinus]
    private static let seekStep = 30
    /// Digit keys, top row and keypad → 0…9: typed on the TV while the Numbers page is open.
    private static let digits: [UInt16: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
                                                82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]

    init(state: AppState, isTarget: @escaping (NSEvent) -> Bool) {
        self.state = state
        self.isTarget = isTarget
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isTarget(event), self.handle(event) else { return event }
            return nil   // consumed: the TV got it
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSPopover.didShowNotification, object: nil,
                                        queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.panelShown(note.object as? NSPopover) }
        })
        observers.append(nc.addObserver(forName: NSPopover.didCloseNotification, object: nil,
                                        queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelClosed() }
        })
        // the ⌨ badge turns capture on / off; turning it on takes the keyboard right away
        enabledSink = KeyCapture.shared.$enabled.dropFirst().sink { [weak self] enabled in
            DispatchQueue.main.async {
                guard let self else { return }
                if enabled, let popover = self.popover, popover.isShown, !NSApp.isActive {
                    self.activatedByUs = true
                    NSApp.activate(ignoringOtherApps: true)
                }
                self.updateCapture()
            }
        }
        // the keyboard is ours only while Fling is the active app
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCapture() }
            })
        }
    }

    private func updateCapture() {
        let on = KeyCapture.shared.enabled && (popover?.isShown ?? false) && NSApp.isActive
        if KeyCapture.shared.on != on { KeyCapture.shared.on = on }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    private func panelShown(_ shown: NSPopover?) {
        if let shown { popover = shown }
        defer { updateCapture() }
        guard KeyCapture.shared.enabled, !NSApp.isActive else { return }   // off: leave the keyboard alone
        activatedByUs = true
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Give the keyboard back to the app the user was in, unless a real Fling
    /// window (onboarding, …) is still open.
    private func panelClosed() {
        KeyCapture.shared.on = false
        guard activatedByUs else { return }
        activatedByUs = false
        let otherWindows = NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled) && !$0.className.contains("Popover")
        }
        if !otherWindows { NSApp.deactivate() }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.window?.firstResponder is NSText { return false }   // typing in a field
        guard KeyCapture.shared.enabled else { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods == .command && event.keyCode == K.v && state.tvPaired {   // ⌘V: clipboard → TV
            if !event.isARepeat, let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                Task { await state.sendTVText(clip) }
            }
            return true
        }
        if event.modifierFlags.intersection([.command, .control, .option]) != [] { return false }
        let key = Self.remap(event.keyCode, KeyCapture.shared.scheme)
        if key == K.none { return false }
        if key == K.escape, let popover, popover.isShown {          // Esc: close the panel, keys go back
            popover.performClose(nil)
            return true
        }
        if event.isARepeat && !Self.repeatable.contains(key) { return true }   // swallow, don't spam
        let casting = state.panel == .casting
        let shift = event.modifierFlags.contains(.shift)

        if casting && shift && (key == K.left || key == K.right) {
            if !event.isARepeat { seek(key == K.right) }
            return true
        }
        if state.tvPaired, RemoteMode.current == .num, !shift, let d = Self.digits[event.keyCode] {
            if !event.isARepeat {
                RemoteKeyFlash.post(ATVKeyCode.digit(d))
                Task { await state.pressTVKey(ATVKeyCode.digit(d)) }
            }
            return true
        }
        if state.tvPaired {
            let code: Int32
            switch key {
            case K.up: code = ATVKeyCode.dpadUp
            case K.down: code = ATVKeyCode.dpadDown
            case K.left: code = ATVKeyCode.dpadLeft
            case K.right: code = ATVKeyCode.dpadRight
            case K.ret, K.enter: code = ATVKeyCode.dpadCenter
            case K.delete, K.fwdDelete: code = ATVKeyCode.back
            case K.home: code = ATVKeyCode.home
            case K.equal, K.padPlus: code = ATVKeyCode.volumeUp
            case K.minus, K.padMinus: code = ATVKeyCode.volumeDown
            case K.space:
                if casting {
                    Task { await state.togglePlayPause() }
                    return true
                }
                code = ATVKeyCode.dpadCenter
            default: return false
            }
            RemoteKeyFlash.post(code)
            Task { await state.pressTVKey(code) }
            return true
        }
        if casting {   // no remote yet — keep cast transport on the keys
            switch key {
            case K.left, K.right: seek(key == K.right); return true
            case K.space: Task { await state.togglePlayPause() }; return true
            default: return false
            }
        }
        return false
    }

    private func seek(_ forward: Bool) {
        let s = forward ? Self.seekStep : -Self.seekStep
        Task { await state.seek(by: s) }
    }
}

/// Whether the Mac keyboard drives the TV right now (panel open and Fling active);
/// RemoteView shows a "keyboard captured" strip while it is.
@MainActor
final class KeyCapture: ObservableObject {
    static let shared = KeyCapture()
    @Published var on = false
    /// User switch (the ⌨ badge): capture the Mac keyboard at all. On by default.
    /// Which keys move around the TV: arrows or W A S D. Arrows by default.
    @Published var scheme: KeyScheme = KeyScheme(rawValue: UserDefaults.standard.string(forKey: "keyScheme") ?? "")
                                       ?? .arrows {
        didSet { UserDefaults.standard.set(scheme.rawValue, forKey: "keyScheme") }
    }
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "keyCapture") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "keyCapture") }
    }
}

enum KeyScheme: String { case arrows, wasd }

/// Android key codes the upstream ATVKeyCode table doesn't list.
enum PortKey {
    static let enter: Int32 = 66   // KEYCODE_ENTER — runs a search typed on the TV
    static let del: Int32 = 67     // KEYCODE_DEL — backspace in a TV text field
}

/// Lights up the matching on-screen key for a moment when it was pressed on the keyboard.
enum RemoteKeyFlash {
    static let name = Notification.Name("FlingRemoteKeyFlash")
    static func post(_ code: Int32) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["code": code])
    }
}
