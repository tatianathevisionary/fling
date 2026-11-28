import SwiftUI
import Combine
import FlingKit

/// The TV section of the panel: power, app launcher, d-pad, volume keys, and
/// typing, all over the Android TV Remote session.
///
/// Typing is a keyboard button (live typing, send on Return, paste) rather than an
/// always-visible field. Text goes through `sendTVText` / the Android TV Remote IME.
struct RemoteView: View {
    @ObservedObject var state: AppState
    @State private var typed = ""
    @State private var showTypeField = false
    @AppStorage("typeLive") private var liveTyping = true
    @State private var liveSent = ""                 // what the TV field holds now (live mode)
    @State private var liveTask: Task<Void, Never>?
    @FocusState private var typeFocused: Bool
    @ObservedObject private var capture = KeyCapture.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showBadge && !state.tvPaired && state.panel == .casting {
                keyboardBadge   // no TV header yet — sit quietly at the top
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 14).padding(.top, 8)
            }
            switch state.tvPairing {
            case .starting:
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(tr("Contacting TV…")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            case .waitingForPIN, .verifying:
                TVPinEntry(state: state)
            case .idle, .failed:
                if state.tvPaired { controls } else { setup }
                if case .failed(let why) = state.tvPairing {
                    Text(tr(why))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.bottom, 7)
                }
            }
        }
    }

    /// Says so while the Mac keyboard goes to the TV instead of the app the user was in.
    /// How to drive the TV from the Mac keyboard; follows the arrows / WASD switch.
    private var keyLegend: some View {
        let lines: [String] = capture.scheme == .wasd ? [
            "WASD move · E ⏎ OK · Q ⌫ back · ± vol",
            "space pause · ⇧A D seek · ⌘V paste · esc exit",
        ] : [
            "↑↓←→ move · ⏎ OK · ⌫ back · ± vol",
            "space pause · ⇧← → seek · ⌘V paste · esc exit",
        ]
        return VStack(spacing: 0) {
            ForEach(lines, id: \.self) { Text(tr($0)) }
        }
        .font(.system(size: 9)).foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .id(capture.scheme)
        .transition(.opacity)
    }

    /// Two-position switch under the d-pad: arrow keys ↔ W A S D.
    private var schemeSwitch: some View {
        HStack(spacing: 0) {
            schemeOption(.arrows) { Image(systemName: "arrowkeys").font(.system(size: 9.5)) }
                .help(tr("Move with the arrow keys"))
            schemeOption(.wasd) { Text(tr("WASD")).font(.system(size: 8, weight: .bold, design: .rounded)) }
                .help(tr("Move with W A S D (E = OK, Q = Back)"))
        }
        .padding(1.5)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func schemeOption<L: View>(_ scheme: KeyScheme, @ViewBuilder label: () -> L) -> some View {
        let on = capture.scheme == scheme
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { capture.scheme = scheme }
        } label: {
            label()
                .foregroundStyle(on ? Color.primary : Color.secondary)
                .frame(width: 30, height: 15)
                .background(on ? Color.accentColor.opacity(0.25) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr(scheme == .wasd ? "WASD" : "Arrow keys"))
    }

    private var keysCaptured: Bool { capture.on && !typeFocused }
    /// Badge shows while the keyboard is captured, and always when capture is off
    /// (so it can be turned back on).
    private var showBadge: Bool { !typeFocused && (capture.on || !capture.enabled) }

    /// Quiet switch for the Mac keyboard → TV capture: a small grey "⌨ esc"
    /// beside the power key (click = off), "⌨ off" when it's off (click = on).
    private var keyboardBadge: some View {
        Button {
            capture.enabled.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: capture.enabled ? "keyboard" : "keyboard.badge.ellipsis")
                    .font(.system(size: 9))
                Text(tr(capture.enabled ? "esc" : "off"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .strikethrough(!capture.enabled)
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr(!capture.enabled ? "Keyboard capture is off — click to control the TV from the Mac keyboard"
              : state.tvPaired ? "Keyboard captured — keys go to the TV. Esc releases it. Click to turn capture off"
                               : "Keyboard captured — ← → seek, Space pauses. Esc releases it. Click to turn capture off"))
        .transition(.opacity)
    }

    // MARK: - unpaired

    private var setup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("Pair once with the TV to unlock apps, the d-pad, and typing."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
            MenuRow(title: "Turn TV On", icon: "power") { Task { await state.wakeTV() } }
            MenuRow(title: "Set Up TV Power…", icon: "dot.radiowaves.left.and.right",
                    accented: true) {
                Task { await state.startTVPairing() }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - paired

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            appGrid
            RemoteModes(state: state) { dpad }           // Arrows · Touchpad · Numbers · Media
            if let vol = state.tvVolume {
                TVVolumeRow(state: state, volume: vol)   // the TV reports its volume: a slider
            } else {
                volumeKeys
            }
            typeRow
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "ON THE TV")
                if let subtitle = headerSubtitle {
                    Text(tr(subtitle))
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            Spacer()
            if showBadge { keyboardBadge }
            KeyButton(symbol: "power", size: 26, state: state, code: ATVKeyCode.power)
                .help(tr(powerHelp))
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
    }

    private var headerSubtitle: String? {
        if let package = state.tvCurrentApp { return "Now: \(TVApp.displayName(forPackage: package))" }
        if state.tvIsOn == false { return "TV is off" }
        return nil
    }

    private var powerHelp: String {
        switch state.tvIsOn {
        case true?:  return "Turn TV off"
        case false?: return "Turn TV on"
        case nil:    return "Toggle TV power"
        }
    }

    private var appGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                  spacing: 4) {
            ForEach(TVApp.catalog) { app in
                AppChip(name: app.name, active: app.package == state.tvCurrentApp) {
                    Task { await state.launchTVApp(app) }
                }
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    /// Classic remote layout — Back and Home flank the OK row.
    private var dpad: some View {
        VStack(spacing: 6) {
            KeyButton(symbol: "chevron.up", size: 30, state: state, code: ATVKeyCode.dpadUp)
            HStack(spacing: 13) {
                KeyButton(symbol: "arrow.uturn.backward", size: 30,
                          state: state, code: ATVKeyCode.back)
                    .help(tr("Back"))
                KeyButton(symbol: "chevron.left", size: 30, state: state, code: ATVKeyCode.dpadLeft)
                KeyButton(label: "OK", size: 40, accented: true,
                          state: state, code: ATVKeyCode.dpadCenter)
                KeyButton(symbol: "chevron.right", size: 30, state: state, code: ATVKeyCode.dpadRight)
                KeyButton(symbol: "house", size: 30, state: state, code: ATVKeyCode.home)
                    .help(tr("Home"))
            }
            KeyButton(symbol: "chevron.down", size: 30, state: state, code: ATVKeyCode.dpadDown)
            schemeSwitch.padding(.top, 2)
            keyLegend
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6).padding(.bottom, 8)
    }

    private var volumeKeys: some View {
        HStack(spacing: 5) {
            KeyPill(symbol: "speaker.minus", label: "Vol −",
                    state: state, code: ATVKeyCode.volumeDown)
            KeyPill(symbol: "speaker.slash", label: "Mute",
                    state: state, code: ATVKeyCode.volumeMute)
            KeyPill(symbol: "speaker.plus", label: "Vol +",
                    state: state, code: ATVKeyCode.volumeUp)
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
    }

    /// Keyboard icon reveals the type field; mic stays beside it.
    /// Transport unchanged: `AppState.sendTVText` → Android TV Remote IME.
    /// Keyboard button, three ways to get text onto the TV:
    ///  • Live (default): every letter shows up on the TV as you type; Return
    ///    presses Enter on the TV (runs the search).
    ///  • Send on Return: type the whole phrase, Return sends it at once.
    ///  • Paste: the clipboard text goes to the TV (button, menu, or ⌘V).
    /// Right-click the keyboard button to switch Live on / off.
    /// Transport unchanged: `AppState.sendTVText` → Android TV Remote IME
    /// (the IME edit carries the whole field value, so live sends the full text).
    private var typeRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showTypeField.toggle()
                    }
                    if showTypeField {
                        DispatchQueue.main.async { typeFocused = true }
                    } else {
                        resetTyping()
                    }
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 22)
                .background(showTypeField ? Color.accentColor.opacity(0.22)
                                          : Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 5))
                .help(tr(showTypeField ? "Hide keyboard" : "Keyboard — type on the TV (right-click for options)"))
                .accessibilityLabel(tr(showTypeField ? "Hide keyboard" : "Show keyboard"))
                .contextMenu {
                    Button(tr(liveTyping ? "✓ Live — letters appear as you type" : "Live — letters appear as you type")) {
                        liveTyping = true
                    }
                    Button(tr(liveTyping ? "Send on Return" : "✓ Send on Return")) { liveTyping = false }
                    Divider()
                    Button(tr("Paste clipboard on the TV")) { pasteClipboard() }
                }

                if showTypeField {
                    TextField(tr(liveTyping ? "Type — shows on the TV live" : "Type, Return sends"), text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($typeFocused)
                        .onSubmit { submitTyped() }
                        .help(tr("Lands in whatever text field is focused on the TV"))
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                        .onChange(of: typed) { _, text in if liveTyping { scheduleLive(text) } }

                    smallIcon(liveTyping ? "bolt.fill" : "bolt.slash",
                              tint: liveTyping ? Color.accentColor : Color.primary,
                              help: liveTyping ? "Live typing is on — click to send on Return instead"
                                               : "Live typing is off — click to turn on") {
                        liveTyping.toggle()
                    }
                    smallIcon("doc.on.clipboard", help: "Paste clipboard on the TV  (⌘V)") {
                        pasteClipboard()
                    }
                }

                Button {
                    Task { await state.toggleVoiceSearch() }
                } label: {
                    Image(systemName: state.tvVoiceActive ? "mic.fill" : "mic")
                        .font(.system(size: 11.5))
                        .foregroundStyle(state.tvVoiceActive ? Color.red : Color.primary)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 22)
                .background(state.tvVoiceActive ? Color.red.opacity(0.15)
                                                : Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 5))
                .help(tr(state.tvVoiceActive ? "Stop voice search" : "Voice search"))
            }
            if state.tvVoiceActive {
                Text(tr("Listening — click the mic again when done."))
                    .font(.system(size: 10)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 9)
        .onChange(of: state.tvPaired) { _, paired in
            if !paired {
                showTypeField = false
                resetTyping()
            }
        }
    }

    private func smallIcon(_ symbol: String, tint: Color = .primary, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
        .help(tr(help))
    }

    /// Live: send the whole field shortly after the last keystroke (a fast typist
    /// doesn't flood the TV). Emptying the field deletes what's left on the TV.
    private func scheduleLive(_ text: String) {
        liveTask?.cancel()
        liveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, text != liveSent else { return }
            if text.isEmpty {
                for _ in 0..<max(1, liveSent.count) { await state.pressTVKey(PortKey.del) }
            } else {
                await state.sendTVText(text)
            }
            liveSent = text
        }
    }

    private func submitTyped() {
        if liveTyping {
            // text is already on the TV — Return runs it (search / OK), field starts fresh
            liveTask?.cancel()
            let pending = typed
            Task { @MainActor in
                if !pending.isEmpty, pending != liveSent { await state.sendTVText(pending) }
                await state.pressTVKey(PortKey.enter)
            }
            typed = ""; liveSent = ""
            return
        }
        let text = typed
        typed = ""
        guard !text.isEmpty else { return }
        Task { await state.sendTVText(text) }
    }

    private func pasteClipboard() {
        guard let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty else {
            state.lastError = "Clipboard is empty"
            return
        }
        if showTypeField && liveTyping {
            typed = clip                       // live path sends it
        } else {
            Task { await state.sendTVText(clip) }
        }
    }

    private func resetTyping() {
        liveTask?.cancel()
        typed = ""; liveSent = ""
        typeFocused = false
    }
}

// MARK: - controls

/// The TV's own volume as a slider, on the
/// TV's scale (some go to 15 or 60, not 100) shown in percent. Dragging walks
/// the TV there with volume keys; a bubble over the knob shows the level.
/// The speaker toggles mute. Shown only when the TV reports its volume.
struct TVVolumeRow: View {
    @ObservedObject var state: AppState
    let volume: TVVolume
    @State private var dragValue: Double?

    private var shown: Double { dragValue ?? Double(state.tvVolumeTarget ?? volume.level) }
    private func pct(_ v: Double) -> Int { Int((100 * v / Double(max(volume.max, 1))).rounded()) }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                Task { await state.pressTVKey(ATVKeyCode.volumeMute) }
            } label: {
                Image(systemName: volume.muted || shown == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(volume.muted ? Color.orange : Color.secondary)
                    .frame(width: 15, height: 15)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tr("TV sound: click to mute / unmute"))

            BubbleSlider(value: shown, range: 0...Double(volume.max), label: { "\(pct($0))%" },
                         onChange: { v in
                             dragValue = v
                             state.setTVVolume(Int(v.rounded()))
                         },
                         onEnd: { dragValue = nil })
                .opacity(volume.muted ? 0.45 : 1)

            Text(tr("\(pct(shown))%"))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)
        }
        .help(tr("TV volume"))
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
    }
}

/// The author's SlimSlider look (thin track, white knob) plus a small bubble
/// above the knob with the level while it is dragged.
struct BubbleSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let label: (Double) -> String
    let onChange: (Double) -> Void
    let onEnd: () -> Void
    @State private var dragging = false
    private let knob: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = max(range.upperBound - range.lowerBound, 1)
            let frac = CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
            let x = min(max(0, w * frac - knob / 2), w - knob)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.18)).frame(height: 3)
                Capsule().fill(Color.primary.opacity(0.85))
                    .frame(width: max(0, w * frac), height: 3)
                Circle().fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                    .scaleEffect(dragging ? 1.15 : 1)
                    .offset(x: x)
                if dragging {
                    Text(tr(label(value)))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .fixedSize()
                        .frame(width: 40)
                        .offset(x: x + knob / 2 - 20, y: -17)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging { withAnimation(.easeOut(duration: 0.1)) { dragging = true } }
                        let f = min(1, max(0, g.location.x / max(w, 1)))
                        let v = (range.lowerBound + Double(f) * span).rounded()
                        if v != value { onChange(v) }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.15)) { dragging = false }
                        onEnd()
                    }
            )
        }
        .frame(height: knob)
    }
}

/// Round icon key for the d-pad cluster and power.
struct KeyButton: View {
    var symbol: String? = nil
    var label: String? = nil
    var size: CGFloat = 32
    var accented = false
    @ObservedObject var state: AppState
    let code: Int32

    @State private var hovering = false
    @State private var flash = false   // pressed on the Mac keyboard (KeyRemote)

    var body: some View {
        Button {
            Task { await state.pressTVKey(code) }
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: size * 0.36, weight: .semibold))
                } else {
                    Text(tr(label ?? "")).font(.system(size: size * 0.3, weight: .semibold))
                }
            }
            .foregroundStyle(accented ? Color.accentColor : Color.primary)
            .frame(width: size, height: size)
            .background(
                Circle().fill(flash ? Color.accentColor.opacity(0.35)
                              : hovering ? Color.accentColor.opacity(0.22)
                                         : Color.primary.opacity(accented ? 0.1 : 0.07))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onReceive(NotificationCenter.default.publisher(for: RemoteKeyFlash.name)) { note in
            guard note.userInfo?["code"] as? Int32 == code else { return }
            flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { flash = false }
        }
    }
}

/// Wide pill key: Back/Home and the volume cluster.
struct KeyPill: View {
    let symbol: String
    let label: String
    @ObservedObject var state: AppState
    let code: Int32

    @State private var hovering = false

    var body: some View {
        Button {
            Task { await state.pressTVKey(code) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(tr(label)).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(hovering ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// App launcher chip; `active` marks the app the TV reports as foreground.
struct AppChip: View {
    let name: String
    var active = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(tr(name))
                .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(active ? Color.accentColor.opacity(0.18)
                            : hovering ? Color.accentColor.opacity(0.2)
                                       : Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
