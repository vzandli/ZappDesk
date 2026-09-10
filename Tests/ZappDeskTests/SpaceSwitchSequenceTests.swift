import XCTest
@testable import ZappDesk

final class SpaceSwitchSequenceTests: XCTestCase {
    private var callbacks: [() -> Void] = []
    private var time: TimeInterval = 0
    private var snapshot: SpaceSwitchSequence.Snapshot? = .init(spaces: [1, 2, 3, 4], current: 1)
    private var posted: [Int] = []
    private var confirmed = 0
    private var finished = 0
    private var mayPost = true
    private lazy var sequence = SpaceSwitchSequence(schedule: { [unowned self] _, action in
        callbacks.append(action)
    }, now: { [unowned self] in time })

    private func start(_ target: UInt64 = 3) -> Bool {
        sequence.start(target: target, snapshot: { self.snapshot }, post: {
            self.posted.append($0)
            return self.mayPost
        }, confirmed: { self.confirmed += 1 }, finished: { self.finished += 1 })
    }

    private func tick(current: UInt64? = nil, advance: TimeInterval = 0.02) {
        if let current { snapshot = .init(spaces: snapshot!.spaces, current: current) }
        time += advance
        XCTAssertFalse(callbacks.isEmpty)
        if !callbacks.isEmpty { callbacks.removeFirst()() }
    }

    func testWaitsForEachDesktopAndCountsOnlyConfirmedTransitions() {
        XCTAssertTrue(start())
        XCTAssertEqual(posted, [1])
        tick()
        XCTAssertEqual(posted, [1])
        XCTAssertEqual(confirmed, 0)
        tick(current: 2)
        XCTAssertEqual(posted, [1, 1])
        XCTAssertEqual(confirmed, 1)
        tick(current: 3)
        XCTAssertEqual(confirmed, 2)
        XCTAssertEqual(finished, 1)
        XCTAssertFalse(sequence.isRunning)
    }

    func testInitialFailureDeclinesWithoutSchedulingOrCounting() {
        mayPost = false
        XCTAssertFalse(start())
        XCTAssertTrue(callbacks.isEmpty)
        XCTAssertEqual(confirmed, 0)
        XCTAssertFalse(sequence.isRunning)
    }

    func testLaterFailureStopsAfterConfirmedStep() {
        XCTAssertTrue(start())
        mayPost = false
        tick(current: 2)
        XCTAssertEqual(confirmed, 1)
        XCTAssertEqual(finished, 1)
        XCTAssertFalse(sequence.isRunning)
    }

    func testTimeoutDoesNotPostMoreGesturesOrCount() {
        XCTAssertTrue(start())
        tick(advance: 2)
        XCTAssertEqual(posted, [1])
        XCTAssertEqual(confirmed, 0)
        XCTAssertEqual(finished, 1)
    }

    func testUnexpectedNavigationStopsSequence() {
        XCTAssertTrue(start())
        tick(current: 4)
        XCTAssertEqual(posted, [1])
        XCTAssertEqual(confirmed, 0)
        XCTAssertFalse(sequence.isRunning)
    }

    func testDisplayRemovalStopsAndCleansUp() {
        XCTAssertTrue(start())
        snapshot = nil
        tick()
        XCTAssertEqual(finished, 1)
        XCTAssertFalse(sequence.isRunning)
    }

    func testDesktopReorderingStopsSequence() {
        XCTAssertTrue(start())
        snapshot = .init(spaces: [1, 3, 2, 4], current: 2)
        tick()
        XCTAssertEqual(confirmed, 0)
        XCTAssertEqual(posted, [1])
        XCTAssertFalse(sequence.isRunning)
    }

    func testCancellationInvalidatesOldCallbacksAfterRestart() {
        XCTAssertTrue(start())
        sequence.cancel()
        XCTAssertEqual(finished, 1)
        XCTAssertTrue(start(2))
        tick(current: 2) // callback from cancelled request
        XCTAssertEqual(confirmed, 0)
        XCTAssertTrue(sequence.isRunning)
        tick()
        XCTAssertEqual(confirmed, 1)
        XCTAssertEqual(finished, 2)
    }

    func testBusyRequestDoesNotOverlapGestures() {
        XCTAssertTrue(start())
        XCTAssertFalse(start(4))
        XCTAssertEqual(posted, [1])
    }

    func testLeftwardRoute() {
        snapshot = .init(spaces: [1, 2, 3, 4], current: 3)
        XCTAssertTrue(start(1))
        tick(current: 2)
        tick(current: 1)
        XCTAssertEqual(posted, [-1, -1])
        XCTAssertEqual(confirmed, 2)
    }

    func testUnknownAndCurrentDestinationsDecline() {
        XCTAssertFalse(start(99))
        XCTAssertFalse(start(1))
        XCTAssertTrue(posted.isEmpty)
    }
}
