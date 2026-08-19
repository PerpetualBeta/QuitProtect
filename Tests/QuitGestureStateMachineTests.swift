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
}
