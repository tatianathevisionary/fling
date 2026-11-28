import Foundation
import Combine

/// The remote's extras on top of `AppState`: explicit Turn on / Turn off, the
/// per-TV favourite apps, scenes and the sleep timer — all over the Android
/// TV Remote session. Owned by AppState (`state.remoteExtras`), so the sleep
/// timer keeps running with the panel closed. Nothing polls unless a timer
/// or a scene is running. Failures end in `state.lastError` like the rest.
@MainActor
public final class RemoteExtras: ObservableObject {
    public unowned let state: AppState
    private let store: UserDefaults

    @Published public private(set) var scenes: [TVScene]
    /// Bumped when a favourites list is saved, so the grid redraws.
    @Published public private(set) var favoritesRevision = 0
    @Published public private(set) var sleepDeadline: Date?
    @Published public private(set) var runningScene: String?

    /// How long an opened app gets to show up as the TV's foreground app.
    static let launchCheckTimeout: TimeInterval = 8

    private var sleepHost: String?
    private var sleepTask: Task<Void, Never>?
    private var sceneTask: Task<Void, Never>?
    private var launchGeneration = 0
    private var deviceSink: AnyCancellable?

    public init(state: AppState, store: UserDefaults = .standard) {
        self.state = state
        self.store = store
        self.scenes = SceneStore.load(from: store)
        // a timer set for one TV must not turn off another one
        deviceSink = state.$selectedDevice.removeDuplicates().sink { [weak self] device in
            guard let self, self.sleepDeadline != nil, let host = self.sleepHost,
                  device?.ip != host else { return }
            self.setSleep(minutes: nil)
            self.state.lastError = "Sleep timer cancelled: another TV was selected."
        }
    }

    /// Per-TV settings are kept under the TV's name: it survives a new IP from the router.
    public var tvID: String { state.selectedDevice?.name ?? state.selectedDevice?.ip ?? "" }

    // MARK: - power

    /// The one-way WAKEUP key, never the POWER toggle: standby-networked sets
    /// report "on" with the screen dark, so a toggle could turn them off.
    /// Unpaired, the Cast wake (HDMI-CEC) does it.
    @discardableResult
    public func turnOn() async -> Bool {
        if state.tvPaired {
            await state.pressTVKey(ATVKeyCode.wakeUp)
        } else {
            await state.wakeTV()
        }
        return state.selectedDevice != nil
    }

    /// The one-way SLEEP key; needs pairing (Cast has no power-off).
    @discardableResult
    public func turnOff() async -> Bool {
        guard state.tvPaired else {
            state.lastError = "Can't turn the TV off: Fling isn't paired with it."
            return false
        }
        await state.pressTVKey(ATVKeyCode.sleep)
        return true
    }

    // MARK: - favourite apps

    public var favorites: [FavoriteApp] { FavoriteApps.load(tv: tvID, from: store) }

    /// nil restores the default set.
    public func setFavorites(_ apps: [FavoriteApp]?) {
        FavoriteApps.save(apps, tv: tvID, to: store)
        favoritesRevision += 1
    }

    @discardableResult
    public func addFavorite(_ app: FavoriteApp) -> Bool {
        let apps = favorites
        if apps.count >= FavoriteApps.maxCount {
            state.lastError = "No more room — remove an app first."
            return false
        }
        guard let next = FavoriteApps.adding(app, to: apps) else { return false }
        setFavorites(next)
        return true
    }

    /// Opens `app` by its app link, the way the catalog launcher always has.
    /// Without a link the only thing left to send is
    /// `FavoriteApps.fallbackLink`, which many TVs ignore — so the result is
    /// checked against the foreground app the TV reports, and a TV that
    /// didn't open it gets a plain explanation instead of silence.
    public func open(_ app: FavoriteApp) async {
        guard state.tvPaired else {
            state.lastError = "Apps open once Fling is paired with the TV."
            return
        }
        launchGeneration += 1
        let generation = launchGeneration
        let link = app.link ?? FavoriteApps.fallbackLink(forPackage: app.package)
        await state.launchTVApp(TVApp(name: app.name, link: link, package: app.package))
        guard state.lastError == nil else { return }          // the send itself failed
        await waitUntil(Self.launchCheckTimeout) { self.state.tvCurrentApp == app.package }
        guard generation == launchGeneration, !Task.isCancelled,
              state.tvCurrentApp != app.package else { return }
        if let message = Self.notOpenedMessage(app, reported: state.tvCurrentApp) {
            state.lastError = message
        }
    }

    /// What to say when the TV's foreground app isn't `app` after a launch.
    /// A linked app on a TV that doesn't report its foreground app may well
    /// have opened, so that case says nothing.
    static func notOpenedMessage(_ app: FavoriteApp, reported: String?) -> String? {
        if !app.hasAppLink {
            return "The TV didn't open \(app.name): Fling knows no app link for it, and most TVs won't open an app by its package name. Open it from the TV's home screen."
        }
        guard reported != nil else { return nil }
        return "The TV didn't open \(app.name): this TV doesn't accept the app's link. Open it from the TV's home screen."
    }

    // MARK: - sleep timer

    public var sleepMinutesLeft: Int? { sleepDeadline.map { SleepTimer.minutesLeft(until: $0) } }

    /// nil cancels. A wall-clock deadline checked at least every 30 s, so a
    /// Mac that slept through it still turns the TV off when it wakes.
    public func setSleep(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        guard let minutes, minutes > 0 else {
            sleepDeadline = nil
            sleepHost = nil
            return
        }
        let deadline = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        sleepDeadline = deadline
        sleepHost = state.selectedDevice?.ip
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                let left = deadline.timeIntervalSinceNow
                if left <= 0 { break }
                try? await Task.sleep(for: .seconds(min(left, 30) + 0.05))
                guard !Task.isCancelled else { return }
                self?.objectWillChange.send()          // the "turns off in N min" line
            }
            guard !Task.isCancelled, let self else { return }
            self.sleepDeadline = nil
            self.sleepHost = nil
            self.sleepTask = nil
            await self.turnOff()
        }
    }

    // MARK: - scenes

    /// Saves `scene` (new when its id isn't there yet) with a name no other scene has.
    public func save(scene: TVScene) {
        var sc = scene
        var all = scenes
        sc.name = SceneStore.uniqueName(sc.name, among: all.filter { $0.id != sc.id })
        if let i = all.firstIndex(where: { $0.id == sc.id }) { all[i] = sc } else { all.append(sc) }
        setScenes(all)
    }

    public func delete(scene id: UUID) {
        setScenes(scenes.filter { $0.id != id })
    }

    private func setScenes(_ scenes: [TVScene]) {
        self.scenes = scenes
        SceneStore.save(scenes, to: store)
    }

    public func stopScene() {
        sceneTask?.cancel()
        sceneTask = nil
        runningScene = nil
    }

    /// Runs the steps in order; a new scene replaces a running one.
    public func run(_ scene: TVScene) {
        sceneTask?.cancel()
        runningScene = scene.name
        sceneTask = Task { [weak self] in
            await self?.perform(scene)
            guard !Task.isCancelled else { return }
            self?.runningScene = nil
            self?.sceneTask = nil
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(max(0, seconds)))
    }

    /// Checks `condition` every 250 ms until it holds or `timeout` passes.
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !Task.isCancelled, !condition(), Date() < end { await pause(0.25) }
    }

    private func perform(_ scene: TVScene) async {
        if let want = scene.tv, state.selectedDevice?.name != want {
            if let device = state.devices.first(where: { $0.name == want }) {
                await state.select(device: device)
                await pause(1)
            } else {
                state.lastError = "TV “\(want)” not found — the scene ran on the current TV."
            }
        }
        for step in scene.steps {
            if Task.isCancelled { return }
            switch step {
            case .wake:
                let paired = state.tvPaired
                if await turnOn() {
                    // a paired TV reports power once it is up; one woken over Cast gets a few seconds
                    await waitUntil(paired ? 12 : 4) { paired && self.state.tvIsOn == true }
                    await pause(1.5)
                }
            case .off:
                await turnOff()
                await pause(1)
            case .app(let app):
                await open(app)
                await pause(1)
            case .key(let id):
                if let key = SceneKey.with(id: id) { await state.pressTVKey(key.code) }
                await pause(0.5)
            case .wait(let s):
                await pause(Double(min(600, max(0, s))))
            case .sleepTimer(let m):
                setSleep(minutes: m)
            case .volume(let pct):
                await waitUntil(6) { self.state.tvVolume != nil }
                guard let v = state.tvVolume else {
                    state.lastError = "Scene “\(scene.name)”: the TV doesn't report its volume — step skipped."
                    continue
                }
                state.setTVVolume(Int((Double(v.max) * Double(min(100, max(0, pct))) / 100).rounded()))
                await pause(0.3)
                await waitUntil(15) { self.state.tvVolumeTarget == nil }
                await pause(0.5)
            }
        }
    }
}
