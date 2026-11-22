import AppKit
import Combine
import ParcCore

open class LayoutView: NSView, Sendable {
    package var onLayout: (() -> Void)?
    public override var isFlipped: Bool { true }
    open override func layout() { super.layout(); onLayout?() }
}
