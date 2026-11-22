import AppKit
import QuartzCore
import ParcLibrary

@MainActor
package final class SidebarMotionController {
    package enum Style { case anchored, floating, libraryWidth }

    private struct OwnedAnimation {
        let layer: CALayer
        let key: String
        let animation: CAAnimation

        var isCurrent: Bool { layer.animation(forKey: key) === animation }
        func removeIfCurrent() {
            if isCurrent { layer.removeAnimation(forKey: key) }
        }
    }

    private static let geometryKeys = ["position", "bounds", "cornerRadius"]
    private var generation: UInt64 = 0
    private var owned: [OwnedAnimation] = []
    package private(set) var isAnimating = false
    package typealias AnimationGroup = (_ changes: (NSAnimationContext) -> Void, _ completion: @escaping @Sendable () -> Void) -> Void
    private let runGroup: AnimationGroup

    package init(runGroup: @escaping AnimationGroup = { NSAnimationContext.runAnimationGroup($0, completionHandler: $1) }) {
        self.runGroup = runGroup
    }

    package func animate(layoutRoot: NSView, views: [NSView], style: Style, flushesPreviousLayout: Bool = true,
                 changes: () -> Void, completion: @escaping () -> Void) {
        generation &+= 1
        let token = generation
        isAnimating = true
        if flushesPreviousLayout, Self.shouldFlushPreviousLayout(of: layoutRoot) {
            if Self.subtreeNeedsLayout(layoutRoot) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    layoutRoot.layoutSubtreeIfNeeded()
                }
            }
            CATransaction.flush()
        }
        var hidden: [NSView] = []
        let before = geometryAnimations(in: views) { hidden.append($0) }
        for view in hidden { view.layerContentsRedrawPolicy = .beforeViewResize }
        defer { for view in hidden { view.layerContentsRedrawPolicy = .duringViewResize } }

        let saved = views.map { ($0, $0.animations) }
        if style == .floating {
            for view in views {
                var animations = view.animations
                animations["frameOrigin"] = Self.floatingAnimation()
                animations["frameSize"] = Self.floatingAnimation()
                view.animations = animations
            }
        }
        defer { if style == .floating { for (view, animations) in saved { view.animations = animations } } }

        runGroup({ context in
            switch style {
            case .anchored: context.duration = 0.08
            case .libraryWidth: context.duration = 0.2
            case .floating: context.duration = Self.floatingAnimation().settlingDuration
            }
            if style != .floating {
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            }
            context.allowsImplicitAnimation = true
            changes()
            layoutRoot.layoutSubtreeIfNeeded()

            owned = owned.filter(\.isCurrent)
            for item in geometryAnimations(in: views) {
                if !before.contains(where: { $0.layer === item.layer && $0.key == item.key && $0.animation === item.animation }),
                   !owned.contains(where: { $0.layer === item.layer && $0.key == item.key && $0.animation === item.animation }) {
                    owned.append(item)
                }
            }
        }, { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.cancel()
                completion()
            }
        })
    }

    package func cancel() {
        generation &+= 1
        isAnimating = false
        let animations = owned
        owned.removeAll()
        for item in animations { item.removeIfCurrent() }
    }

    package static func animatesLibraryWidth(in window: NSWindow?, layoutRoot: NSView,
                                     isOnScreen: @MainActor (NSWindow) -> Bool = { $0.isVisible && !$0.isMiniaturized },
                                     reducesMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) -> Bool {
        guard let window else { return false }
        return isOnScreen(window) && !layoutRoot.inLiveResize && !reducesMotion()
    }

    static func shouldFlushPreviousLayout(of layoutRoot: NSView) -> Bool {
        subtreeNeedsLayout(layoutRoot) || subtreeHasUncommittedGeometry(layoutRoot)
    }

    private static func subtreeNeedsLayout(_ root: NSView) -> Bool {
        if root.needsLayout || root.needsUpdateConstraints { return true }
        for child in root.subviews where subtreeNeedsLayout(child) { return true }
        return false
    }

    private static func subtreeHasUncommittedGeometry(_ root: NSView) -> Bool {
        if let layer = root.layer, let presentation = layer.presentation(),
           presentation.position != layer.position
            || presentation.bounds != layer.bounds
            || presentation.cornerRadius != layer.cornerRadius {
            return true
        }
        for child in root.subviews where subtreeHasUncommittedGeometry(child) { return true }
        return false
    }

    private func geometryAnimations(in roots: [NSView], hiddenRedrawing: ((NSView) -> Void)? = nil) -> [OwnedAnimation] {
        var seen = Set<ObjectIdentifier>()
        var result: [OwnedAnimation] = []
        func visit(_ view: NSView, hidden: Bool) {
            guard seen.insert(ObjectIdentifier(view)).inserted else { return }
            let hidden = hidden || view.isHidden
            if hidden, view.layerContentsRedrawPolicy == .duringViewResize { hiddenRedrawing?(view) }
            if let layer = view.layer {
                for key in Self.geometryKeys {
                    if let animation = layer.animation(forKey: key) {
                        result.append(OwnedAnimation(layer: layer, key: key, animation: animation))
                    }
                }
            }
            for child in view.subviews { visit(child, hidden: hidden) }
        }
        for root in roots { visit(root, hidden: root.isHiddenOrHasHiddenAncestor) }
        return result
    }

    package static func pinDrawnContent(_ view: NSView, to placement: NSView.LayerContentsPlacement, clips: Bool = false) {
        view.layerContentsRedrawPolicy = .beforeViewResize
        view.layerContentsPlacement = placement
        if clips { view.wantsLayer = true; view.layer?.masksToBounds = true }
    }

    package static func pinSurface(of container: NSView, except content: NSView) {
        for surface in container.subviews where surface !== content && !(surface is NSVisualEffectView) {
            pinDrawnContent(surface, to: .scaleAxesIndependently)
        }
    }

    private static func floatingAnimation() -> CASpringAnimation {
        let animation = CASpringAnimation()
        let response = 0.18, dampingRatio = 0.8
        let frequency = 2 * Double.pi / response
        animation.mass = 1
        animation.stiffness = frequency * frequency
        animation.damping = 2 * dampingRatio * frequency
        animation.duration = animation.settlingDuration
        return animation
    }
}

package enum SidebarPresentation {
    case locked, floating, hidden

    package func presents(inMotion: Bool) -> Bool { self != .hidden || inMotion }
}

package enum PendingSplitPaneSidebarRule {
    package static func holdsSidebar(pendingSplitPane: Bool, creatingSpace: Bool, popup: Bool, library: Bool) -> Bool {
        pendingSplitPane && !creatingSpace && !popup && !library
    }
    package static func presentation(for requested: SidebarPresentation, pendingPane: Bool) -> SidebarPresentation {
        requested == .hidden && pendingPane ? .floating : requested
    }
    package enum Refresh { case keep, float, applyHover }
    package static func refresh(_ presentation: SidebarPresentation, pendingPane: Bool, heldBefore: Bool) -> Refresh {
        if pendingPane { return presentation == .hidden ? .float : .keep }
        return heldBefore && presentation == .floating ? .applyHover : .keep
    }
}

package enum SidebarPresentationFrame {
    case locked, floating
    case hiding, hidden, revealing

    package init(_ presentation: SidebarPresentation, inMotion: Bool, floatingSurface: Bool, revealsAnchored: Bool) {
        switch presentation {
        case .locked: self = .locked
        case .floating: self = .floating
        case .hidden: self = revealsAnchored ? .revealing : inMotion && !floatingSurface ? .hiding : .hidden
        }
    }

    package func rect(width: CGFloat, in bounds: NSRect) -> NSRect {
        let locked = NSRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
        let floating = NSRect(x: bounds.minX + 5, y: bounds.minY + 5, width: width, height: max(0, bounds.height - 10))
        switch self {
        case .locked: return locked
        case .floating: return floating
        case .hiding: return locked.offsetBy(dx: -width - 10, dy: 0)
        case .hidden: return floating.offsetBy(dx: -width - 15, dy: 0)
        case .revealing: return locked.offsetBy(dx: -width, dy: 0)
        }
    }
}

package struct SidebarTransition {
    package let style: SidebarMotionController.Style
    package let keepsFloatingSurface: Bool
    package let docksFloatingSurface: Bool
    package let revealsAnchored: Bool
    package let flushesPreparation: Bool

    package init(from previous: SidebarPresentation, to next: SidebarPresentation) {
        style = previous == .locked || next == .locked ? .anchored : .floating
        keepsFloatingSurface = previous == .floating || next == .floating
        docksFloatingSurface = previous == .floating && next == .locked
        revealsAnchored = previous == .hidden && next == .locked
        flushesPreparation = previous == .hidden
    }
}

package struct SidebarChromeFrames {
    package static let pageInset: CGFloat = 10
    package let sidebar, library, popupChrome, pageHost, sidePanel: NSRect
    package let showsSidePanel: Bool

    package init(bounds: NSRect, sidebarWidth width: CGFloat, presentation: SidebarPresentation, placement: SidebarPresentationFrame,
         previewingHidden: Bool = false, fullscreen: Bool = false, library: Bool = false, libraryContentWidth: CGFloat = 0,
         popup: Bool = false, sidePanel: Bool = false, thickness: CGFloat = SidebarChromeFrames.pageInset) {
        var sidebar = placement.rect(width: width, in: bounds)
        if previewingHidden { sidebar.origin.x = -width }
        self.sidebar = sidebar
        let libraryWidth: CGFloat = !library || fullscreen ? 0
            : max(LibraryView.minimumWidth, min(bounds.width - 56, libraryContentWidth))
        self.library = NSRect(x: 0, y: 0, width: libraryWidth, height: bounds.height)
        let left: CGFloat = fullscreen ? 0 : libraryWidth > 0 ? libraryWidth
            : (!popup && presentation == .locked && !previewingHidden ? width : popup ? 8 : thickness)
        let inset: CGFloat = fullscreen ? 0 : popup ? Self.pageInset : thickness
        let popupHeight: CGFloat = popup && !fullscreen ? 47 : 0
        popupChrome = NSRect(x: 8, y: 0, width: max(0, bounds.width - 16), height: popupHeight)
        let panelRight = max(0, bounds.width - inset)
        let panelWidth = min(max(0, panelRight - left), min(360, max(240, bounds.width * 0.3)))
        showsSidePanel = sidePanel && !fullscreen
        let top = inset + popupHeight, height = max(0, bounds.height - 2 * inset - popupHeight)
        pageHost = NSRect(x: left, y: top, width: max(0, bounds.width - left - inset - (showsSidePanel ? panelWidth : 0)), height: height)
        self.sidePanel = NSRect(x: panelRight - panelWidth, y: top, width: panelWidth, height: height)
    }
}

package struct LayoutChromeGeometryFingerprint: Equatable {
    package var boundsWidth: CGFloat
    package var boundsHeight: CGFloat
    package var sidebarWidth: CGFloat
    package var presentation: SidebarPresentation
    package var motionVisible: Bool
    package var floatingSurface: Bool
    package var revealsAnchored: Bool
    package var previewingHidden: Bool
    package var fullscreen: Bool
    package var library: Bool
    package var libraryContentWidth: CGFloat
    package var popup: Bool
    package var sidePanel: Bool
    package var findVisible: Bool
    package var resizing: Bool
    package var currentTabID: UUID?
    package var activePeekID: UUID?
    package var commandBarOpen: Bool
    package var windowClosePending: Bool
    package var transferringTabIDs: [UUID]
    package var frameThickness: CGFloat
    package init(boundsWidth: CGFloat, boundsHeight: CGFloat, sidebarWidth: CGFloat, presentation: SidebarPresentation, motionVisible: Bool, floatingSurface: Bool, revealsAnchored: Bool, previewingHidden: Bool, fullscreen: Bool, library: Bool, libraryContentWidth: CGFloat, popup: Bool, sidePanel: Bool, findVisible: Bool, resizing: Bool, currentTabID: UUID? = nil, activePeekID: UUID? = nil, commandBarOpen: Bool, windowClosePending: Bool, transferringTabIDs: [UUID], frameThickness: CGFloat) {
        self.boundsWidth = boundsWidth
        self.boundsHeight = boundsHeight
        self.sidebarWidth = sidebarWidth
        self.presentation = presentation
        self.motionVisible = motionVisible
        self.floatingSurface = floatingSurface
        self.revealsAnchored = revealsAnchored
        self.previewingHidden = previewingHidden
        self.fullscreen = fullscreen
        self.library = library
        self.libraryContentWidth = libraryContentWidth
        self.popup = popup
        self.sidePanel = sidePanel
        self.findVisible = findVisible
        self.resizing = resizing
        self.currentTabID = currentTabID
        self.activePeekID = activePeekID
        self.commandBarOpen = commandBarOpen
        self.windowClosePending = windowClosePending
        self.transferringTabIDs = transferringTabIDs
        self.frameThickness = frameThickness
    }
}

package enum LayoutChromeGeometrySkip {
    package static func shouldReturnEarly(
        previous: LayoutChromeGeometryFingerprint?,
        next: LayoutChromeGeometryFingerprint,
        dirtyHostedLayout: Bool
    ) -> Bool {
        previous == next && !dirtyHostedLayout
    }
}
