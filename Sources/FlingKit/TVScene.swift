import Foundation

/// A remote button a scene step can press. `id` is what a saved scene stores,
/// so it must never change; `title` is the English label.
public struct SceneKey: Sendable {
    public let id: String
    public let title: String
    public let code: Int32

    public static let all: [SceneKey] = [
        SceneKey(id: "home", title: "Home", code: ATVKeyCode.home),
        SceneKey(id: "back", title: "Back", code: ATVKeyCode.back),
        SceneKey(id: "ok", title: "OK", code: ATVKeyCode.dpadCenter),
        SceneKey(id: "play_pause", title: "Play / Pause", code: ATVKeyCode.mediaPlayPause),
        SceneKey(id: "mute", title: "Mute", code: ATVKeyCode.volumeMute),
        SceneKey(id: "input", title: "Input", code: ATVKeyCode.tvInput),
        SceneKey(id: "settings", title: "TV settings", code: ATVKeyCode.settings),
    ]

    public static func with(id: String) -> SceneKey? { all.first { $0.id == id } }
}

/// One step of a scene ("Movie night": turn on the TV → open an app → volume 20 %).
public enum SceneStep: Codable, Hashable, Sendable {
    case wake
    case off
    case app(FavoriteApp)
    case volume(percent: Int)
    case key(String)                 // a `SceneKey.id`
    case wait(seconds: Int)
    case sleepTimer(minutes: Int)

    /// English label as (fixed part, value): the UI translates each piece.
    public var parts: (String, String?) {
        switch self {
        case .wake: return ("Turn on the TV", nil)
        case .off: return ("Turn off the TV", nil)
        case .app(let a): return ("Open: ", a.name)
        case .volume(let p): return ("TV volume: ", "\(p)%")
        case .key(let id): return ("Button: ", SceneKey.with(id: id)?.title ?? id)
        case .wait(let s): return ("Wait: ", "\(s) s")
        case .sleepTimer(let m): return ("Sleep timer: ", "\(m) min")
        }
    }
}

public struct TVScene: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    /// Switch to this TV (by name) first; nil = whichever TV is selected.
    public var tv: String?
    public var steps: [SceneStep]

    public init(name: String, tv: String? = nil, steps: [SceneStep]) {
        self.name = name; self.tv = tv; self.steps = steps
    }

    /// What "New scene…" starts from.
    public static func template(app: FavoriteApp?) -> TVScene {
        var steps: [SceneStep] = [.wake]
        if let app { steps.append(.app(app)) }
        steps.append(.volume(percent: 20))
        return TVScene(name: "Movie night", steps: steps)
    }
}

public enum SceneStore {
    static let defaultsKey = "scenes"
    public static let maxNameLength = 60

    public static func load(from store: UserDefaults = .standard) -> [TVScene] {
        guard let data = store.data(forKey: defaultsKey),
              let scenes = try? JSONDecoder().decode([TVScene].self, from: data) else { return [] }
        return scenes
    }

    public static func save(_ scenes: [TVScene], to store: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(scenes) { store.set(data, forKey: defaultsKey) }
    }

    /// Names stay unique (case-insensitively): "Movie night" twice becomes "Movie night 2".
    public static func uniqueName(_ name: String, among others: [TVScene]) -> String {
        let base = String(name.trimmingCharacters(in: .whitespaces).prefix(maxNameLength))
        let taken = Set(others.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}

public enum SleepTimer {
    public static let choices = [15, 30, 45, 60, 90, 120]

    /// Minutes shown for what is left: rounded up, at least 1 while running.
    public static func minutesLeft(until deadline: Date, now: Date = Date()) -> Int {
        max(1, Int((deadline.timeIntervalSince(now) / 60).rounded(.up)))
    }
}
