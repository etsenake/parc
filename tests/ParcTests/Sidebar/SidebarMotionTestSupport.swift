import AppKit
import QuartzCore
@testable import Parc

final class SidebarMotionCompletions {
    private var pending: [() -> Void] = []
    var count: Int { pending.count }

    func run(_ changes: (NSAnimationContext) -> Void, _ completion: @escaping @Sendable () -> Void) {
        NSAnimationContext.runAnimationGroup(changes)
        pending.append(completion)
    }

    func finishAll() {
        let due = pending
        pending.removeAll()
        for completion in due { completion() }
    }
}

extension SidebarMotionController {
    convenience init(completions: SidebarMotionCompletions) {
        self.init(runGroup: { completions.run($0, $1) })
    }
}

@MainActor
func sidebarMotionAnimation(_ view: NSView, _ key: String) -> CABasicAnimation? {
    view.layer?.animation(forKey: key) as? CABasicAnimation
}

func sidebarMotionControlPoints(_ timing: CAMediaTimingFunction?) -> [Float] {
    guard let timing else { return [] }
    var first: [Float] = [0, 0], second: [Float] = [0, 0]
    timing.getControlPoint(at: 1, values: &first)
    timing.getControlPoint(at: 2, values: &second)
    return first + second
}
