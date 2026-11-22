import AppKit
import QuartzCore
import ParcKit
import ParcSidebar

@MainActor protocol ExtensionPopupActivityDrawing: NSView {
    var activityFill: CGFloat { get set }
    var glyphLift: CGFloat { get set }
}

extension ExtensionActionButton: ExtensionPopupActivityDrawing {}
extension ActionButton: ExtensionPopupActivityDrawing {}
extension BrowserToolbarActionButton: ExtensionPopupActivityDrawing {}
extension SidebarRowActionButton: ExtensionPopupActivityDrawing {}

@MainActor final class ExtensionPopupActivityIndicator {
    private(set) weak var view: (any ExtensionPopupActivityDrawing)?
    private(set) var phase: ExtensionPopupActivityPhase?
    private var motion = ExtensionPopupActivityMotion()
    private let frames = ViewDisplayFrameDriver()
    var isIdle: Bool { phase == nil && !frames.isRunning }

    init(view: any ExtensionPopupActivityDrawing) { self.view = view }

    func show(_ next: ExtensionPopupActivityPhase?) {
        guard next != phase, let view else { return }
        phase = next
        motion.show(next, at: CACurrentMediaTime(), reduceMotion: Self.reduceMotion)
        view.setAccessibilityExpanded(next != nil)
        (view as? NSControl)?.cell?.setAccessibilityExpanded(next != nil)
        if step() { frames.start(in: view) { [weak self] in self?.step() ?? false } }
    }

    private func step() -> Bool {
        guard let view else { return false }
        let frame = motion.frame(at: CACurrentMediaTime(), reduceMotion: Self.reduceMotion)
        if view.activityFill != frame.fill { view.activityFill = frame.fill }
        if view.glyphLift != frame.lift { view.glyphLift = frame.lift }
        return !frame.finished
    }

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
