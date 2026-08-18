import Foundation

public enum QuitGestureAction: Equatable {
    case consume
    case passThrough
    case began
    case resolved
    case blocked
    case quit
}

/// Pure gesture logic. The event tap supplies key transitions and timestamps;
/// this type deliberately knows nothing about AppKit or Accessibility.
public struct QuitGestureStateMachine {
    public private(set) var waitingForSecondPress = false
    public private(set) var holding = false
    public private(set) var holdConfirmed = false
    public private(set) var blockedCount = 0

    public init() {}

    public mutating func modeChanged() -> QuitGestureAction {
        waitingForSecondPress = false
        holding = false
        holdConfirmed = false
        return .resolved
    }

    public mutating func doublePressKeyDown(isRepeat: Bool) -> QuitGestureAction {
        guard !isRepeat else { return .consume }
        if waitingForSecondPress {
            waitingForSecondPress = false
            return .passThrough
        }
        waitingForSecondPress = true
        return .began
    }

    public mutating func doublePressExpired() -> QuitGestureAction {
        guard waitingForSecondPress else { return .consume }
        waitingForSecondPress = false
        blockedCount += 1
        return .blocked
    }

    public mutating func holdKeyDown() -> QuitGestureAction {
        guard !holding else { return .consume }
        holding = true
        holdConfirmed = false
        return .began
    }

    public mutating func holdDurationReached() -> QuitGestureAction {
        guard holding, !holdConfirmed else { return .consume }
        holdConfirmed = true
        return .quit
    }

    public mutating func holdReleased() -> QuitGestureAction {
        guard holding else { return .consume }
        let action: QuitGestureAction = holdConfirmed ? .resolved : .blocked
        if !holdConfirmed { blockedCount += 1 }
        holding = false
        holdConfirmed = false
        return action
    }
}
