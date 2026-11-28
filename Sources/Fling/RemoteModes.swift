import SwiftUI
import AppKit
import FlingKit

/// The pages under the app grid. Remembered in UserDefaults; KeyRemote reads
/// it too (on the Numbers page the Mac's digit keys type digits on the TV).
enum RemoteMode: String, CaseIterable {
    case dpad, touch, num, media
    static let defaultsKey = "remoteMode"

    var title: String {
        switch self {
        case .dpad: return "Arrows"
        case .touch: return "Touchpad"
        case .num: return "Numbers"
        case .media: return "Media"
        }
    }

    static var current: RemoteMode {
        RemoteMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .dpad
    }
}

/// A segmented switch under the app grid — Arrows (the d-pad), Touchpad,
/// Numbers, Media — over pages laid in one ZStack, so the panel keeps its
/// height when switching.
struct RemoteModes<Arrows: View>: View {
    @ObservedObject var state: AppState
    @ViewBuilder let arrows: () -> Arrows
    @AppStorage(RemoteMode.defaultsKey) private var modeRaw = RemoteMode.dpad.rawValue

    private var mode: RemoteMode { RemoteMode(rawValue: modeRaw) ?? .dpad }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                ForEach(RemoteMode.allCases, id: \.self) { m in Text(tr(m.title)).tag(m) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 30).padding(.top, 2)
            .help(tr("Remote: arrows, touchpad, number keys or media keys"))

            ZStack {
                page(.dpad) { arrows() }
                page(.touch) { TouchpadPage(state: state) }
                page(.num) { NumbersPage(state: state) }
                page(.media) { MediaPage(state: state) }
            }
        }
    }

    private func page<P: View>(_ m: RemoteMode, @ViewBuilder _ content: () -> P) -> some View {
        let on = m == mode
        return content()
            .frame(maxWidth: .infinity)
            .opacity(on ? 1 : 0)
            .allowsHitTesting(on)
            .accessibilityHidden(!on)
    }
}

// MARK: - touchpad

/// Back · the pad · Home. Drag on the pad = arrows, click = OK, right-click = Back,
/// middle-click = Home. (Two-finger scrolling anywhere on the panel moves too: ScrollRemote.)
private struct TouchpadPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            KeyButton(symbol: "arrow.uturn.backward", size: 30, state: state, code: ATVKeyCode.back)
                .help(tr("Back"))
            Touchpad(state: state)
                .frame(width: 196, height: 140)
            KeyButton(symbol: "house", size: 30, state: state, code: ATVKeyCode.home)
                .help(tr("Home"))
        }
        .padding(.top, 10).padding(.bottom, 8)
    }
}

private struct Touchpad: View {
    @ObservedObject var state: AppState
    @State private var finger: CGPoint?
    @State private var flash: Int32?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(finger != nil ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.045))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            if finger == nil {
                Text(tr("Drag on the pad for arrows\nClick for OK, right-click for Back"))
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(10)
            }
            GeometryReader { geo in
                if let f = finger {
                    Circle().fill(Color.accentColor.opacity(0.5))
                        .frame(width: 14, height: 14)
                        .position(f)
                }
                if let flash { edge(flash, in: geo.size) }
            }
            .allowsHitTesting(false)
            TouchpadSurface(onKey: press, onFinger: { finger = $0 })
        }
        .help(tr("Touchpad: drag for arrows, click for OK, right-click for Back, middle-click for Home"))
    }

    /// A short glow on the edge that was "pressed".
    @ViewBuilder private func edge(_ code: Int32, in size: CGSize) -> some View {
        let glow = Color.accentColor.opacity(0.4)
        switch code {
        case ATVKeyCode.dpadUp:
            Capsule().fill(glow).frame(width: size.width * 0.4, height: 4).position(x: size.width / 2, y: 6)
        case ATVKeyCode.dpadDown:
            Capsule().fill(glow).frame(width: size.width * 0.4, height: 4).position(x: size.width / 2, y: size.height - 6)
        case ATVKeyCode.dpadLeft:
            Capsule().fill(glow).frame(width: 4, height: size.height * 0.4).position(x: 6, y: size.height / 2)
        case ATVKeyCode.dpadRight:
            Capsule().fill(glow).frame(width: 4, height: size.height * 0.4).position(x: size.width - 6, y: size.height / 2)
        case ATVKeyCode.dpadCenter:
            Circle().fill(glow).frame(width: 32, height: 32).position(x: size.width / 2, y: size.height / 2)
        default:
            EmptyView()
        }
    }

    private func press(_ code: Int32) {
        Task { await state.pressTVKey(code) }
        flash = code
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { if flash == code { flash = nil } }
    }
}

/// AppKit view for the pad: SwiftUI gestures don't see the right / middle buttons.
private struct TouchpadSurface: NSViewRepresentable {
    let onKey: (Int32) -> Void
    let onFinger: (CGPoint?) -> Void

    func makeNSView(context: Context) -> PadView {
        let v = PadView()
        v.onKey = onKey; v.onFinger = onFinger
        return v
    }

    func updateNSView(_ v: PadView, context: Context) {
        v.onKey = onKey; v.onFinger = onFinger
    }

    final class PadView: NSView {
        var onKey: (Int32) -> Void = { _ in }
        var onFinger: (CGPoint?) -> Void = { _ in }
        private var nav = TouchpadNav()
        private var start: CGPoint?
        private var last: CGPoint?
        private var moved = false
        private var downAt: TimeInterval = 0

        override var isFlipped: Bool { true }                 // y grows downwards, like SwiftUI
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() { addCursorRect(bounds, cursor: start == nil ? .openHand : .closedHand) }

        private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

        override func mouseDown(with e: NSEvent) {
            let p = point(e)
            start = p; last = p; moved = false
            downAt = e.timestamp
            nav.reset()
            NSCursor.closedHand.set()
            onFinger(p)
        }

        override func mouseDragged(with e: NSEvent) {
            guard let s = start, let l = last else { return }
            let p = point(e)
            for key in nav.drag(dx: p.x - l.x, dy: p.y - l.y) { onKey(key) }
            last = p
            if abs(p.x - s.x) + abs(p.y - s.y) > 6 { moved = true }
            onFinger(CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height)))
        }

        override func mouseUp(with e: NSEvent) {
            guard start != nil else { return }
            if !moved && e.timestamp - downAt < 0.6 { onKey(ATVKeyCode.dpadCenter) }
            start = nil; last = nil
            NSCursor.openHand.set()
            window?.invalidateCursorRects(for: self)
            onFinger(nil)
        }

        override func rightMouseDown(with e: NSEvent) { onKey(ATVKeyCode.back) }
        override func otherMouseDown(with e: NSEvent) { onKey(ATVKeyCode.home) }
    }
}

// MARK: - numbers

/// Digits with Back / OK, channel ±, and Input · Guide · Info · Settings. The Mac's digit
/// keys type digits too while this page is open (KeyRemote).
private struct NumbersPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(0..<3) { r in
                    GridRow {
                        ForEach(1...3, id: \.self) { c in
                            let d = r * 3 + c
                            KeyButton(label: "\(d)", size: 30, state: state, code: ATVKeyCode.digit(d))
                        }
                    }
                }
                GridRow {
                    KeyButton(symbol: "arrow.uturn.backward", size: 30, state: state, code: ATVKeyCode.back)
                        .help(tr("Back"))
                    KeyButton(label: "0", size: 30, state: state, code: ATVKeyCode.digit(0))
                    KeyButton(label: "OK", size: 30, accented: true, state: state, code: ATVKeyCode.dpadCenter)
                }
            }
            VStack(spacing: 5) {
                KeyButton(symbol: "chevron.up", size: 30, state: state, code: ATVKeyCode.channelUp)
                    .help(tr("Channel +"))
                Text(tr("CH")).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.tertiary)
                KeyButton(symbol: "chevron.down", size: 30, state: state, code: ATVKeyCode.channelDown)
                    .help(tr("Channel −"))
            }
            VStack(spacing: 5) {
                TextKey(title: "Input", help: "Input source (HDMI, antenna…)", state: state, code: ATVKeyCode.tvInput)
                TextKey(title: "Guide", help: "TV guide", state: state, code: ATVKeyCode.guide)
                TextKey(title: "Info", help: "Programme info", state: state, code: ATVKeyCode.info)
                TextKey(title: "Settings", help: "TV settings", state: state, code: ATVKeyCode.settings)
            }
            .frame(width: 84)
        }
        .padding(.top, 10).padding(.bottom, 8)
    }
}

// MARK: - media

private struct MediaPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                KeyButton(symbol: "backward.end.fill", size: 30, state: state, code: ATVKeyCode.mediaPrevious)
                    .help(tr("Previous track"))
                KeyButton(symbol: "backward.fill", size: 34, state: state, code: ATVKeyCode.mediaRewind)
                    .help(tr("Rewind"))
                playPause
                KeyButton(symbol: "forward.fill", size: 34, state: state, code: ATVKeyCode.mediaFastForward)
                    .help(tr("Fast-forward"))
                KeyButton(symbol: "forward.end.fill", size: 30, state: state, code: ATVKeyCode.mediaNext)
                    .help(tr("Next track"))
            }
            HStack(spacing: 6) {
                KeyButton(symbol: "stop.fill", size: 28, state: state, code: ATVKeyCode.mediaStop)
                    .help(tr("Stop"))
                TextKey(title: "Subtitles", state: state, code: ATVKeyCode.captions)
                TextKey(title: "Audio track", state: state, code: ATVKeyCode.mediaAudioTrack)
            }
            .fixedSize()
            HStack(spacing: 8) {
                ColorKey(color: Color(red: 0.90, green: 0.28, blue: 0.25), help: "Red button", state: state, code: ATVKeyCode.progRed)
                ColorKey(color: Color(red: 0.20, green: 0.71, blue: 0.35), help: "Green button", state: state, code: ATVKeyCode.progGreen)
                ColorKey(color: Color(red: 0.91, green: 0.76, blue: 0.18), help: "Yellow button", state: state, code: ATVKeyCode.progYellow)
                ColorKey(color: Color(red: 0.23, green: 0.48, blue: 0.88), help: "Blue button", state: state, code: ATVKeyCode.progBlue)
            }
            Text(tr("Colour buttons — for TV channels and teletext"))
                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
        }
        .padding(.top, 12).padding(.bottom, 8)
    }

    /// While casting, Play / Pause drives the cast (the TV's key may not reach it).
    private var playPause: some View {
        Button {
            Task {
                if state.panel == .casting { await state.togglePlayPause() }
                else { await state.pressTVKey(ATVKeyCode.mediaPlayPause) }
            }
        } label: {
            Image(systemName: "playpause.fill").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tr("Play / Pause"))
    }
}

// MARK: - keys

/// A rounded key with a word on it.
private struct TextKey: View {
    let title: String
    var help: String? = nil
    @ObservedObject var state: AppState
    let code: Int32
    @State private var hovering = false

    var body: some View {
        Button {
            Task { await state.pressTVKey(code) }
        } label: {
            Text(tr(title))
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(hovering ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tr(help ?? title))
    }
}

private struct ColorKey: View {
    let color: Color
    let help: String
    @ObservedObject var state: AppState
    let code: Int32
    @State private var hovering = false

    var body: some View {
        Button {
            Task { await state.pressTVKey(code) }
        } label: {
            Capsule().fill(color)
                .brightness(hovering ? 0.12 : 0)
                .frame(width: 30, height: 14)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tr(help))
        .accessibilityLabel(tr(help))
    }
}
