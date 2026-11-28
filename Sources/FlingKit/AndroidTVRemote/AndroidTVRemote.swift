import Foundation

/// Errors surfaced by the Android TV remote subsystem. String payloads keep the
/// enum Equatable so UI code can match on cases.
public enum ATVError: Error, Equatable {
    case connectionFailed(String)
    /// The server aborted the TLS handshake itself (alert, or reset right
    /// after TCP came up). On port 6466 this is the signature of the TV no
    /// longer trusting the client certificate — the fix is re-pairing, not
    /// retrying. Payload is the verbatim NWError text.
    case tlsHandshakeFailed(String)
    case connectionClosed
    case connectionTimeout
    case notConnected
    case pairingNotStarted
    /// Pairing status other than STATUS_OK — 402 is a rejected secret.
    case serverStatus(UInt64)
    case unexpectedMessage
    case invalidPIN(String)
    case certificateFailure(String)
    case noHostConfigured
    case notPaired
    case invalidText
    /// Voice was not negotiated — construct the facade with `enableVoice: true`.
    case voiceNotEnabled
    case voiceSessionActive
    case voiceSessionInactive
    /// The TV never answered KEYCODE_SEARCH with RemoteVoiceBegin.
    case voiceTimeout
    /// The remote is waiting to retry a refused handshake with this TV; the
    /// command was dropped instead of running seconds late.
    case reconnecting
    /// The command waited for a connect that needed a retry wait, so it was
    /// dropped rather than delivered late. Nothing to tell the user.
    case commandDropped
    /// The connect was stopped on purpose (another TV chosen, pairing
    /// started). Nothing to tell the user.
    case superseded
}

/// App-facing facade over the Android TV Remote protocol v2 client: one-time
/// pairing on port 6467, then the power/key session on port 6466. Call order
/// is `hasPairing`, `startPairing`, `finishPairing`, then any session method.
public actor AndroidTVRemote {

    public let store: ATVCertificateStore
    private let clientName: String
    private let remote: ATVRemoteClient
    private var pairing: ATVPairingClient?
    private var pairingHost: String?
    private var lastHost: String?
    /// Single in-flight connect, joined by overlapping callers so a second
    /// connect can't tear down the first one's fresh session.
    /// The task's result is true when the connect had to wait for a retry.
    private var inflightConnect: (id: UUID, host: String, task: Task<Bool, Error>)?

    // A TV that has just woken up or restarted can drop the first TLS
    // handshakes, which looks exactly like "the TV forgot this Mac". For a
    // paired TV, try again after these waits before believing it and
    // dropping the pairing mark.
    static let defaultRetryWaits: [TimeInterval] = [2, 4, 6]
    /// After the TV refused this Mac, no retries / extra attempts for this long.
    static let defaultRefusalMemory: TimeInterval = 60
    private let retryWaits: [TimeInterval]
    private let refusalMemory: TimeInterval
    /// Host -> when the TV last refused this Mac (after the retries).
    private var refusedAt: [String: Date] = [:]
    /// Hosts whose pairing mark Fling dropped in this run: one later attempt
    /// may still find the TV trusts the certificate, which restores the mark.
    private var droppedMarks: Set<String> = []
    /// The host a connect is waiting to retry, nil otherwise.
    public private(set) var waitingHost: String?

    /// `enableVoice` negotiates the VOICE feature so `beginVoice`/`sendVoice`
    /// work. Off by default: once negotiated, KEYCODE_SEARCH puts the TV into
    /// mic-listening mode instead of opening typed search.
    public init(clientName: String = "Fling",
                store: ATVCertificateStore = .shared,
                enableVoice: Bool = false) {
        self.init(clientName: clientName, store: store,
                  remote: ATVRemoteClient(store: store, enableVoice: enableVoice),
                  retryWaits: Self.defaultRetryWaits)
    }

    /// Test seam: a remote with an injected transport.
    init(clientName: String = "Fling",
         store: ATVCertificateStore = .shared,
         remote: ATVRemoteClient,
         retryWaits: [TimeInterval] = AndroidTVRemote.defaultRetryWaits,
         refusalMemory: TimeInterval = AndroidTVRemote.defaultRefusalMemory) {
        self.clientName = clientName
        self.store = store
        self.remote = remote
        self.retryWaits = retryWaits
        self.refusalMemory = refusalMemory
    }

    // MARK: - pairing

    /// Client-side record only: the identity exists and this host acked the
    /// secret once. The TV clearing its side surfaces as a TLS failure on
    /// `connect`, which is the signal to re-pair.
    public nonisolated func hasPairing(host: String) -> Bool {
        store.identityExists && store.pairedHosts().contains(host)
    }

    /// When this returns, the TV is displaying a 6-hex-character PIN.
    public func startPairing(host: String) async throws {
        stopReconnecting()                 // a retry wait for the old pairing is pointless now
        await pairing?.cancel()
        let client = ATVPairingClient(clientName: clientName, store: store)
        pairing = client
        pairingHost = host
        try await client.start(host: host)
    }

    public func finishPairing(pin: String) async throws {
        guard let pairing, let pairingHost else { throw ATVError.pairingNotStarted }
        try await pairing.finish(pin: pin)
        store.recordPairedHost(pairingHost)
        refusedAt[pairingHost] = nil
        droppedMarks.remove(pairingHost)
        self.pairing = nil
        self.pairingHost = nil
    }

    public func cancelPairing() async {
        await pairing?.cancel()
        pairing = nil
        pairingHost = nil
    }

    // MARK: - remote session

    public func connect(host: String) async throws {
        _ = try await connectTracked(host: host)
    }

    /// `connect`, returning true when it had to wait for a retry — a command
    /// that waited for it is stale by now.
    func connectTracked(host: String) async throws -> Bool {
        guard hasPairing(host: host) || mayTry(host: host) else { throw ATVError.notPaired }
        // A press while the connect waits to retry would land 2–12 s late.
        if waitingHost == host { throw ATVError.reconnecting }
        lastHost = host
        if let inflight = inflightConnect, inflight.host == host {
            return try await inflight.task.value
        }
        if let inflight = inflightConnect {
            // A connect to a different host is settling; let it finish so two
            // teardowns can't interleave. Its outcome is that caller's to
            // handle, not ours. A retry wait for the other TV stops now.
            inflight.task.cancel()
            _ = try? await inflight.task.value
        }
        let id = UUID()
        let task = Task { try await self.connectWithRetries(host: host) }
        inflightConnect = (id, host, task)
        // Identity-checked: while this call awaited, a joiner may have
        // resumed first and a later call registered its own attempt.
        defer { if inflightConnect?.id == id { inflightConnect = nil } }
        return try await task.value
    }

    /// Not marked paired, but worth one attempt: Fling dropped the mark itself
    /// earlier in this run, and the TV may trust this Mac all the same.
    public func mayTry(host: String) -> Bool {
        store.identityExists && droppedMarks.contains(host) && !recentlyRefused(host)
    }

    public func recentlyRefused(_ host: String) -> Bool {
        guard let at = refusedAt[host] else { return false }
        return Date().timeIntervalSince(at) < refusalMemory
    }

    /// Ends a retry wait at once (another TV chosen, pairing started).
    public func stopReconnecting() {
        guard waitingHost != nil else { return }
        inflightConnect?.task.cancel()
    }

    /// The TLS refusal policy around `ATVRemoteClient.connect`.
    private func connectWithRetries(host: String) async throws -> Bool {
        let waits = hasPairing(host: host) && !recentlyRefused(host) ? retryWaits : []
        var waited = false
        var attempt = 0
        while true {
            do {
                try await remote.connect(host: host)
                break
            } catch ATVError.tlsHandshakeFailed(let detail) {
                if Task.isCancelled { throw ATVError.superseded }
                guard attempt < waits.count else {
                    refusedAt[host] = Date()
                    if store.pairedHosts().contains(host) {
                        // The TV really has forgotten this Mac: the panel offers "Pair with TV".
                        store.removePairedHost(host)
                        droppedMarks.insert(host)
                        ATVLog.shared.log("remote", "\(host) refused this Mac after \(attempt + 1) attempts (\(detail)); pairing mark dropped")
                    }
                    throw ATVError.tlsHandshakeFailed(detail)
                }
                let wait = waits[attempt]
                attempt += 1
                ATVLog.shared.log("remote", "\(host) TLS refused (\(detail)); retry \(attempt)/\(waits.count) in \(wait) s")
                waitingHost = host
                do {
                    try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                } catch {
                    waitingHost = nil
                    ATVLog.shared.log("remote", "\(host) retry wait stopped")
                    throw ATVError.superseded
                }
                waitingHost = nil
                waited = true
                // Paired again or forgotten meanwhile: this attempt is no longer wanted.
                guard hasPairing(host: host) else { throw ATVError.superseded }
            } catch {
                if Task.isCancelled { throw ATVError.superseded }
                throw error
            }
        }
        if !store.pairedHosts().contains(host) {
            // The TV accepted the certificate, so it does trust this Mac: the
            // mark was lost, not the pairing.
            store.recordPairedHost(host)
            ATVLog.shared.log("remote", "\(host) still trusts this Mac; pairing mark restored")
        }
        droppedMarks.remove(host)
        refusedAt[host] = nil
        return waited
    }

    /// Power state from the TV's last RemoteStart; meaningful once connected.
    public var isOn: Bool {
        get async { await remote.isOn }
    }

    /// Toggles power, connecting first if needed. Pass `host` on the first call;
    /// later calls fall back to the last host used.
    public func togglePower(host: String? = nil) async throws {
        try await ensureConnected(host: host)
        try await remote.powerToggle()
    }

    /// Sends any keycode (see `ATVKeyCode`), connecting on demand.
    public func pressKey(_ code: Int32, host: String? = nil) async throws {
        try await ensureConnected(host: host)
        try await remote.sendKey(code)
    }

    /// Launches an app, connecting on demand. A bare app id (no URL scheme)
    /// becomes a `market://launch?id=…` link.
    public func launchApp(link: String, host: String? = nil) async throws {
        try await ensureConnected(host: host)
        try await remote.launchApp(link: Self.normalizeAppLink(link))
    }

    /// Commits text via the IME, connecting on demand. Only lands when a text
    /// field is focused on the TV.
    public func sendText(_ text: String, host: String? = nil) async throws {
        try await ensureConnected(host: host)
        try await remote.sendText(text)
    }

    // MARK: - voice

    /// Opens a voice session (KEYCODE_SEARCH → RemoteVoiceBegin handshake).
    /// Requires the facade to have been constructed with `enableVoice: true`.
    public func beginVoice(host: String? = nil) async throws {
        try await ensureConnected(host: host)
        try await remote.beginVoice()
    }

    /// Streams one PCM chunk: 16-bit little-endian, mono, 8000 Hz. Chunks under
    /// 8 KB are zero-padded; over 20 KB are split.
    public func sendVoice(pcm: Data) async throws {
        try await remote.sendVoice(pcm: pcm)
    }

    public func endVoice() async throws {
        try await remote.endVoice()
    }

    /// Connection, power, and foreground-app events from the remote session.
    public func events() async -> AsyncStream<ATVRemoteClient.Event> {
        await remote.events()
    }

    // MARK: - plumbing

    /// Connects when disconnected — and also when connected to a *different*
    /// TV than requested, since sending there would steer the wrong device.
    /// Throws `commandDropped` when the connect had to wait for a retry — the
    /// command would arrive seconds after the press.
    private func ensureConnected(host: String?) async throws {
        if let host { lastHost = host }
        guard let target = lastHost else { throw ATVError.noHostConfigured }
        if await remote.isConnected, await remote.connectedHost == target { return }
        if try await connectTracked(host: target) { throw ATVError.commandDropped }
    }

    /// androidtv_remote.py send_launch_app_command: a value without a URL scheme
    /// is a Play Store package id.
    static func normalizeAppLink(_ link: String) -> String {
        hasURLScheme(link) ? link : "market://launch?id=\(link)"
    }

    private static func hasURLScheme(_ link: String) -> Bool {
        guard let range = link.range(of: "://") else { return false }
        let scheme = link[link.startIndex ..< range.lowerBound]
        return !scheme.isEmpty && scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
    }
}
