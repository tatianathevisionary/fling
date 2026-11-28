import Foundation
import Network

/// Is a TV answering right now: one TCP knock on the Cast and remote ports,
/// all at once, so a TV that's gone costs about a second.
public enum TVReachability {
    /// Cast (8009, 8008), Android TV remote (6466), ADB (5555).
    public static let ports: [UInt16] = [8009, 8008, 6466, 5555]

    public static func isReachable(host: String, ports: [UInt16] = ports,
                                   timeout: TimeInterval = 1.0) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            for port in ports {
                group.addTask { await knock(host: host, port: port, timeout: timeout) }
            }
            for await open in group where open {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if done { return false }
            done = true
            return true
        }
    }

    private static let queue = DispatchQueue(label: "fling.reachability")

    static func knock(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let once = Once()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let finish: @Sendable (Bool) -> Void = { open in
                guard once.claim() else { return }
                connection.stateUpdateHandler = nil
                connection.cancel()
                cont.resume(returning: open)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting, .cancelled: finish(false)   // refused, unreachable
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}

/// The TV in use stopped answering (two checks in a row) while another known
/// TV answers: offer that one, one click.
public struct SwitchAdvisor {
    private var away = 0
    private var awayHost: String?

    public init() {}

    /// `preferred`: TVs to offer first (paired Android TVs can do the most).
    public mutating func suggestion(current: DeviceInfo?, devices: [DeviceInfo],
                                    online: [String: Bool],
                                    preferred: Set<String> = []) -> DeviceInfo? {
        guard let current else { reset(); return nil }
        if awayHost != current.ip { away = 0; awayHost = current.ip }
        away = online[current.ip] == false ? away + 1 : 0
        guard away >= 2 else { return nil }
        let alternatives = devices.filter { $0.ip != current.ip && online[$0.ip] == true }
        return alternatives.min { a, b in
            let pa = preferred.contains(a.ip), pb = preferred.contains(b.ip)
            if pa != pb { return pa }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    public mutating func reset() { away = 0; awayHost = nil }
}
