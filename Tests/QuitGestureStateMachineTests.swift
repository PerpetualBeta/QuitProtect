import XCTest
@testable import QuitProtectCore

final class QuitGestureStateMachineTests: XCTestCase {

    func testSettingsPolicyMatchesSettingsChoices() {
        XCTAssertEqual(QuitProtectSettingsPolicy.defaultHoldDuration, 1.0)
        XCTAssertEqual(QuitProtectSettingsPolicy.defaultDoublePressInterval, 0.4)
        XCTAssertEqual(QuitProtectSettingsPolicy.holdDurations, [0.5, 1.0, 1.5, 2.0])
        XCTAssertEqual(QuitProtectSettingsPolicy.doublePressIntervals, [0.3, 0.4, 0.5, 0.75])
    }

    func testSettingsPolicyRejectsValuesNotPresentedByTheSettingsUI() {
        XCTAssertTrue(QuitProtectSettingsPolicy.validHoldDuration(1.5))
        XCTAssertFalse(QuitProtectSettingsPolicy.validHoldDuration(3.0))
        XCTAssertTrue(QuitProtectSettingsPolicy.validDoublePressInterval(0.75))
        XCTAssertFalse(QuitProtectSettingsPolicy.validDoublePressInterval(1.0))
    }

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
