import Foundation

/// Turns a mouse drag on the remote's touchpad into d-pad steps, like
/// `ScrollNav` does for scroll gestures: every `step` points along the
/// dominant axis is one arrow press, and drift on the other axis is dropped.
public struct TouchpadNav {

    /// Points of drag per d-pad step.
    public static let step: CGFloat = 34
    /// A jump this big in one event (a lost drag, a fast fling) still moves
    /// a few rows, not across the whole grid.
    public static let maxStepsPerEvent = 4

    private var accX: CGFloat = 0
    private var accY: CGFloat = 0

    public init() {}

    /// `dx` / `dy` in view points, y growing downwards. Returns keycodes, oldest first.
    public mutating func drag(dx: CGFloat, dy: CGFloat) -> [Int32] {
        accX += dx
        accY += dy
        var keys: [Int32] = []
        while keys.count < Self.maxStepsPerEvent {
            if abs(accX) >= Self.step && abs(accX) >= abs(accY) {
                keys.append(accX > 0 ? ATVKeyCode.dpadRight : ATVKeyCode.dpadLeft)
                accX -= accX > 0 ? Self.step : -Self.step
                accY = 0
            } else if abs(accY) >= Self.step {
                keys.append(accY > 0 ? ATVKeyCode.dpadDown : ATVKeyCode.dpadUp)
                accY -= accY > 0 ? Self.step : -Self.step
                accX = 0
            } else {
                break
            }
        }
        return keys
    }

    public mutating func reset() { accX = 0; accY = 0 }
}
