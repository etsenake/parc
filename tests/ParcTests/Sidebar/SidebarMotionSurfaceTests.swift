import AppKit
import QuartzCore
import Testing
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SidebarMotionSurfaceTests {
    final class ToolbarHost: NSView {
        let lights = NSView()
        let toggle = NSView()
        override var isFlipped: Bool { true }
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; addSubview(lights); addSubview(toggle) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func layout() {
            super.layout()
            let bar = SidebarChromeLayout.toolbar(width: bounds.width, windowButtons: WindowStandardButtons.stackSize, showsNavigation: true)
            lights.frame = bar.windowButtons ?? .zero; toggle.frame = bar.toggle ?? .zero
        }
    }

    final class CountedLabel: NSTextField {
        var sizeChanges = 0
        override func setFrameSize(_ newSize: NSSize) {
            if frame.size != newSize { sizeChanges += 1 }
            super.setFrameSize(newSize)
        }
    }

    final class FlushCountingRoot: NSView {
        var zeroDurationLayouts = 0
        override func layoutSubtreeIfNeeded() {
            let context = NSAnimationContext.current
            if context.duration == 0, !context.allowsImplicitAnimation { zeroDurationLayouts += 1 }
            super.layoutSubtreeIfNeeded()
        }
    }

    private func host<Root: NSView>(_ root: Root) -> NSWindow {
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        root.wantsLayer = true
        window.contentView = root
        return window
    }

    @MainActor final class HeaderStage {
        let completions = SidebarMotionCompletions()
        lazy var motion = SidebarMotionController(completions: completions)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let container = NSView(frame: NSRect(x: -228, y: 5, width: 228, height: 690))
        let toolbar: ToolbarHost
        let window: NSWindow
        var finished: [String] = []
        let toggleX = 13 + WindowStandardButtons.stackSize.width + 4

        init() {
            window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            root.wantsLayer = true; window.contentView = root
            container.wantsLayer = true
            toolbar = ToolbarHost(frame: container.bounds)
            container.addSubview(toolbar); root.addSubview(container)
            root.layoutSubtreeIfNeeded(); CATransaction.flush()
        }

        func reveal() {
            motion.animate(layoutRoot: root, views: [container], style: .floating, changes: { self.container.frame.origin.x = 5 },
                           completion: { self.finished.append("reveal") })
        }

        func lock() {
            motion.animate(layoutRoot: root, views: [container], style: .anchored, flushesPreviousLayout: false, changes: {
                self.container.frame = NSRect(x: 0, y: 0, width: 228, height: 700)
                self.toolbar.frame = self.container.bounds
            }, completion: { self.finished.append("lock") })
        }
    }

    @Test func theLightsLeadTheHeaderAndTheToggleFollowsFourPointsAfterThem() {
        let s = HeaderStage()
        #expect(s.toolbar.lights.frame == NSRect(origin: NSPoint(x: 13, y: 17), size: WindowStandardButtons.stackSize))
        #expect(s.toolbar.toggle.frame.minX == s.toggleX)
    }

    @Test func aFloatingRevealSlidesTheSurfaceWithTheHeaderRidingIt() {
        let s = HeaderStage()
        s.reveal()
        #expect(sidebarMotionAnimation(s.toolbar.toggle, "position") == nil && sidebarMotionAnimation(s.toolbar.lights, "position") == nil)
        #expect(s.container.layer!.animation(forKey: "position") is CASpringAnimation)
        s.completions.finishAll()
        #expect(s.container.frame.minX + s.toolbar.lights.frame.minX == 18)
        #expect(s.container.frame.minX + s.toolbar.toggle.frame.minX == 5 + s.toggleX)
    }

    @Test func lockingCarriesTheHeaderOnTheContainersAnchoredGroup() {
        let s = HeaderStage()
        s.reveal(); s.completions.finishAll()
        s.lock()
        #expect(s.toolbar.toggle.frame.minX == s.toggleX && s.toolbar.lights.frame.minX == 13)
        #expect(sidebarMotionAnimation(s.container, "position")?.duration == 0.08)
        #expect(sidebarMotionAnimation(s.toolbar.toggle, "position") == nil && sidebarMotionAnimation(s.toolbar.lights, "position") == nil)
        s.completions.finishAll()
        #expect(s.finished == ["reveal", "lock"])
        #expect(!s.toolbar.needsLayout && s.container.frame.minX + s.toolbar.toggle.frame.minX == s.toggleX)
    }

    @Test func appKitsDefaultRedrawPoliciesDifferByViewKind() {
        let label = NSTextField(labelWithString: "Parc")
        let button = NSButton(title: "Capture", target: nil, action: nil)
        #expect(label.layerContentsRedrawPolicy == .duringViewResize)
        #expect(button.layerContentsRedrawPolicy != .duringViewResize)
    }

    @Test func pinningDrawnContentSetsItsPolicyPlacementAndClip() {
        let label = NSTextField(labelWithString: "Parc"), button = NSButton(title: "Capture", target: nil, action: nil)
        let bar = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 300, height: 2))
        SidebarMotionController.pinDrawnContent(label, to: .center)
        SidebarMotionController.pinDrawnContent(button, to: .left)
        SidebarMotionController.pinDrawnContent(bar, to: .left, clips: true)
        #expect(label.layerContentsRedrawPolicy == .beforeViewResize && label.layerContentsPlacement == .center)
        #expect(button.layerContentsPlacement == .left)
        #expect(bar.layer?.masksToBounds == true)
    }

    @MainActor final class DrawnStage {
        let completions = SidebarMotionCompletions()
        lazy var motion = SidebarMotionController(completions: completions)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
        let window: NSWindow
        let ticking = CountedLabel(labelWithString: "Parc"), pinned = CountedLabel(labelWithString: "Parc")
        let hiddenHost = NSView(frame: NSRect(x: 0, y: 320, width: 300, height: 30))
        let hidden = CountedLabel(labelWithString: "Hidden")
        let stretched = NSButton(title: "Capture", target: nil, action: nil), anchored = NSButton(title: "Capture", target: nil, action: nil)
        let bar = NSProgressIndicator(frame: NSRect(x: 0, y: 280, width: 300, height: 2))
        var finished = false

        init() {
            window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            root.wantsLayer = true; window.contentView = root
            pane.wantsLayer = true; root.addSubview(pane)
            for (field, y) in [(ticking, 100.0), (pinned, 150.0)] {
                field.alignment = .center; field.frame = NSRect(x: 0, y: y, width: 300, height: 40); pane.addSubview(field)
            }
            hiddenHost.isHidden = true; pane.addSubview(hiddenHost)
            hidden.frame = hiddenHost.bounds; hiddenHost.addSubview(hidden)
            for (index, button) in [stretched, anchored].enumerated() {
                button.isBordered = false; button.frame = NSRect(x: 0, y: 200 + CGFloat(index) * 40, width: 300, height: 30); pane.addSubview(button)
            }
            bar.style = .bar; bar.isIndeterminate = true; pane.addSubview(bar)
            SidebarMotionController.pinDrawnContent(pinned, to: .center)
            SidebarMotionController.pinDrawnContent(anchored, to: .left)
            SidebarMotionController.pinDrawnContent(bar, to: .left, clips: true)
            root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
            ticking.sizeChanges = 0; pinned.sizeChanges = 0; hidden.sizeChanges = 0
        }

        func widen() {
            motion.animate(layoutRoot: root, views: [pane], style: .anchored, changes: {
                for view in [self.ticking, self.pinned, self.stretched, self.anchored, self.bar, self.hidden] as [NSView] { view.frame.size.width = 600 }
            }, completion: { self.finished = true })
        }
    }

    @Test func aDefaultDrawingViewGetsNoCoreAnimationGeometry() {
        let s = DrawnStage()
        s.widen()
        #expect(sidebarMotionAnimation(s.ticking, "bounds") == nil)
    }

    @Test func pinnedViewsAnimateInTheGroupWithoutScalingTheirContent() {
        let s = DrawnStage()
        s.widen()
        #expect(sidebarMotionAnimation(s.pinned, "bounds")?.duration == 0.08 && s.pinned.layer?.contentsGravity == .center)
        #expect(sidebarMotionAnimation(s.anchored, "bounds")?.duration == 0.08 && s.anchored.layer?.contentsGravity == .left)
        #expect(sidebarMotionAnimation(s.bar, "bounds")?.duration == 0.08)
    }

    @Test func aDefaultButtonScalesItsContentsInTheGroup() {
        let s = DrawnStage()
        s.widen()
        #expect(sidebarMotionAnimation(s.stretched, "bounds") != nil && s.stretched.layer?.contentsGravity == .resize)
    }

    @Test func pinnedAndHiddenLabelsAreSizedOnceAndHiddenKeepsItsPolicy() {
        let s = DrawnStage()
        s.widen()
        s.completions.finishAll()
        #expect(s.pinned.sizeChanges == 1)
        #expect(s.hidden.sizeChanges == 1 && s.hidden.layerContentsRedrawPolicy == .duringViewResize)
        #expect(s.finished && sidebarMotionAnimation(s.pinned, "bounds") == nil)
    }

    @MainActor final class FlushStage {
        let root = FlushCountingRoot(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let sidebar = NSView(frame: NSRect(x: -200, y: 0, width: 200, height: 300))
        let window: NSWindow
        init() {
            window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            root.wantsLayer = true; sidebar.wantsLayer = true
            root.addSubview(sidebar); window.contentView = root
            root.layoutSubtreeIfNeeded(); root.displayIfNeeded(); CATransaction.flush()
        }
    }

    @Test func aCleanLaidOutRootNeedsNoRevealFlush() {
        #expect(!SidebarMotionController.shouldFlushPreviousLayout(of: FlushStage().root))
    }

    @Test func aDirtyLayoutNeedsTheRevealFlushUntilItIsLaidOut() {
        let s = FlushStage()
        s.root.needsLayout = true
        #expect(SidebarMotionController.shouldFlushPreviousLayout(of: s.root))
        s.root.layoutSubtreeIfNeeded(); CATransaction.flush()
        #expect(!SidebarMotionController.shouldFlushPreviousLayout(of: s.root))
    }

    @Test func anOriginOnlyMoveNeedsTheRevealFlushUntilItIsCommitted() throws {
        let s = FlushStage()
        s.sidebar.layer?.removeAllAnimations(); CATransaction.flush()
        let old = try #require(s.sidebar.layer?.presentation()?.position)
        s.sidebar.frame.origin.x += 40
        #expect(!s.root.needsLayout && !s.sidebar.needsLayout)
        #expect(s.sidebar.layer!.position != old && s.sidebar.layer!.presentation()!.position == old)
        #expect(SidebarMotionController.shouldFlushPreviousLayout(of: s.root))
        CATransaction.flush()
        #expect(!SidebarMotionController.shouldFlushPreviousLayout(of: s.root))
    }

    @Test(arguments: [false, true])
    func aRevealRunsTheZeroDurationLayoutOnlyWhenTheRootIsDirty(dirty: Bool) {
        let s = FlushStage()
        let completions = SidebarMotionCompletions()
        let motion = SidebarMotionController(completions: completions)
        if dirty { s.root.needsLayout = true }
        s.root.zeroDurationLayouts = 0
        motion.animate(layoutRoot: s.root, views: [s.sidebar], style: .anchored, flushesPreviousLayout: true,
                       changes: { s.sidebar.frame.origin.x = 0 }, completion: {})
        #expect(s.root.zeroDurationLayouts == (dirty ? 1 : 0))
        motion.cancel()
    }
}
