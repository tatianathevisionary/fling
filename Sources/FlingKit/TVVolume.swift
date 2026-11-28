/// The TV's own volume, as RemoteSetVolumeLevel reports it.
public struct TVVolume: Equatable, Sendable {
    public let level: Int
    public let max: Int
    public let muted: Bool
}
