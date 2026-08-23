import XCTest
@testable import QuitProtectCore

final class EventTapLifecycleControllerTests: XCTestCase {
    private final class Resource {
        let id: Int
        var isValid = true
        var isEnabled = false
        var enableSucceeds = true

        init(id: Int) {
            self.id = id
        }
    }

    private final class Harness {
        var nextID = 0
        var creationSucceeds = true
        var newResourceEnableSucceeds = true
        var created: [Resource] = []
        var destroyed: [Int] = []

        lazy var controller = EventTapLifecycleController<Resource>(
            create: { [unowned self] in
                guard creationSucceeds else { return nil }
                nextID += 1
                let resource = Resource(id: nextID)
                resource.enableSucceeds = newResourceEnableSucceeds
                created.append(resource)
                return resource
            },
            isValid: { $0.isValid },
            isEnabled: { $0.isEnabled },
            enable: {
                if $0.enableSucceeds { $0.isEnabled = true }
            },
            destroy: { [unowned self] in
                destroyed.append($0.id)
                $0.isEnabled = false
                $0.isValid = false
            }
        )
    }

    func testStartOwnsOneHealthyResourceAndIsIdempotent() {
        let harness = Harness()

        XCTAssertTrue(harness.controller.start())
        XCTAssertTrue(harness.controller.start())

        XCTAssertEqual(harness.created.map(\.id), [1])
        XCTAssertEqual(harness.destroyed, [])
        XCTAssertTrue(harness.controller.isProtecting)
    }

    func testStopDestroysTheOwnedResourceExactlyOnce() {
        let harness = Harness()
        XCTAssertTrue(harness.controller.start())

        harness.controller.stop()
        harness.controller.stop()

        XCTAssertEqual(harness.destroyed, [1])
        XCTAssertFalse(harness.controller.isProtecting)
    }

    func testFailedInitialEnableDestroysTheCandidate() {
        let harness = Harness()
        harness.newResourceEnableSucceeds = false

        XCTAssertFalse(harness.controller.start())

        XCTAssertEqual(harness.created.map(\.id), [1])
        XCTAssertEqual(harness.destroyed, [1])
        XCTAssertFalse(harness.controller.isProtecting)
    }

    func testDisableReenablesAStillValidResourceWithoutRebuilding() {
        let harness = Harness()
        XCTAssertTrue(harness.controller.start())
        harness.created[0].isEnabled = false

        XCTAssertTrue(harness.controller.recoverAfterDisable())

        XCTAssertEqual(harness.created.map(\.id), [1])
        XCTAssertEqual(harness.destroyed, [])
        XCTAssertTrue(harness.controller.isProtecting)
    }

    func testDisableRebuildsAnInvalidResource() {
        let harness = Harness()
        XCTAssertTrue(harness.controller.start())
        harness.created[0].isValid = false
        harness.created[0].isEnabled = false

        XCTAssertTrue(harness.controller.recoverAfterDisable())

        XCTAssertEqual(harness.created.map(\.id), [1, 2])
        XCTAssertEqual(harness.destroyed, [1])
        XCTAssertTrue(harness.controller.isProtecting)
    }

    func testFailedReenableRebuildsTheResource() {
        let harness = Harness()
        XCTAssertTrue(harness.controller.start())
        harness.created[0].isEnabled = false
        harness.created[0].enableSucceeds = false

        XCTAssertTrue(harness.controller.recoverAfterDisable())

        XCTAssertEqual(harness.created.map(\.id), [1, 2])
        XCTAssertEqual(harness.destroyed, [1])
        XCTAssertTrue(harness.controller.isProtecting)
    }

    func testFailedRebuildLeavesNoStaleResource() {
        let harness = Harness()
        XCTAssertTrue(harness.controller.start())
        harness.created[0].isValid = false
        harness.creationSucceeds = false

        XCTAssertFalse(harness.controller.recoverAfterDisable())

        XCTAssertEqual(harness.destroyed, [1])
        XCTAssertFalse(harness.controller.isProtecting)
    }

    func testRepeatedStartStopCyclesDestroyEveryResource() {
        let harness = Harness()

        for _ in 0..<100 {
            XCTAssertTrue(harness.controller.start())
            harness.controller.stop()
        }

        XCTAssertEqual(harness.created.count, 100)
        XCTAssertEqual(harness.destroyed, Array(1...100))
        XCTAssertFalse(harness.controller.isProtecting)
    }
}
