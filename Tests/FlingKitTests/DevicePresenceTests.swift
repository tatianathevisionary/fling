import XCTest
import Network
@testable import FlingKit

/// The chosen and known TVs across launches and failed searches, the offline
/// check, and the one-click switch offer.
final class DeviceMemoryTests: XCTestCase {
    private let a = DeviceInfo(ip: "10.0.0.2", name: "Living room", model: "Google TV")
    private let b = DeviceInfo(ip: "10.0.0.3", name: "Bedroom", model: "Chromecast")

    func test_failed_search_keeps_the_known_tvs_and_the_choice() {
        let failed = DeviceMemory.merge(found: nil, known: [a, b], selected: b)
        XCTAssertEqual(failed.devices, [a, b])
        XCTAssertEqual(failed.selected, b)
        XCTAssertEqual(DeviceMemory.merge(found: [], known: [a, b], selected: b).selected, b)
    }

    func test_chosen_tv_missing_from_the_search_stays_chosen_and_listed() {
        let merged = DeviceMemory.merge(found: [b], known: [a, b], selected: a)
        XCTAssertEqual(merged.selected, a, "not swapped for the other TV")
        XCTAssertEqual(Set(merged.devices), [a, b])
    }

    func test_chosen_tv_under_a_new_address_is_followed_only_when_unambiguous() {
        let moved = DeviceInfo(ip: "10.0.0.9", name: a.name, model: a.model)
        XCTAssertEqual(DeviceMemory.merge(found: [moved, b], known: [a, b], selected: a).selected, moved)
        let twin = DeviceInfo(ip: "10.0.0.10", name: a.name, model: a.model)
        XCTAssertEqual(DeviceMemory.merge(found: [moved, twin], known: [a], selected: a).selected, a,
                       "two TVs with that name: keep the chosen one")
    }

    func test_first_search_picks_the_first_tv() {
        XCTAssertEqual(DeviceMemory.merge(found: [b, a], known: [], selected: nil).selected, b)
    }

    func test_choice_survives_a_restart() throws {
        let suite = "fling-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        DeviceMemory(defaults: defaults).save(selected: b, known: [a, b])
        let loaded = DeviceMemory(defaults: defaults).load()
        XCTAssertEqual(loaded.selected, b)
        XCTAssertEqual(loaded.known, [a, b])
    }

    @MainActor
    func test_app_state_starts_with_the_remembered_tv() throws {
        let suite = "fling-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        DeviceMemory(defaults: defaults).save(selected: b, known: [a, b])

        let state = AppState(catt: nil, browsers: BrowserReader(runner: FakeRunner()),
                             deviceMemory: DeviceMemory(defaults: defaults))
        XCTAssertEqual(state.selectedDevice, b)
        XCTAssertEqual(state.devices, [a, b])
    }
}

final class SwitchAdvisorTests: XCTestCase {
    private let a = DeviceInfo(ip: "1", name: "Living room", model: "")
    private let b = DeviceInfo(ip: "2", name: "Bedroom", model: "")
    private let c = DeviceInfo(ip: "3", name: "Attic", model: "")

    func test_offers_another_tv_after_two_offline_checks() {
        var advisor = SwitchAdvisor()
        let online = ["1": false, "2": true]
        XCTAssertNil(advisor.suggestion(current: a, devices: [a, b], online: online), "one miss isn't enough")
        XCTAssertEqual(advisor.suggestion(current: a, devices: [a, b], online: online), b)
        XCTAssertNil(advisor.suggestion(current: a, devices: [a, b], online: ["1": true, "2": true]),
                     "the TV is back: no offer")
    }

    func test_prefers_paired_then_by_name_and_never_an_offline_one() {
        let online = ["1": false, "2": true, "3": true]
        var byName = SwitchAdvisor()
        _ = byName.suggestion(current: a, devices: [a, b, c], online: online)
        XCTAssertEqual(byName.suggestion(current: a, devices: [a, b, c], online: online), c)

        var paired = SwitchAdvisor()
        _ = paired.suggestion(current: a, devices: [a, b, c], online: online, preferred: ["2"])
        XCTAssertEqual(paired.suggestion(current: a, devices: [a, b, c], online: online, preferred: ["2"]), b)

        var none = SwitchAdvisor()
        let allAway = ["1": false, "2": false]
        _ = none.suggestion(current: a, devices: [a, b], online: allAway)
        XCTAssertNil(none.suggestion(current: a, devices: [a, b], online: allAway))
    }
}

final class TVReachabilityTests: XCTestCase {

    func test_open_port_answers_and_closed_port_does_not() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: .global())
        defer { listener.cancel() }

        let started = Date()
        while (listener.port?.rawValue ?? 0) == 0, Date().timeIntervalSince(started) < 3 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let port = try XCTUnwrap(listener.port?.rawValue)
        let open = await TVReachability.isReachable(host: "127.0.0.1", ports: [port], timeout: 2)
        XCTAssertTrue(open)

        listener.cancel()
        try await Task.sleep(nanoseconds: 300_000_000)
        let closed = await TVReachability.isReachable(host: "127.0.0.1", ports: [port], timeout: 1)
        XCTAssertFalse(closed)
    }
}
