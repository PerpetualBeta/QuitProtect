import XCTest
@testable import QuitProtectCore

final class QuitGestureStateMachineTests: XCTestCase {

    func testDoublePressConsumesFirstAndPassesSecond() {
        var machine = QuitGestureStateMachine()

        XCTAssertEqual(machine.doublePressKeyDown(isRepeat: false), .began)
        XCTAssertEqual(machine.doublePressKeyDown(isRepeat: false), .passThrough)
        XCTAssertFalse(machine.waitingForSecondPress)
        XCTAssertEqual(machine.blockedCount, 0)
    }

    func testDoublePressTimeoutCountsBlockedQuit() {
        var machine = QuitGestureStateMachine()

        _ = machine.doublePressKeyDown(isRepeat: false)
        XCTAssertEqual(machine.doublePressExpired(), .blocked)
        XCTAssertEqual(machine.blockedCount, 1)
        XCTAssertEqual(machine.doublePressExpired(), .consume)
    }

    func testDoublePressRepeatsAreConsumedWithoutStartingGesture() {
        var machine = QuitGestureStateMachine()

        XCTAssertEqual(machine.doublePressKeyDown(isRepeat: true), .consume)
        XCTAssertFalse(machine.waitingForSecondPress)
    }

    func testHoldReleasedEarlyIsBlocked() {
        var machine = QuitGestureStateMachine()

        XCTAssertEqual(machine.holdKeyDown(), .began)
        XCTAssertEqual(machine.holdReleased(), .blocked)
        XCTAssertEqual(machine.blockedCount, 1)
    }

    func testHoldOnlyQuitsOnceAndSuccessfulReleaseIsNotBlocked() {
        var machine = QuitGestureStateMachine()

        _ = machine.holdKeyDown()
        XCTAssertEqual(machine.holdDurationReached(), .quit)
        XCTAssertEqual(machine.holdDurationReached(), .consume)
        XCTAssertEqual(machine.holdReleased(), .resolved)
        XCTAssertEqual(machine.blockedCount, 0)
    }

    func testChangingModeCancelsPendingGesture() {
        var machine = QuitGestureStateMachine()

        _ = machine.doublePressKeyDown(isRepeat: false)
        XCTAssertEqual(machine.modeChanged(), .resolved)
        XCTAssertEqual(machine.doublePressExpired(), .consume)
    }
}
