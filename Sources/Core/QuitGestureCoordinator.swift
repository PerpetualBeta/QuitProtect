import Dispatch
import Foundation

public enum QuitGestureMode: Equatable {
    case doublePress
    case holdToQuit
}

/// The only inputs that can change gesture state. The event tap and timeout
/// callback both translate their inputs into this value type.
public enum QuitGestureEvent: Equatable {
    case keyDown(now: TimeInterval, isRepeat: Bool)
    case keyUp
    case commandReleased
    case timeout(token: UInt64, now: TimeInterval)
    case reset
}

public enum QuitGestureDisposition: Equatable {
    case consume
    case passThrough
}

public enum QuitGestureGuidance: Equatable {
    case none
    case began
    case resolved
}

public struct QuitGestureResult: Equatable {
    public let mode: QuitGestureMode
    public let disposition: QuitGestureDisposition
    public let guidance: QuitGestureGuidance
    public let shouldQuit: Bool
    public let timeoutAfter: TimeInterval?
    public let timeoutToken: UInt64?

    public init(
        mode: QuitGestureMode = .doublePress,
        disposition: QuitGestureDisposition,
        guidance: QuitGestureGuidance = .none,
        shouldQuit: Bool = false,
        timeoutAfter: TimeInterval? = nil,
        timeoutToken: UInt64? = nil
    ) {
        self.mode = mode
        self.disposition = disposition
        self.guidance = guidance
        self.shouldQuit = shouldQuit
        self.timeoutAfter = timeoutAfter
        self.timeoutToken = timeoutToken
    }
}

/// Owns the complete gesture event flow.
///
/// CGEvent callbacks must return synchronously, while timeout callbacks may
/// arrive from another execution context. A private serial queue gives both
/// paths one synchronous reducer entrance without allowing UI or event-posting
/// side effects to run while the gesture state is being updated.
public final class QuitGestureCoordinator {
    private let queue = DispatchQueue(label: "cc.jorviksoftware.QuitProtect.gesture")
    private var machine = QuitGestureStateMachine()
    private var configuredMode: QuitGestureMode
    private var configuredHoldDuration: TimeInterval
    private var configuredDoublePressInterval: TimeInterval
    private var nextTimeoutToken: UInt64 = 0
    private var activeTimeoutToken: UInt64?

    public init(
        mode: QuitGestureMode = .doublePress,
        holdDuration: TimeInterval = QuitGestureTiming.defaultHoldDuration,
        doublePressInterval: TimeInterval = QuitGestureTiming.defaultDoublePressInterval
    ) {
        self.configuredMode = mode
        self.configuredHoldDuration = QuitGestureTiming.checkedHoldDuration(holdDuration)
        self.configuredDoublePressInterval = QuitGestureTiming.checkedDoublePressInterval(
            doublePressInterval
        )
    }

    public var blockedCount: Int {
        queue.sync { machine.blockedCount }
    }

    public var mode: QuitGestureMode {
        queue.sync { configuredMode }
    }

    public func configure(
        mode: QuitGestureMode,
        holdDuration: TimeInterval,
        doublePressInterval: TimeInterval
    ) {
        queue.sync {
            self.configuredMode = mode
            self.configuredHoldDuration = QuitGestureTiming.checkedHoldDuration(holdDuration)
            self.configuredDoublePressInterval = QuitGestureTiming.checkedDoublePressInterval(
                doublePressInterval
            )
            activeTimeoutToken = nil
            machine.reset()
        }
    }

    public func update(mode: QuitGestureMode) {
        queue.sync {
            guard self.configuredMode != mode else { return }
            self.configuredMode = mode
            activeTimeoutToken = nil
            machine.reset()
        }
    }

    public func update(holdDuration: TimeInterval) {
        queue.sync {
            self.configuredHoldDuration = QuitGestureTiming.checkedHoldDuration(holdDuration)
        }
    }

    public func update(doublePressInterval: TimeInterval) {
        queue.sync {
            self.configuredDoublePressInterval = QuitGestureTiming.checkedDoublePressInterval(
                doublePressInterval
            )
            activeTimeoutToken = nil
            machine.reset()
        }
    }

    public func reset() {
        queue.sync {
            activeTimeoutToken = nil
            machine.reset()
        }
    }

    public func handle(_ event: QuitGestureEvent) -> QuitGestureResult {
        queue.sync { reduce(event) }
    }

    private func reduce(_ event: QuitGestureEvent) -> QuitGestureResult {
        switch event {
        case let .keyDown(now, isRepeat):
            return reduceKeyDown(now: now, isRepeat: isRepeat)
        case .keyUp:
            return reduceKeyUp()
        case .commandReleased:
            return reduceCommandReleased()
        case let .timeout(token, now):
            return reduceTimeout(token: token, now: now)
        case .reset:
            activeTimeoutToken = nil
            machine.reset()
            return makeResult(disposition: .passThrough)
        }
    }

    private func makeResult(
        disposition: QuitGestureDisposition,
        guidance: QuitGestureGuidance = .none,
        shouldQuit: Bool = false,
        timeoutAfter: TimeInterval? = nil,
        timeoutToken: UInt64? = nil
    ) -> QuitGestureResult {
        QuitGestureResult(
            mode: configuredMode,
            disposition: disposition,
            guidance: guidance,
            shouldQuit: shouldQuit,
            timeoutAfter: timeoutAfter,
            timeoutToken: timeoutToken
        )
    }

    private func reduceKeyDown(now: TimeInterval, isRepeat: Bool) -> QuitGestureResult {
        switch configuredMode {
        case .doublePress:
            switch machine.doublePressKeyDown(
                now: now,
                interval: configuredDoublePressInterval,
                isRepeat: isRepeat
            ) {
            case .passThrough:
                activeTimeoutToken = nil
                return makeResult(disposition: .passThrough, guidance: .resolved)
            case .began:
                nextTimeoutToken &+= 1
                activeTimeoutToken = nextTimeoutToken
                return makeResult(
                    disposition: .consume,
                    guidance: .began,
                    timeoutAfter: configuredDoublePressInterval,
                    timeoutToken: nextTimeoutToken
                )
            case .consume:
                return makeResult(disposition: .consume)
            case .blocked, .resolved, .quit:
                assertionFailure("Unexpected double-press transition")
                return makeResult(disposition: .consume)
            }

        case .holdToQuit:
            if !machine.holding {
                _ = machine.holdKeyDown(now: now)
                return makeResult(disposition: .consume, guidance: .began)
            }

            guard isRepeat else {
                return makeResult(disposition: .consume)
            }

            let action = machine.holdDurationReached(now: now, duration: configuredHoldDuration)
            return makeResult(
                disposition: .consume,
                guidance: action == .quit ? .resolved : .none,
                shouldQuit: action == .quit
            )
        }
    }

    private func reduceKeyUp() -> QuitGestureResult {
        switch configuredMode {
        case .doublePress:
            return machine.waitingForSecondPress
                ? makeResult(disposition: .consume)
                : makeResult(disposition: .passThrough)

        case .holdToQuit:
            guard machine.holding else {
                return makeResult(disposition: .passThrough)
            }
            let action = machine.holdReleased()
            return makeResult(
                disposition: .consume,
                guidance: action == .blocked || action == .resolved ? .resolved : .none
            )
        }
    }

    private func reduceCommandReleased() -> QuitGestureResult {
        guard configuredMode == .holdToQuit, machine.holding else {
            return makeResult(disposition: .passThrough)
        }
        let action = machine.holdReleased()
        return makeResult(
            disposition: .passThrough,
            guidance: action == .blocked || action == .resolved ? .resolved : .none
        )
    }

    private func reduceTimeout(token: UInt64, now: TimeInterval) -> QuitGestureResult {
        guard configuredMode == .doublePress else {
            return makeResult(disposition: .consume)
        }
        guard activeTimeoutToken == token else {
            return makeResult(disposition: .consume)
        }
        let action = machine.doublePressExpired(now: now, interval: configuredDoublePressInterval)
        if action == .blocked {
            activeTimeoutToken = nil
        }
        return makeResult(
            disposition: .consume,
            guidance: action == .blocked ? .resolved : .none
        )
    }
}
