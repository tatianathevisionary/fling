import Foundation

/// One chip of the remote's app grid. Catalog apps carry their verified app
/// link; an app added by package name (or as "the app open on the TV") has
/// none, because the remote protocol can't look one up.
public struct FavoriteApp: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    /// nil: no known app link — see `FavoriteApps.fallbackLink`.
    public var link: String?
    public var package: String

    public var id: String { package }

    public init(name: String, link: String?, package: String) {
        self.name = name; self.link = link; self.package = package
    }

    public init(_ app: TVApp) { self.init(name: app.name, link: app.link, package: app.package) }

    /// The catalog entry when there is one, so a known app keeps its link.
    public init(package: String) {
        if let known = TVApp.catalog.first(where: { $0.package == package }) {
            self.init(known)
        } else {
            self.init(name: TVApp.displayName(forPackage: package), link: nil, package: package)
        }
    }

    /// True when the app opens by its own link; false when the TV is only
    /// asked by package, which many TVs ignore.
    public var hasAppLink: Bool { link != nil }
}

public enum FavoriteApps {
    public static let maxCount = 15
    public static let maxNameLength = 40

    /// Home-screen launchers: never offered as "the app open on the TV".
    public static let launchers: Set<String> = [
        "com.google.android.tvlauncher", "com.google.android.apps.tv.launcherx",
        "com.google.android.apps.tv.launcher", "com.google.android.leanbacklauncher",
    ]

    public static var defaults: [FavoriteApp] { TVApp.catalog.map(FavoriteApp.init) }

    /// The only way the remote protocol can name an app without its link.
    /// Many TVs don't open the app this way (TCL Google TV, see the hardware
    /// notes in remote-protocol.md), so `RemoteExtras.open` checks the result.
    public static func fallbackLink(forPackage package: String) -> String {
        "market://launch?id=" + package
    }

    /// Android package names: `org.videolan.vlc`.
    public static func isPackageName(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$"#,
                options: .regularExpression) != nil
    }

    /// Kept per TV under its name, which survives a new IP from the router.
    static func defaultsKey(tv: String) -> String { "favoriteApps." + tv }

    /// The TV's set; the catalog until the user changes something.
    public static func load(tv: String, from store: UserDefaults = .standard) -> [FavoriteApp] {
        guard let data = store.data(forKey: defaultsKey(tv: tv)),
              let apps = try? JSONDecoder().decode([FavoriteApp].self, from: data) else { return defaults }
        return apps
    }

    /// nil restores the default set.
    public static func save(_ apps: [FavoriteApp]?, tv: String, to store: UserDefaults = .standard) {
        guard let apps else { store.removeObject(forKey: defaultsKey(tv: tv)); return }
        let clean = apps.prefix(maxCount).map {
            FavoriteApp(name: String($0.name.prefix(maxNameLength)), link: $0.link, package: $0.package)
        }
        if let data = try? JSONEncoder().encode(Array(clean)) { store.set(data, forKey: defaultsKey(tv: tv)) }
    }

    /// Adds `app` unless it is there already or the grid is full; nil when nothing changed.
    public static func adding(_ app: FavoriteApp, to apps: [FavoriteApp]) -> [FavoriteApp]? {
        guard apps.count < maxCount, !apps.contains(where: { $0.id == app.id }) else { return nil }
        return apps + [app]
    }

    /// Swaps the app at `i` with its neighbour `d` places away; unchanged at the edges.
    public static func moving(_ apps: [FavoriteApp], at i: Int, by d: Int) -> [FavoriteApp] {
        var out = apps
        guard out.indices.contains(i), out.indices.contains(i + d) else { return apps }
        out.swapAt(i, i + d)
        return out
    }
}
