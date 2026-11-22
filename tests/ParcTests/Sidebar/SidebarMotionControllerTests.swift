import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcSidebar

@MainActor
struct SidebarMotionControllerTests {
    final class CountedView: NSView {
        var sizeChanges = 0
        override func setFrameSize(_ newSize: NSSize) {
            if frame.size != newSize { sizeChanges += 1 }
            super.setFrameSize(newSize)
        }
    }

    @MainActor final class Stage {
        let completions = SidebarMotionCompletions()
        let motion: SidebarMotionController
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
        let page = CountedView(frame: NSRect(x: 228, y: 9, width: 763, height: 682))
        let pane: CountedView
        let editor = NSTextField(frame: NSRect(x: 12, y: 12, width: 120, height: 24))
        let unrelated: CAAnimation
        var finished: [String] = []
        let responder: NSResponder?

        init() {
            motion = SidebarMotionController(completions: completions)
            pane = CountedView(frame: page.bounds)
            window.isReleasedWhenClosed = false
            root.wantsLayer = true
            root.layer?.speed = 0
            window.contentView = root
            for view in [sidebar, page, pane] as [NSView] { view.wantsLayer = true }
            root.addSubview(sidebar); root.addSubview(page); page.addSubview(pane); sidebar.addSubview(editor)
            window.makeFirstResponder(editor)
            root.layoutSubtreeIfNeeded(); CATransaction.flush()
            responder = window.firstResponder
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.5; animation.toValue = 1; animation.duration = 10
            pane.layer!.add(animation, forKey: "other.owner")
            unrelated = pane.layer!.animation(forKey: "other.owner")!
            page.sizeChanges = 0; pane.sizeChanges = 0
        }

        var views: [NSView] { [sidebar, page] }

        func layout(_ locked: Bool) {
            sidebar.frame.origin.x = locked ? 0 : -228
            page.frame = NSRect(x: locked ? 228 : 9, y: 9, width: locked ? 763 : 982, height: 682)
            pane.frame = page.bounds
        }

        func animate(_ locked: Bool, style: SidebarMotionController.Style = .anchored, _ name: String) {
            motion.animate(layoutRoot: root, views: views, style: style, changes: { layout(locked) }, completion: { self.finished.append(name) })
        }
    }

    @Test func anAnchoredGroupCommitsTheRealDestinationOnce() {
        let s = Stage()
        s.animate(false, "hide")
        #expect(s.motion.isAnimating)
        #expect(s.page.frame.minX == 9 && s.page.bounds.width == 982)
        #expect(s.pane.bounds.width == 982)
        #expect(s.page.sizeChanges == 1 && s.pane.sizeChanges == 1)
    }

    @Test func anAnchoredGroupAnimatesNestedGeometryOnItsOwnTiming() {
        let s = Stage()
        s.animate(false, "hide")
        #expect(sidebarMotionAnimation(s.page, "position") != nil)
        #expect(sidebarMotionAnimation(s.page, "bounds")?.duration == 0.08)
        #expect(sidebarMotionAnimation(s.pane, "bounds")?.duration == 0.08)
        #expect((sidebarMotionAnimation(s.pane, "bounds")?.fromValue as? NSValue)?.rectValue.width == 763)
    }

    @Test func aGroupKeepsUnrelatedAnimationsAndFieldEditorFocus() {
        let s = Stage()
        s.animate(false, "hide")
        #expect(s.pane.layer!.animation(forKey: "other.owner") === s.unrelated)
        #expect(s.window.firstResponder === s.responder)
    }

    @Test func aReversalStartsFromThePresentationGeometryAndCommitsOnce() throws {
        let s = Stage()
        s.animate(false, "hide")
        CATransaction.flush()
        let visible = try #require(s.page.layer?.presentation()?.position)
        s.animate(true, "show")
        let from = try #require((sidebarMotionAnimation(s.page, "position")?.fromValue as? NSValue)?.pointValue)
        #expect(abs(from.x - visible.x) < 20)
        #expect(s.page.frame.minX == 228 && s.pane.bounds.width == 763)
        #expect(s.page.sizeChanges == 2 && s.pane.sizeChanges == 2)
        #expect(s.window.firstResponder === s.responder)
    }

    @Test func onlyTheNewestGenerationCompletesAndReleasesItsGeometry() {
        let s = Stage()
        s.animate(false, "hide")
        s.animate(true, "show")
        s.completions.finishAll()
        #expect(s.finished == ["show"])
        #expect(!s.motion.isAnimating)
        #expect(sidebarMotionAnimation(s.page, "position") == nil && sidebarMotionAnimation(s.pane, "bounds") == nil)
    }

    @Test func cancellingSettlesAndLeavesAnimationsItDoesNotOwn() {
        let s = Stage()
        s.animate(false, "obsolete")
        let replacement = CABasicAnimation(keyPath: "bounds")
        replacement.fromValue = NSValue(rect: s.pane.bounds); replacement.duration = 10
        s.pane.layer!.add(replacement, forKey: "bounds")
        let identity = s.pane.layer!.animation(forKey: "bounds")
        s.motion.cancel()
        #expect(!s.motion.isAnimating)
        #expect(s.pane.layer!.animation(forKey: "bounds") === identity)
        #expect(s.pane.layer!.animation(forKey: "other.owner") === s.unrelated)
        #expect(sidebarMotionAnimation(s.page, "position") == nil)
        #expect(s.page.frame.minX == 9)
    }

    @Test func aCancelledGroupNeverCompletes() {
        let s = Stage()
        s.animate(false, "obsolete")
        s.motion.cancel()
        s.completions.finishAll()
        #expect(s.finished.isEmpty)
    }

    @Test func aFloatingGroupSpringsAndRestoresTheViewsAnimations() throws {
        let s = Stage()
        s.sidebar.frame.origin.x = -228; s.root.layoutSubtreeIfNeeded(); CATransaction.flush()
        let custom = CABasicAnimation(keyPath: "opacity")
        s.sidebar.animations = ["alphaValue": custom]
        s.motion.animate(layoutRoot: s.root, views: s.views, style: .floating, changes: { s.sidebar.frame.origin.x = 0 }, completion: {})
        #expect(s.sidebar.animations.count == 1 && s.sidebar.animations["alphaValue"] as? CABasicAnimation === custom)
        let spring = try #require(s.sidebar.layer!.animation(forKey: "position") as? CASpringAnimation)
        #expect(abs(spring.stiffness - pow(2 * Double.pi / 0.18, 2)) < 0.001)
        #expect(abs(spring.damping - 2 * 0.8 * 2 * Double.pi / 0.18) < 0.001)
        #expect(s.page.sizeChanges == 0 && s.pane.sizeChanges == 0)
        #expect(s.window.firstResponder === s.responder)
    }

    @Test func cancellingAFloatingGroupRemovesOnlyItsSpring() {
        let s = Stage()
        s.sidebar.frame.origin.x = -228; s.root.layoutSubtreeIfNeeded(); CATransaction.flush()
        s.sidebar.animations = ["alphaValue": CABasicAnimation(keyPath: "opacity")]
        s.motion.animate(layoutRoot: s.root, views: s.views, style: .floating, changes: { s.sidebar.frame.origin.x = 0 }, completion: {})
        s.motion.cancel()
        #expect(s.sidebar.layer!.animation(forKey: "position") == nil)
        #expect(s.sidebar.animations.count == 1)
    }

    @Test func aSettleWithoutMotionKeepsItsLayoutAndDropsThePendingCompletion() {
        let s = Stage()
        s.animate(false, "hide")
        s.motion.cancel()
        s.layout(true); s.root.layoutSubtreeIfNeeded()
        s.completions.finishAll()
        #expect(s.finished.isEmpty)
        #expect(s.page.frame.minX == 228 && s.pane.bounds.width == 763)
        #expect(s.window.firstResponder === s.responder)
    }

    @Test func repeatedRequestsLandOnTheLastAndOnlyItCompletes() {
        let s = Stage()
        for index in 0..<6 { s.animate(index.isMultiple(of: 2), "repeat-\(index)") }
        #expect(s.motion.isAnimating)
        #expect(s.page.frame.minX == 9 && s.pane.bounds.width == 982)
        s.completions.finishAll()
        #expect(s.finished == ["repeat-5"])
        #expect(!s.motion.isAnimating && sidebarMotionAnimation(s.pane, "bounds") == nil)
        #expect(s.window.firstResponder === s.responder)
    }

    @Test func theLibraryWidthGroupMovesThePageForATwoTenthsSecondCubic() {
        let s = Stage()
        s.layout(false); s.root.layoutSubtreeIfNeeded(); CATransaction.flush()
        s.animate(true, style: .libraryWidth, "library")
        #expect(sidebarMotionAnimation(s.page, "position")?.duration == 0.2)
        #expect(sidebarMotionAnimation(s.page, "bounds")?.duration == 0.2)
        #expect(sidebarMotionAnimation(s.pane, "bounds")?.duration == 0.2)
        #expect(sidebarMotionControlPoints(sidebarMotionAnimation(s.page, "bounds")?.timingFunction) == [0.25, 0.46, 0.45, 0.94])
    }

    @Test func settlingTheLibraryWidthGroupKeepsTheSettlingLayoutAndNeverCompletes() {
        let s = Stage()
        s.layout(false); s.root.layoutSubtreeIfNeeded(); CATransaction.flush()
        s.animate(true, style: .libraryWidth, "library")
        s.motion.cancel(); s.layout(false); s.root.layoutSubtreeIfNeeded()
        #expect(!s.motion.isAnimating)
        #expect(sidebarMotionAnimation(s.page, "position") == nil && sidebarMotionAnimation(s.page, "bounds") == nil
                && sidebarMotionAnimation(s.pane, "bounds") == nil)
        #expect(s.page.frame.minX == 9 && s.pane.bounds.width == 982)
        s.completions.finishAll()
        #expect(!s.finished.contains("library"))
    }
}
