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

/// Serializes access to the gesture state shared by the CGEvent callback and
/// main-queue timeout callbacks. The state machine remains pure and directly
/// testable; this is the production concurrency boundary.
public final class QuitGestureStateStore {
    private let lock = NSLock()
    private var machine = QuitGestureStateMachine()

    public init() {}

    public var waitingForSecondPress: Bool { withLock { machine.waitingForSecondPress } }
    public var holding: Bool { withLock { machine.holding } }
    public var holdConfirmed: Bool { withLock { machine.holdConfirmed } }
    public var blockedCount: Int { withLock { machine.blockedCount } }

    public func reset() { withLock { machine.reset() } }
    public func doublePressKeyDown(now: TimeInterval, interval: TimeInterval, isRepeat: Bool) -> QuitGestureAction {
        withLock { machine.doublePressKeyDown(now: now, interval: interval, isRepeat: isRepeat) }
    }
    public func doublePressExpired(now: TimeInterval, interval: TimeInterval) -> QuitGestureAction {
        withLock { machine.doublePressExpired(now: now, interval: interval) }
    }
    public func holdKeyDown(now: TimeInterval) -> QuitGestureAction {
        withLock { machine.holdKeyDown(now: now) }
    }
    public func holdDurationReached(now: TimeInterval, duration: TimeInterval) -> QuitGestureAction {
        withLock { machine.holdDurationReached(now: now, duration: duration) }
    }
    public func holdReleased() -> QuitGestureAction {
        withLock { machine.holdReleased() }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
