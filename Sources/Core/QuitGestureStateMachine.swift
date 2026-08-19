import Foundation

public enum QuitGestureAction: Equatable {
    case consume
    case passThrough
    case began
    case resolved
    case blocked
    case quit
}

public struct QuitGestureStateMachine {
    public private(set) var waitingForSecondPress = false
    public private(set) var holding = false
    public private(set) var holdConfirmed = false
    public private(set) var blockedCount = 0
    private var lastDoublePressTime: TimeInterval?
    private var holdStartTime: TimeInterval?

    public init() {}

    public mutating func reset() {
        waitingForSecondPress = false
        holding = false
        holdConfirmed = false
        lastDoublePressTime = nil
        holdStartTime = nil
    }

    public mutating func doublePressKeyDown(now: TimeInterval, interval: TimeInterval, isRepeat: Bool) -> QuitGestureAction {
        guard !isRepeat else { return .consume }
        if waitingForSecondPress, let lastDoublePressTime,
           now - lastDoublePressTime < interval {
            waitingForSecondPress = false
            self.lastDoublePressTime = nil
            return .passThrough
        }
        if waitingForSecondPress { blockedCount += 1 }
        waitingForSecondPress = true
        lastDoublePressTime = now
        return .began
    }

    public mutating func doublePressExpired(now: TimeInterval, interval: TimeInterval) -> QuitGestureAction {
        guard waitingForSecondPress, let lastDoublePressTime,
              now - lastDoublePressTime >= interval else { return .consume }
        waitingForSecondPress = false
        self.lastDoublePressTime = nil
        blockedCount += 1
        return .blocked
    }

    public mutating func holdKeyDown(now: TimeInterval) -> QuitGestureAction {
        guard !holding else { return .consume }
        holding = true
        holdConfirmed = false
        holdStartTime = now
        return .began
    }

    public mutating func holdDurationReached(now: TimeInterval, duration: TimeInterval) -> QuitGestureAction {
        guard holding, !holdConfirmed, let holdStartTime,
              now - holdStartTime >= duration else { return .consume }
        holdConfirmed = true
        return .quit
    }

    public mutating func holdReleased() -> QuitGestureAction {
        guard holding else { return .consume }
        let action: QuitGestureAction = holdConfirmed ? .resolved : .blocked
        if !holdConfirmed { blockedCount += 1 }
        holding = false
        holdConfirmed = false
        holdStartTime = nil
        return action
    }
}
