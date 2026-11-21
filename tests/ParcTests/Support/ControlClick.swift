import AppKit

extension NSControl {
    @MainActor func sendClick() {
        if overridesPerformClick { performClick(nil); return }
        guard isEnabled else { return }
        cell?.setNextState()
        sendAction(action, to: target)
    }

    private var overridesPerformClick: Bool {
        let selector = #selector(performClick(_:))
        let appKit = Bundle(for: NSControl.self)
        var ancestor: AnyClass = type(of: self)
        while Bundle(for: ancestor) != appKit, let next = class_getSuperclass(ancestor) { ancestor = next }
        return class_getMethodImplementation(type(of: self), selector) != class_getMethodImplementation(ancestor, selector)
    }
}
