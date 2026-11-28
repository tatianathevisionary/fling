import XCTest
@testable import FlingKit

/// The facade's TLS-refusal policy: a paired TV that refuses the handshake is
/// retried before its pairing mark is dropped, presses during the wait are
/// dropped instead of landing late, and a wait stops when the user moves on.
final class AndroidTVRetryTests: XCTestCase {

    /// Hands out scripted transports; `refuse(n, host)` decides whether the
    /// n-th attempt (0-based, across hosts) fails the TLS handshake.
    private final class Transports: @unchecked Sendable {
        private let lock = NSLock()
        private var made: [(host: String, transport: FakeTransport)] = []
        private let refuse: @Sendable (Int, String) -> Bool

        init(refuse: @escaping @Sendable (Int, String) -> Bool) { self.refuse = refuse }

        func make(host: String) -> FakeTransport {
            let transport = FakeTransport()
            lock.lock()
            let attempt = made.count
            made.append((host, transport))
            lock.unlock()
            if refuse(attempt, host) {
                transport.startError = ATVError.tlsHandshakeFailed("-9806")
            } else {
                var configure = ProtoWriter()
                configure.message(1) { c in c.varint(1, 0x26F) }
                transport.push(configure.data)
                transport.push(ATVTestHex.data("1200"))         // RemoteSetActive
                transport.push(ATVTestHex.data("c202020801"))   // RemoteStart(on)
            }
            return transport
        }

        var all: [(host: String, transport: FakeTransport)] {
            lock.lock()
            defer { lock.unlock() }
            return made
        }

        var sent: [Data] { all.flatMap { $0.transport.sentMessages } }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool
        init(_ value: Bool) { self.value = value }
        var isOn: Bool {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    private var directories: [URL] = []

    override func tearDownWithError() throws {
        for dir in directories { try? FileManager.default.removeItem(at: dir) }
        directories = []
    }

    /// Pairing records are real files; the identity is never loaded because
    /// the transport factory bypasses TLS.
    private func store(paired hosts: [String]) throws -> ATVCertificateStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fling-atv-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        directories.append(dir)
        try Data().write(to: dir.appendingPathComponent("atv-identity.p12"))
        try Data().write(to: dir.appendingPathComponent("atv-client-cert.der"))
        let store = ATVCertificateStore(directory: dir)
        for host in hosts { store.recordPairedHost(host) }
        return store
    }

    private func facade(_ store: ATVCertificateStore, _ transports: Transports,
                        waits: [TimeInterval] = [0.05, 0.05, 0.05],
                        refusalMemory: TimeInterval = 60) -> AndroidTVRemote {
        let remote = ATVRemoteClient(store: store,
                                     transportFactory: { host, _ in transports.make(host: host) })
        return AndroidTVRemote(store: store, remote: remote,
                               retryWaits: waits, refusalMemory: refusalMemory)
    }

    private func waitUntil(timeout: TimeInterval = 2,
                           _ condition: () async -> Bool) async -> Bool {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await condition()
    }

    private func assertThrows(_ expected: ATVError, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected), nothing was thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ATVError, expected, file: file, line: line)
        }
    }

    private func key(_ code: Int32) -> Data { ATVRemoteMessage.keyInject(keyCode: code) }

    // MARK: -

    func test_paired_tv_refusing_twice_is_retried_and_stays_paired() async throws {
        let store = try store(paired: ["tv"])
        let transports = Transports { attempt, _ in attempt < 2 }
        let atv = facade(store, transports)

        let waited = try await atv.connectTracked(host: "tv")

        XCTAssertTrue(waited, "the connect had to wait for a retry")
        XCTAssertEqual(transports.all.count, 3)
        XCTAssertTrue(atv.hasPairing(host: "tv"))
    }

    func test_tv_that_really_forgot_drops_the_mark_after_three_retries() async throws {
        let store = try store(paired: ["tv"])
        let transports = Transports { _, _ in true }
        let atv = facade(store, transports)

        await assertThrows(.tlsHandshakeFailed("-9806")) { try await atv.connect(host: "tv") }
        XCTAssertEqual(transports.all.count, 4, "first try + a retry after each of the three waits")
        XCTAssertFalse(atv.hasPairing(host: "tv"), "the panel must offer Pair with TV")

        // It refused this Mac a moment ago: no knocking again right away.
        let mayTry = await atv.mayTry(host: "tv")
        XCTAssertFalse(mayTry)
        await assertThrows(.notPaired) { try await atv.pressKey(ATVKeyCode.dpadUp, host: "tv") }
        XCTAssertEqual(transports.all.count, 4, "no new attempt")
    }

    func test_no_second_round_of_retries_for_a_tv_that_refused_a_moment_ago() async throws {
        let store = try store(paired: ["tv"])
        let transports = Transports { _, _ in true }
        let atv = facade(store, transports)

        try? await atv.connect(host: "tv")
        XCTAssertEqual(transports.all.count, 4)
        store.recordPairedHost("tv")   // the mark is back (e.g. from another launch)
        try? await atv.connect(host: "tv")
        XCTAssertEqual(transports.all.count, 5, "one attempt, not another round of retries")
    }

    func test_dropped_mark_gets_one_later_attempt_and_success_restores_it() async throws {
        let store = try store(paired: ["tv"])
        let refusing = Flag(true)
        let transports = Transports { _, _ in refusing.isOn }
        let atv = facade(store, transports, refusalMemory: 0)   // the refusal is forgotten at once

        try? await atv.connect(host: "tv")
        XCTAssertFalse(atv.hasPairing(host: "tv"))

        refusing.isOn = false
        let mayTry = await atv.mayTry(host: "tv")
        XCTAssertTrue(mayTry)
        try await atv.pressKey(ATVKeyCode.dpadUp, host: "tv")
        XCTAssertTrue(atv.hasPairing(host: "tv"), "the TV still trusts this Mac: mark restored")
        XCTAssertTrue(transports.sent.contains(key(ATVKeyCode.dpadUp)))
    }

    func test_presses_during_the_wait_are_dropped_not_delivered_late() async throws {
        let store = try store(paired: ["tv"])
        let transports = Transports { attempt, _ in attempt == 0 }
        let atv = facade(store, transports, waits: [0.6])

        let first = Task { try await atv.pressKey(ATVKeyCode.dpadUp, host: "tv") }
        let waiting = await waitUntil { await atv.waitingHost == "tv" }
        XCTAssertTrue(waiting)
        await assertThrows(.reconnecting) { try await atv.pressKey(ATVKeyCode.dpadDown, host: "tv") }

        // The press that started the connect is stale once the retry worked.
        await assertThrows(.commandDropped) { try await first.value }
        XCTAssertFalse(transports.sent.contains(key(ATVKeyCode.dpadUp)))
        XCTAssertFalse(transports.sent.contains(key(ATVKeyCode.dpadDown)))

        // The session is up now: the next press goes through at once.
        try await atv.pressKey(ATVKeyCode.dpadLeft, host: "tv")
        XCTAssertTrue(transports.sent.contains(key(ATVKeyCode.dpadLeft)))
    }

    func test_stop_reconnecting_ends_the_wait_quietly_and_keeps_the_pairing() async throws {
        let store = try store(paired: ["tv"])
        let transports = Transports { _, _ in true }
        let atv = facade(store, transports, waits: [5, 5, 5])
        let started = Date()

        let connect = Task { try await atv.connect(host: "tv") }
        let waiting = await waitUntil { await atv.waitingHost == "tv" }
        XCTAssertTrue(waiting)
        await atv.stopReconnecting()

        await assertThrows(.superseded) { try await connect.value }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertTrue(atv.hasPairing(host: "tv"), "a stopped wait gives no verdict")
        let waitingHost = await atv.waitingHost
        XCTAssertNil(waitingHost)
    }

    func test_switching_tv_stops_the_wait_for_the_old_one() async throws {
        let store = try store(paired: ["a", "b"])
        let transports = Transports { _, host in host == "a" }
        let atv = facade(store, transports, waits: [5, 5, 5])
        let started = Date()

        let old = Task { try await atv.connect(host: "a") }
        let waiting = await waitUntil { await atv.waitingHost == "a" }
        XCTAssertTrue(waiting)
        try await atv.pressKey(ATVKeyCode.home, host: "b")

        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        await assertThrows(.superseded) { try await old.value }
        XCTAssertTrue(atv.hasPairing(host: "a"))
        XCTAssertEqual(transports.all.last?.host, "b")
        XCTAssertEqual(transports.all.last?.transport.sentMessages.contains(key(ATVKeyCode.home)), true)
    }

    func test_never_paired_tv_is_not_contacted() async throws {
        let store = try store(paired: [])
        let transports = Transports { _, _ in true }
        let atv = facade(store, transports)

        await assertThrows(.notPaired) { try await atv.connect(host: "tv") }
        XCTAssertTrue(transports.all.isEmpty, "nothing sent to a TV that was never paired")
    }
}
