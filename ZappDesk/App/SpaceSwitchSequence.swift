import Foundation

/// Serializes gestures without blocking the event tap. A subsequent gesture is
/// sent only after WindowServer reports the expected intermediate desktop.
final class SpaceSwitchSequence {
    struct Snapshot: Equatable {
        let spaces: [UInt64]
        let current: UInt64
    }

    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let now: () -> TimeInterval
    private var generation = 0
    private var completion: (() -> Void)?
    private(set) var isRunning = false

    init(schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = {
        delay, action in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.schedule = schedule
        self.now = now
    }

    @discardableResult
    func start(target: UInt64, snapshot: @escaping () -> Snapshot?,
               post: @escaping (Int) -> Bool, confirmed: @escaping () -> Void,
               finished: @escaping () -> Void) -> Bool {
        guard !isRunning, let initial = snapshot(),
              let from = initial.spaces.firstIndex(of: initial.current),
              let to = initial.spaces.firstIndex(of: target), from != to else { return false }
        let direction = to > from ? 1 : -1
        let route = stride(from: from + direction, through: to, by: direction).map { initial.spaces[$0] }
        guard post(direction) else { return false }
        generation += 1
        let token = generation
        isRunning = true
        completion = finished
        waitForStep(route: route, index: 0, previous: initial.current,
                    order: initial.spaces, direction: direction, deadline: now() + 1.5,
                    token: token, snapshot: snapshot, post: post, confirmed: confirmed)
        return true
    }

    func cancel() {
        generation += 1
        isRunning = false
        let callback = completion
        completion = nil
        callback?()
    }

    private func waitForStep(route: [UInt64], index: Int, previous: UInt64,
                             order: [UInt64], direction: Int, deadline: TimeInterval,
                             token: Int, snapshot: @escaping () -> Snapshot?,
                             post: @escaping (Int) -> Bool, confirmed: @escaping () -> Void) {
        schedule(0.02) { [weak self] in
            guard let self, self.isRunning, self.generation == token else { return }
            guard let current = snapshot(), current.spaces == order else { self.cancel(); return }
            if current.current == route[index] {
                confirmed()
                guard self.isRunning, self.generation == token else { return }
                guard index + 1 < route.count else { self.cancel(); return }
                guard post(direction) else { self.cancel(); return }
                self.waitForStep(route: route, index: index + 1, previous: current.current,
                                 order: order, direction: direction, deadline: self.now() + 1.5,
                                 token: token, snapshot: snapshot, post: post, confirmed: confirmed)
            } else if current.current == previous, self.now() < deadline {
                self.waitForStep(route: route, index: index, previous: previous,
                                 order: order, direction: direction, deadline: deadline,
                                 token: token, snapshot: snapshot, post: post, confirmed: confirmed)
            } else {
                // Timeout, display removal, or navigation by another source: do not keep moving.
                self.cancel()
            }
        }
    }
}
