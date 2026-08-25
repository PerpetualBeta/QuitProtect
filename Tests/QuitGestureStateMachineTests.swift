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

    // The coordinator is checked, not merely normalised: passing it an out-of-catalog
    // value trips `assertionFailure` in debug, so these tests cover the normalising
    // policy at `QuitGestureTiming` and cover the coordinator with catalog values only.

    func testCoordinatorHonoursANonDefaultCatalogHoldDuration() {
        let coordinator = QuitGestureCoordinator(mode: .holdToQuit, holdDuration: 2.0)

        _ = coordinator.handle(.keyDown(now: 0, isRepeat: false))
        XCTAssertFalse(coordinator.handle(.keyDown(now: 1, isRepeat: true)).shouldQuit)
        XCTAssertFalse(coordinator.handle(.keyDown(now: 1.9, isRepeat: true)).shouldQuit)
        XCTAssertTrue(coordinator.handle(.keyDown(now: 2, isRepeat: true)).shouldQuit)
    }

    func testCoordinatorHonoursANonDefaultCatalogHoldDurationAfterAnUpdate() {
        let coordinator = QuitGestureCoordinator(mode: .holdToQuit)
        coordinator.update(holdDuration: 0.5)

        _ = coordinator.handle(.keyDown(now: 0, isRepeat: false))
        XCTAssertFalse(coordinator.handle(.keyDown(now: 0.25, isRepeat: true)).shouldQuit)
        XCTAssertTrue(coordinator.handle(.keyDown(now: 0.5, isRepeat: true)).shouldQuit)
    }

    // A hold guard gets stricter as it gets longer, so an unsupported value must round UP.
    // Rounding to the nearest option, or to the default, would silently weaken a guard
    // that somebody deliberately set high.
    func testHoldDurationSnapsUpToTheNextSupportedOption() {
        let expectations: [(input: TimeInterval, expected: TimeInterval)] = [
            (0.1, 0.5),   // below the catalog: the weakest option is as close as it gets
            (0.5, 0.5),
            (0.6, 1.0),
            (1.0, 1.0),
            (1.4, 1.5),
            (1.9, 2.0),   // asked for stricter than 1.5, so must not drop to 1.5
            (2.0, 2.0),
            (10, 2.0),    // past the catalog: pin to the strictest option
        ]

        for (input, expected) in expectations {
            XCTAssertEqual(
                QuitGestureTiming.normalizedHoldDuration(input),
                expected,
                "hold duration \(input) should snap to \(expected)"
            )
        }
    }

    // A double-press window gets stricter as it gets shorter, so it rounds DOWN.
    func testDoublePressIntervalSnapsDownToTheNextSupportedOption() {
        let expectations: [(input: TimeInterval, expected: TimeInterval)] = [
            (0.1, 0.3),   // below the catalog: the strictest option is as close as it gets
            (0.3, 0.3),
            (0.35, 0.3),
            (0.4, 0.4),
            (0.6, 0.5),
            (0.75, 0.75),
            (10, 0.75),   // past the catalog: pin to the laxest option
        ]

        for (input, expected) in expectations {
            XCTAssertEqual(
                QuitGestureTiming.normalizedDoublePressInterval(input),
                expected,
                "double-press interval \(input) should snap to \(expected)"
            )
        }
    }

    // Nonsense is not a preference to honour, so it goes to the shipped default rather
    // than to an end of the catalog.
    func testNonsenseTimingsFallBackToTheShippedDefaults() {
        for nonsense in [-1.0, 0, .nan, .infinity, -.infinity] {
            XCTAssertEqual(
                QuitGestureTiming.normalizedHoldDuration(nonsense),
                QuitGestureTiming.defaultHoldDuration,
                "hold duration \(nonsense) should use the default"
            )
            XCTAssertEqual(
                QuitGestureTiming.normalizedDoublePressInterval(nonsense),
                QuitGestureTiming.defaultDoublePressInterval,
                "double-press interval \(nonsense) should use the default"
            )
        }
    }

    func testGestureTimingPreservesEverySupportedValue() {
        for duration in QuitGestureTiming.supportedHoldDurations {
            XCTAssertEqual(QuitGestureTiming.normalizedHoldDuration(duration), duration)
        }
        for interval in QuitGestureTiming.supportedDoublePressIntervals {
            XCTAssertEqual(QuitGestureTiming.normalizedDoublePressInterval(interval), interval)
        }
    }

    func testGestureTimingOptionsAreValidSingleSourcesOfTruth() {
        for (options, defaultValue) in [
            (QuitGestureTiming.holdOptions, QuitGestureTiming.defaultHoldDuration),
            (QuitGestureTiming.doublePressOptions, QuitGestureTiming.defaultDoublePressInterval),
        ] {
            let values = options.map(\.value)
            XCTAssertEqual(Set(values).count, values.count)
            XCTAssertTrue(values.allSatisfy { $0.isFinite && $0 > 0 })
            XCTAssertTrue(values.contains(defaultValue))
            XCTAssertTrue(options.allSatisfy {
                !$0.localizationKey.isEmpty && !$0.fallbackLabel.isEmpty
            })
        }
    }

    // `tools/check-localisation.sh` is what proves every key has a string in every
    // .lproj. This only pins the naming rule the script and the .strings files share,
    // so a new option cannot be added under an ad-hoc key that the script then reports
    // as missing.
    func testGestureTimingKeysFollowTheDurationNamingRule() {
        for option in QuitGestureTiming.holdOptions + QuitGestureTiming.doublePressOptions {
            XCTAssertEqual(option.localizationKey, "duration.\(option.value)_seconds")
        }
    }

    private func makeThrowawayDefaults(
        _ body: (UserDefaults) -> Void
    ) {
        let suiteName = "QuitGestureTimingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    func testGestureTimingRepairsNonsensePersistedValues() {
        makeThrowawayDefaults { defaults in
            defaults.set(-1.0, forKey: QuitGestureTiming.DefaultsKey.holdDuration)
            defaults.set(Double.nan, forKey: QuitGestureTiming.DefaultsKey.doublePressInterval)

            XCTAssertEqual(
                QuitGestureTiming.resolveHoldDuration(from: defaults),
                QuitGestureTiming.defaultHoldDuration
            )
            XCTAssertEqual(
                QuitGestureTiming.resolveDoublePressInterval(from: defaults),
                QuitGestureTiming.defaultDoublePressInterval
            )
            XCTAssertEqual(
                defaults.double(forKey: QuitGestureTiming.DefaultsKey.holdDuration),
                QuitGestureTiming.defaultHoldDuration
            )
            XCTAssertEqual(
                defaults.double(forKey: QuitGestureTiming.DefaultsKey.doublePressInterval),
                QuitGestureTiming.defaultDoublePressInterval
            )
        }
    }

    // A stricter-than-supported setting is repaired towards the strictest option the
    // Settings picker can show, not back to the shipped default.
    func testGestureTimingRepairsUnsupportedValuesTowardsTheStricterOption() {
        makeThrowawayDefaults { defaults in
            defaults.set(1.9, forKey: QuitGestureTiming.DefaultsKey.holdDuration)
            defaults.set(0.35, forKey: QuitGestureTiming.DefaultsKey.doublePressInterval)

            XCTAssertEqual(QuitGestureTiming.resolveHoldDuration(from: defaults), 2.0)
            XCTAssertEqual(QuitGestureTiming.resolveDoublePressInterval(from: defaults), 0.3)
            XCTAssertEqual(
                defaults.double(forKey: QuitGestureTiming.DefaultsKey.holdDuration),
                2.0
            )
            XCTAssertEqual(
                defaults.double(forKey: QuitGestureTiming.DefaultsKey.doublePressInterval),
                0.3
            )
        }
    }

    // `defaults write <domain> holdDuration 1.5` stores a STRING unless the caller passes
    // `-float`, which is the mistake people actually make. Read the number they meant and
    // rewrite the entry as a number so the next reader does not have to parse it.
    func testGestureTimingRepairsTimingsStoredAsText() {
        makeThrowawayDefaults { defaults in
            defaults.set("1.5", forKey: QuitGestureTiming.DefaultsKey.holdDuration)
            defaults.set("0.9", forKey: QuitGestureTiming.DefaultsKey.doublePressInterval)

            XCTAssertEqual(QuitGestureTiming.resolveHoldDuration(from: defaults), 1.5)
            XCTAssertEqual(QuitGestureTiming.resolveDoublePressInterval(from: defaults), 0.75)
            XCTAssertNil(
                defaults.object(forKey: QuitGestureTiming.DefaultsKey.holdDuration) as? String
            )
            XCTAssertNil(
                defaults.object(
                    forKey: QuitGestureTiming.DefaultsKey.doublePressInterval
                ) as? String
            )
        }
    }

    // Present but holding nothing a duration can be read out of. There is nothing to snap
    // towards, so the entry is replaced instead of being silently ignored on every launch.
    func testGestureTimingRepairsUnreadablePersistedValues() {
        makeThrowawayDefaults { defaults in
            defaults.set(["soon": true], forKey: QuitGestureTiming.DefaultsKey.holdDuration)
            defaults.set("soon", forKey: QuitGestureTiming.DefaultsKey.doublePressInterval)

            XCTAssertEqual(
                QuitGestureTiming.resolveHoldDuration(from: defaults),
                QuitGestureTiming.defaultHoldDuration
            )
            XCTAssertEqual(
                QuitGestureTiming.resolveDoublePressInterval(from: defaults),
                QuitGestureTiming.defaultDoublePressInterval
            )
            XCTAssertEqual(
                defaults.double(forKey: QuitGestureTiming.DefaultsKey.holdDuration),
                QuitGestureTiming.defaultHoldDuration
            )
            XCTAssertEqual(
                defaults.double(forKey: QuitGestureTiming.DefaultsKey.doublePressInterval),
                QuitGestureTiming.defaultDoublePressInterval
            )
        }
    }

    func testGestureTimingLeavesSupportedPersistedValuesAlone() {
        makeThrowawayDefaults { defaults in
            defaults.set(1.5, forKey: QuitGestureTiming.DefaultsKey.holdDuration)
            defaults.set(0.75, forKey: QuitGestureTiming.DefaultsKey.doublePressInterval)

            XCTAssertEqual(QuitGestureTiming.resolveHoldDuration(from: defaults), 1.5)
            XCTAssertEqual(QuitGestureTiming.resolveDoublePressInterval(from: defaults), 0.75)
        }
    }

    func testGestureTimingDoesNotPersistDefaultsForMissingKeys() {
        makeThrowawayDefaults { defaults in
            XCTAssertEqual(
                QuitGestureTiming.resolveHoldDuration(from: defaults),
                QuitGestureTiming.defaultHoldDuration
            )
            XCTAssertEqual(
                QuitGestureTiming.resolveDoublePressInterval(from: defaults),
                QuitGestureTiming.defaultDoublePressInterval
            )
            XCTAssertNil(defaults.object(forKey: QuitGestureTiming.DefaultsKey.holdDuration))
            XCTAssertNil(defaults.object(forKey: QuitGestureTiming.DefaultsKey.doublePressInterval))
        }
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
