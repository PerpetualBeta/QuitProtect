import XCTest
@testable import QuitProtectCore

final class QuitGestureStateMachineTests: XCTestCase {
    func testHoldCanStartAgainAfterThresholdAndRelease() {
        var machine = QuitGestureStateMachine()

        XCTAssertEqual(machine.holdKeyDown(now: 0), .began)
        XCTAssertEqual(machine.holdDurationReached(now: 1, duration: 1), .quit)
        XCTAssertEqual(machine.holdReleased(), .resolved)
        XCTAssertEqual(machine.holdKeyDown(now: 2), .began)
        XCTAssertEqual(machine.holdDurationReached(now: 3, duration: 1), .quit)
        XCTAssertEqual(machine.blockedCount, 0)
    }

    func testEarlyHoldReleaseCountsBlockedAndResets() {
        var machine = QuitGestureStateMachine()

        _ = machine.holdKeyDown(now: 0)
        XCTAssertEqual(machine.holdReleased(), .blocked)
        XCTAssertEqual(machine.blockedCount, 1)
        XCTAssertFalse(machine.holding)
    }

    func testDoublePressRepeatsAreConsumedWithoutStartingGesture() {
        var machine = QuitGestureStateMachine()

        XCTAssertEqual(machine.doublePressKeyDown(now: 0, interval: 0.4, isRepeat: true), .consume)
        XCTAssertFalse(machine.waitingForSecondPress)
    }

    func testDoublePressPassesOnlyTheSecondPress() {
        var machine = QuitGestureStateMachine()

        XCTAssertEqual(machine.doublePressKeyDown(now: 0, interval: 0.4, isRepeat: false), .began)
        XCTAssertEqual(machine.doublePressKeyDown(now: 0.2, interval: 0.4, isRepeat: false), .passThrough)
        XCTAssertFalse(machine.waitingForSecondPress)
    }

    func testCoordinatorResolvesDoublePressAndTimeoutInOneEventFlow() {
        let coordinator = QuitGestureCoordinator()

        XCTAssertEqual(
            coordinator.handle(.keyDown(now: 0, isRepeat: false)),
            QuitGestureResult(
                disposition: .consume,
                guidance: .began,
                timeoutAfter: 0.4,
                timeoutToken: 1
            )
        )
        XCTAssertEqual(
            coordinator.handle(.keyUp),
            QuitGestureResult(disposition: .consume)
        )
        XCTAssertEqual(
            coordinator.handle(.timeout(token: 1, now: 0.5)),
            QuitGestureResult(disposition: .consume, guidance: .resolved)
        )
        XCTAssertEqual(coordinator.blockedCount, 1)
    }

    func testCoordinatorPassesSecondDoublePressAndDoesNotCountItAsBlocked() {
        let coordinator = QuitGestureCoordinator()

        _ = coordinator.handle(.keyDown(now: 0, isRepeat: false))
        XCTAssertEqual(
            coordinator.handle(.keyDown(now: 0.2, isRepeat: false)),
            QuitGestureResult(disposition: .passThrough, guidance: .resolved)
        )
        XCTAssertEqual(coordinator.blockedCount, 0)
    }

    func testCoordinatorIgnoresStaleTimeoutAfterStartingANewDoublePress() {
        let coordinator = QuitGestureCoordinator()

        let first = coordinator.handle(.keyDown(now: 0, isRepeat: false))
        let second = coordinator.handle(.keyDown(now: 1, isRepeat: false))

        XCTAssertEqual(first.timeoutToken, 1)
        XCTAssertEqual(second.timeoutToken, 2)
        XCTAssertEqual(
            coordinator.handle(.timeout(token: 1, now: 1.1)),
            QuitGestureResult(disposition: .consume)
        )
        XCTAssertEqual(
            coordinator.handle(.timeout(token: 2, now: 1.5)),
            QuitGestureResult(disposition: .consume, guidance: .resolved)
        )
        XCTAssertEqual(coordinator.blockedCount, 2)
    }

    func testCoordinatorResetsHoldWhenCommandIsReleased() {
        let coordinator = QuitGestureCoordinator(mode: .holdToQuit, holdDuration: 1)

        XCTAssertEqual(
            coordinator.handle(.keyDown(now: 0, isRepeat: false)),
            QuitGestureResult(mode: .holdToQuit, disposition: .consume, guidance: .began)
        )
        XCTAssertEqual(
            coordinator.handle(.commandReleased),
            QuitGestureResult(mode: .holdToQuit, disposition: .passThrough, guidance: .resolved)
        )
        XCTAssertEqual(
            coordinator.handle(.keyDown(now: 2, isRepeat: false)),
            QuitGestureResult(mode: .holdToQuit, disposition: .consume, guidance: .began)
        )
        XCTAssertEqual(coordinator.blockedCount, 1)
    }

    func testCoordinatorInvalidatesPendingTimeoutWhenDoublePressIntervalChanges() {
        let coordinator = QuitGestureCoordinator(doublePressInterval: 0.4)

        let first = coordinator.handle(.keyDown(now: 0, isRepeat: false))
        XCTAssertEqual(first.timeoutToken, 1)

        coordinator.update(doublePressInterval: 0.75)

        XCTAssertEqual(
            coordinator.handle(.timeout(token: 1, now: 0.4)),
            QuitGestureResult(disposition: .consume)
        )
        let next = coordinator.handle(.keyDown(now: 0.5, isRepeat: false))
        XCTAssertEqual(next.timeoutToken, 2)
        XCTAssertEqual(next.timeoutAfter, 0.75)
        XCTAssertEqual(
            coordinator.handle(.timeout(token: 2, now: 1.25)),
            QuitGestureResult(disposition: .consume, guidance: .resolved)
        )
        XCTAssertEqual(coordinator.blockedCount, 1)
    }

    func testCoordinatorSerializesConcurrentEvents() {
        let coordinator = QuitGestureCoordinator(mode: .holdToQuit, holdDuration: 1)
        let resultLock = NSLock()
        var results: [QuitGestureResult] = []

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let result = coordinator.handle(.keyDown(now: Double(index), isRepeat: false))
            resultLock.lock()
            results.append(result)
            resultLock.unlock()
        }

        XCTAssertEqual(results.count, 100)
        XCTAssertEqual(results.filter { $0.guidance == .began }.count, 1)
        XCTAssertTrue(results.allSatisfy { $0.disposition == .consume })
        XCTAssertTrue(results.allSatisfy { !$0.shouldQuit })
        XCTAssertEqual(
            coordinator.handle(.keyUp),
            QuitGestureResult(mode: .holdToQuit, disposition: .consume, guidance: .resolved)
        )
        XCTAssertEqual(coordinator.blockedCount, 1)
    }
}
