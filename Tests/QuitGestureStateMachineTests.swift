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

    func testVisibilityStorePersistsOnlyRealChanges() {
        let suite = UserDefaults(suiteName: "QuitProtectTests.visibility")!
        suite.removePersistentDomain(forName: "QuitProtectTests.visibility")
        let store = StatusItemVisibilityStore(defaults: suite, key: "hidden")

        XCTAssertTrue(store.isVisible)
        XCTAssertFalse(store.setVisible(true))
        XCTAssertTrue(store.setVisible(false))
        XCTAssertFalse(store.isVisible)
        XCTAssertFalse(store.setVisible(false))
        XCTAssertTrue(store.setVisible(true))
        XCTAssertTrue(store.isVisible)
    }

    func testMenuContractProtectsSettingsAndQuitShortcuts() {
        XCTAssertEqual(QuitProtectMenuContract.settingsKeyEquivalent, ",")
        XCTAssertEqual(QuitProtectMenuContract.quitKeyEquivalent, "q")
        XCTAssertEqual(QuitProtectMenuContract.quitTitle(appName: "QuitProtect"), "Quit QuitProtect")
    }

    func testPermissionPolicyDoesNotReadDuringTCCSettlement() {
        var policy = PermissionRefreshPolicy(isGranted: false)
        policy.announceChange(at: 10, settleFor: 1.5)

        XCTAssertFalse(policy.reread(at: 10.5, value: true))
        XCTAssertFalse(policy.isGranted)
        XCTAssertTrue(policy.reread(at: 11.5, value: true))
        XCTAssertTrue(policy.isGranted)
        XCTAssertFalse(policy.reread(at: 12, value: true))
    }

    func testSettingsWindowSizingHasFloorAndDisplayCeiling() {
        let result = SettingsWindowSizing.contentSize(
            fittingWidth: 900,
            fittingHeight: 1600,
            visibleWidth: 1440,
            visibleHeight: 900,
            chromeHeight: 24
        )

        XCTAssertEqual(result.width, 900)
        XCTAssertEqual(result.height, 696)
        XCTAssertEqual(
            SettingsWindowSizing.contentSize(
                fittingWidth: 100,
                fittingHeight: 100,
                visibleWidth: 500,
                visibleHeight: 500,
                chromeHeight: 24
            ).width,
            420
        )
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
