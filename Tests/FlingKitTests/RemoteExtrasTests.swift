import XCTest
@testable import FlingKit

/// A throwaway UserDefaults suite per test.
private final class ScratchDefaults {
    let name = "fling-tests-\(UUID().uuidString)"
    lazy var store = UserDefaults(suiteName: name)!
    deinit { UserDefaults().removePersistentDomain(forName: name) }
}

final class TouchpadNavTests: XCTestCase {

    func test_small_drags_accumulate_before_a_step() {
        var nav = TouchpadNav()
        XCTAssertEqual(nav.drag(dx: 20, dy: 0), [])
        XCTAssertEqual(nav.drag(dx: 20, dy: 0), [ATVKeyCode.dpadRight])
    }

    func test_dominant_axis_and_direction() {
        var nav = TouchpadNav()
        XCTAssertEqual(nav.drag(dx: 5, dy: -40), [ATVKeyCode.dpadUp])
        nav.reset()
        XCTAssertEqual(nav.drag(dx: -40, dy: 10), [ATVKeyCode.dpadLeft])
        nav.reset()
        XCTAssertEqual(nav.drag(dx: 0, dy: 70), [ATVKeyCode.dpadDown, ATVKeyCode.dpadDown])
    }

    func test_cross_axis_drift_is_dropped_after_a_step() {
        var nav = TouchpadNav()
        XCTAssertEqual(nav.drag(dx: 40, dy: 30), [ATVKeyCode.dpadRight])
        XCTAssertEqual(nav.drag(dx: 0, dy: 10), [])          // the 30 of drift is gone
    }

    func test_a_huge_jump_is_capped() {
        var nav = TouchpadNav()
        XCTAssertEqual(nav.drag(dx: 1000, dy: 0).count, TouchpadNav.maxStepsPerEvent)
    }
}

final class FavoriteAppsTests: XCTestCase {

    func test_defaults_until_saved_then_per_tv() {
        let d = ScratchDefaults()
        XCTAssertEqual(FavoriteApps.load(tv: "Living room", from: d.store), FavoriteApps.defaults)
        let vlc = FavoriteApp(package: "org.videolan.vlc")
        FavoriteApps.save([vlc], tv: "Living room", to: d.store)
        XCTAssertEqual(FavoriteApps.load(tv: "Living room", from: d.store), [vlc])
        XCTAssertEqual(FavoriteApps.load(tv: "Bedroom", from: d.store), FavoriteApps.defaults)
        FavoriteApps.save(nil, tv: "Living room", to: d.store)
        XCTAssertEqual(FavoriteApps.load(tv: "Living room", from: d.store), FavoriteApps.defaults)
    }

    func test_defaults_are_the_catalog_with_its_links() {
        XCTAssertEqual(FavoriteApps.defaults.map(\.package), TVApp.catalog.map(\.package))
        XCTAssertTrue(FavoriteApps.defaults.allSatisfy(\.hasAppLink))
    }

    func test_known_package_keeps_the_catalog_link() {
        let netflix = FavoriteApp(package: "com.netflix.ninja")
        XCTAssertEqual(netflix.link, "netflix://")
        XCTAssertEqual(netflix.name, "Netflix")
    }

    func test_unknown_package_has_no_link_and_falls_back_to_market() {
        let vlc = FavoriteApp(package: "org.videolan.vlc")
        XCTAssertNil(vlc.link)
        XCTAssertFalse(vlc.hasAppLink)
        XCTAssertEqual(vlc.name, "Vlc")
        XCTAssertEqual(FavoriteApps.fallbackLink(forPackage: vlc.package),
                       "market://launch?id=org.videolan.vlc")
    }

    func test_adding_skips_duplicates_and_respects_the_limit() {
        let yt = FavoriteApps.defaults[0]
        XCTAssertNil(FavoriteApps.adding(yt, to: FavoriteApps.defaults))
        let full = (0..<FavoriteApps.maxCount).map { FavoriteApp(package: "com.example.app\($0)") }
        XCTAssertNil(FavoriteApps.adding(FavoriteApp(package: "org.kodi.x"), to: full))
        XCTAssertEqual(FavoriteApps.adding(FavoriteApp(package: "org.kodi.x"), to: [yt])?.count, 2)
    }

    func test_save_trims_names_and_count() {
        let d = ScratchDefaults()
        let long = FavoriteApp(name: String(repeating: "x", count: 100), link: nil, package: "a.b")
        let many = [long] + (0..<20).map { FavoriteApp(package: "com.example.app\($0)") }
        FavoriteApps.save(many, tv: "TV", to: d.store)
        let back = FavoriteApps.load(tv: "TV", from: d.store)
        XCTAssertEqual(back.count, FavoriteApps.maxCount)
        XCTAssertEqual(back[0].name.count, FavoriteApps.maxNameLength)
    }

    func test_moving_swaps_neighbours_and_ignores_edges() {
        let apps = Array(FavoriteApps.defaults.prefix(3))
        XCTAssertEqual(FavoriteApps.moving(apps, at: 0, by: 1).map(\.id), [apps[1].id, apps[0].id, apps[2].id])
        XCTAssertEqual(FavoriteApps.moving(apps, at: 0, by: -1), apps)
        XCTAssertEqual(FavoriteApps.moving(apps, at: 2, by: 1), apps)
    }

    func test_package_names() {
        XCTAssertTrue(FavoriteApps.isPackageName("org.videolan.vlc"))
        XCTAssertFalse(FavoriteApps.isPackageName("vlc"))
        XCTAssertFalse(FavoriteApps.isPackageName("org.videolan.vlc; reboot"))
        XCTAssertFalse(FavoriteApps.isPackageName("org.1abc"))
    }
}

final class TVSceneTests: XCTestCase {

    func test_scenes_round_trip_through_defaults() {
        let d = ScratchDefaults()
        let sc = TVScene(name: "Movie night", tv: "Living room",
                         steps: [.wake, .app(FavoriteApps.defaults[0]), .volume(percent: 20), .key("home"),
                                 .wait(seconds: 3), .sleepTimer(minutes: 30), .off,
                                 .app(FavoriteApp(package: "org.videolan.vlc"))])
        SceneStore.save([sc], to: d.store)
        XCTAssertEqual(SceneStore.load(from: d.store), [sc])
    }

    func test_unique_names() {
        let others = [TVScene(name: "Movie night", steps: [.wake]), TVScene(name: "movie night 2", steps: [.wake])]
        XCTAssertEqual(SceneStore.uniqueName("Movie night", among: others), "Movie night 3")
        XCTAssertEqual(SceneStore.uniqueName("  Morning ", among: others), "Morning")
    }

    func test_template_and_step_text() {
        let t = TVScene.template(app: FavoriteApps.defaults[0])
        XCTAssertEqual(t.steps, [.wake, .app(FavoriteApps.defaults[0]), .volume(percent: 20)])
        XCTAssertEqual(SceneStep.key("ok").parts.1, "OK")
        XCTAssertEqual(SceneStep.wait(seconds: 5).parts.1, "5 s")
        XCTAssertEqual(SceneStep.key("gone").parts.1, "gone")
    }

    func test_scene_key_ids_are_unique() {
        XCTAssertEqual(Set(SceneKey.all.map(\.id)).count, SceneKey.all.count)
    }

    func test_digit_key_codes() {
        XCTAssertEqual(ATVKeyCode.digit(0), 7)
        XCTAssertEqual(ATVKeyCode.digit(9), 16)
        XCTAssertEqual(ATVKeyCode.digit(12), 16)
    }

    func test_sleep_timer_minutes_round_up_and_never_show_zero() {
        let now = Date()
        XCTAssertEqual(SleepTimer.minutesLeft(until: now.addingTimeInterval(25 * 60), now: now), 25)
        XCTAssertEqual(SleepTimer.minutesLeft(until: now.addingTimeInterval(24 * 60 + 1), now: now), 25)
        XCTAssertEqual(SleepTimer.minutesLeft(until: now.addingTimeInterval(5), now: now), 1)
        XCTAssertEqual(SleepTimer.minutesLeft(until: now.addingTimeInterval(-5), now: now), 1)
    }
}

@MainActor
final class RemoteExtrasTests: XCTestCase {

    private func makeState() -> AppState {
        AppState(catt: nil, browsers: BrowserReader(runner: FakeRunner()))
    }

    func test_sleep_timer_sets_and_cancels() {
        let state = makeState()
        let d = ScratchDefaults()
        let extras = RemoteExtras(state: state, store: d.store)
        extras.setSleep(minutes: 30)
        XCTAssertEqual(extras.sleepMinutesLeft, 30)
        extras.setSleep(minutes: nil)
        XCTAssertNil(extras.sleepDeadline)
    }

    func test_turning_off_an_unpaired_tv_says_why() async {
        let state = makeState()
        let d = ScratchDefaults()
        let extras = RemoteExtras(state: state, store: d.store)
        let ok = await extras.turnOff()
        XCTAssertFalse(ok)
        XCTAssertNotNil(state.lastError)
    }

    func test_opening_an_app_unpaired_says_why() async {
        let state = makeState()
        let d = ScratchDefaults()
        await RemoteExtras(state: state, store: d.store).open(FavoriteApps.defaults[0])
        XCTAssertEqual(state.lastError, "Apps open once Fling is paired with the TV.")
    }

    func test_scenes_save_with_unique_names_and_delete() {
        let state = makeState()
        let d = ScratchDefaults()
        let extras = RemoteExtras(state: state, store: d.store)
        extras.save(scene: TVScene(name: "Movie night", steps: [.wake]))
        extras.save(scene: TVScene(name: "Movie night", steps: [.off]))
        XCTAssertEqual(extras.scenes.map(\.name), ["Movie night", "Movie night 2"])
        XCTAssertEqual(RemoteExtras(state: state, store: d.store).scenes, extras.scenes)
        extras.delete(scene: extras.scenes[0].id)
        XCTAssertEqual(extras.scenes.map(\.name), ["Movie night 2"])
    }

    func test_not_opened_message_is_honest_about_links() {
        let vlc = FavoriteApp(package: "org.videolan.vlc")
        let prime = FavoriteApp(package: "com.amazon.amazonvideo.livingroom")
        // no link: always explained, whether or not the TV reports its foreground app
        XCTAssertNotNil(RemoteExtras.notOpenedMessage(vlc, reported: nil))
        XCTAssertNotNil(RemoteExtras.notOpenedMessage(vlc, reported: "com.google.android.tvlauncher"))
        // a linked app is only reported as not opened when the TV says something else is in front
        XCTAssertNil(RemoteExtras.notOpenedMessage(prime, reported: nil))
        XCTAssertNotNil(RemoteExtras.notOpenedMessage(prime, reported: "com.google.android.tvlauncher"))
    }
}
