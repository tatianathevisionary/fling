import Foundation

/// What the panel says when the TV remote fails: plain words instead of raw
/// network / certificate errors, which go to ~/Library/Logs/Fling.log instead.
/// The UI translates these with `tr()` (English keys, Russian in L10n.swift).
public enum TVConnectionText {
    public static let forgotten =
        "The TV has forgotten this Mac — it happens after a TV reset or update. Click “Pair with TV” and type the code from the TV screen."
    public static let notPaired =
        "The remote isn't paired with the TV. Click “Pair with TV” and type the code from the TV screen."
    public static let unreachable =
        "The remote isn't answering: the TV is off or on another network. Try again when the TV is on."
    public static let dropped = "The connection to the TV remote dropped. Press again to reconnect."
    public static let timeout = "The TV didn't answer in time. Try again."
    /// Grey progress note (ends with "…"): the connect waits to retry.
    public static let reconnecting = "Reconnecting to the TV…"
    public static let noTV = "No TV found yet — check that the TV is on and on the same Wi-Fi as this Mac."
    public static let certificate = "Fling couldn't prepare this Mac's remote key. Try “Pair with TV” again."
    public static let wrongPIN = "That code doesn't match — read it off the TV again."
    public static let pinRejected = "The TV rejected the pairing code. Start over."
    public static let voiceDeclined = "This TV session declined voice — use typed search instead."
    public static let voiceTimeout = "The TV didn't open voice search."
    public static let generic = "The TV remote didn't work this time. Try again."

    /// nil: nothing to show (the command was dropped or stopped on purpose).
    public static func message(for error: Error) -> String? {
        switch error {
        case ATVError.commandDropped, ATVError.superseded, is CancellationError:
            return nil
        case ATVError.voiceSessionActive:
            return nil                      // a second mic press while one is opening
        case ATVError.reconnecting:
            return reconnecting
        case ATVError.invalidPIN:
            return wrongPIN
        case ATVError.serverStatus:
            return pinRejected
        case ATVError.tlsHandshakeFailed:
            return forgotten
        case ATVError.connectionFailed:
            return unreachable
        case ATVError.connectionClosed, ATVError.notConnected:
            return dropped
        case ATVError.connectionTimeout:
            return timeout
        case ATVError.certificateFailure:
            return certificate
        case ATVError.notPaired, ATVError.pairingNotStarted, ATVError.noHostConfigured:
            return notPaired
        case ATVError.voiceNotEnabled:
            return voiceDeclined
        case ATVError.voiceTimeout:
            return voiceTimeout
        default:
            return generic
        }
    }

    /// Grey for "…in progress" notes, red for errors.
    public static func isProgressNote(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).hasSuffix("…")
    }
}
