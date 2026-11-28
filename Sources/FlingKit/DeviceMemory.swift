import Foundation

/// The chosen TV and the known TVs survive a restart (an update), and a TV
/// search that fails or misses the chosen TV doesn't swap it for another one.
public struct DeviceMemory {
    private let defaults: UserDefaults
    private static let selectedKey = "selectedDevice"
    private static let knownKey = "knownDevices"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// Only inside the real app: test runs must not read or write the user's choice.
    public static var standard: DeviceMemory? {
        Bundle.main.bundleURL.pathExtension == "app" ? DeviceMemory(defaults: .standard) : nil
    }

    private struct Stored: Codable { let ip, name, model: String }

    public func load() -> (selected: DeviceInfo?, known: [DeviceInfo]) {
        let dec = JSONDecoder()
        let sel = defaults.data(forKey: Self.selectedKey).flatMap { try? dec.decode(Stored.self, from: $0) }
        let known = defaults.data(forKey: Self.knownKey).flatMap { try? dec.decode([Stored].self, from: $0) } ?? []
        func dev(_ s: Stored) -> DeviceInfo { DeviceInfo(ip: s.ip, name: s.name, model: s.model) }
        return (sel.map(dev), known.map(dev))
    }

    public func save(selected: DeviceInfo?, known: [DeviceInfo]) {
        let enc = JSONEncoder()
        func st(_ d: DeviceInfo) -> Stored { Stored(ip: d.ip, name: d.name, model: d.model) }
        if let selected, let data = try? enc.encode(st(selected)) {
            defaults.set(data, forKey: Self.selectedKey)
        }
        if let data = try? enc.encode(known.map(st)) { defaults.set(data, forKey: Self.knownKey) }
    }

    /// What a finished TV search means for the list and the chosen TV.
    /// - `found` nil or empty: the search failed (cut off, crashed, timed out)
    ///   or saw nothing — that says nothing about which TVs are there, so the
    ///   known list and the chosen TV stay.
    /// - The chosen TV seen under a new address (DHCP) is followed only when
    ///   that is unambiguous: exactly one TV with its name (and model, if known).
    /// - The chosen TV not seen this time (asleep, off, a slow mDNS reply) stays
    ///   chosen and stays in the list, shown offline.
    public static func merge(found: [DeviceInfo]?, known: [DeviceInfo], selected: DeviceInfo?)
        -> (devices: [DeviceInfo], selected: DeviceInfo?) {
        guard let found, !found.isEmpty else {
            var devices = known
            if let selected, !devices.contains(where: { $0.ip == selected.ip }) { devices.append(selected) }
            return (devices, selected ?? devices.first)
        }
        var devices = found
        var chosen = selected
        if let sel = selected {
            if let same = found.first(where: { $0.ip == sel.ip }) {
                chosen = same
            } else {
                let renamed = found.filter {
                    $0.name == sel.name && ($0.model.isEmpty || sel.model.isEmpty || $0.model == sel.model)
                }
                if renamed.count == 1 {
                    chosen = renamed[0]
                } else {
                    devices.append(sel)
                }
            }
        }
        return (devices, chosen ?? devices.first)
    }
}
