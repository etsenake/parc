import AppKit
import QuartzCore

/// One original window's AppKit layout transaction. The native view hierarchy,
/// including its content subtree, participates in the same animation context.
@MainActor
final class SidebarMotionController {
    ///
    /// the anchored groups' cubic.
    enum Style { case anchored, floating, libraryWidth }

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
    private(set) var isAnimating = false

    func animate(layoutRoot: NSView, views: [NSView], style: Style, flushesPreviousLayout: Bool = true,
                 changes: () -> Void, completion: @escaping () -> Void) {
        generation &+= 1
        let token = generation
        isAnimating = true
        //
        //
        // does not. Do not cancel a previous group: AppKit must see its
        // presentation values when retargeting a reversal. Skip only when that
        // forced pass is a true no-op for the first animated frame: the layout
        // root is already clean and no pending layer geometry would change.
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
        // AppKit resizes and redraws a `.duringViewResize` view whose size
        // changes inside the group every display frame, on the main thread,
        // even while it is hidden: a pane's hidden toolbars, failure page and
        //
        // calls; Parc's budget is no per-frame main-thread work in its views
        // (docs/sidebar-motion.md, frame pacing). Hidden, such a view takes one
        // geometry animation like the other participants and gets its own
        // policy back after the group.
        var hidden: [NSView] = []
        let before = geometryAnimations(in: views) { hidden.append($0) }
        for view in hidden { view.layerContentsRedrawPolicy = .beforeViewResize }
        defer { for view in hidden { view.layerContentsRedrawPolicy = .duringViewResize } }

        //
        // its floating view, then restores its dictionary after the group. Parc
        // uses AppKit's public frameSize key for its ordinary NSView owner.
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

        NSAnimationContext.runAnimationGroup { context in
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

            // Retain only the actual geometry animations created by this group,
            // plus still-current predecessors. Never remove a renderer's or
            // another component's animation that later takes the same key.
            owned = owned.filter(\.isCurrent)
            for item in geometryAnimations(in: views) {
                if !before.contains(where: { $0.layer === item.layer && $0.key == item.key && $0.animation === item.animation }),
                   !owned.contains(where: { $0.layer === item.layer && $0.key == item.key && $0.animation === item.animation }) {
                    owned.append(item)
                }
            }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.cancel()
                completion()
            }
        }
    }

    /// A resize, reduced-motion change or another layout owner settles at the
    /// authoritative native frames. This never changes focus or page selection.
    func cancel() {
        generation &+= 1
        isAnimating = false
        let animations = owned
        owned.removeAll()
        for item in animations { item.removeIfCurrent() }
    }

    ///
    /// animated frame: dirty AppKit layout, or layer geometry whose presentation
    /// has not yet caught the model (an origin-only prep move can leave
    /// `needsLayout` false while position is still uncommitted).
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

    /// The geometry animations under `roots`; `hiddenRedrawing`, when given,
    /// also receives each hidden view AppKit would redraw during a resize.
    private func geometryAnimations(in roots: [NSView], hiddenRedrawing: ((NSView) -> Void)? = nil) -> [OwnedAnimation] {
        var seen = Set<ObjectIdentifier>()
        var result: [OwnedAnimation] = []
        func visit(_ view: NSView, hidden: Bool) {
            guard seen.insert(ObjectIdentifier(view)).inserted else { return }
            let hidden = hidden || view.isHidden
            if hidden, view.layerContentsRedrawPolicy == .duringViewResize { hiddenRedrawing?(view) }
            // Do not change layer backing or walk Chromium's compositor layers.
            // The existing NSViews own their AppKit layout and backing layers.
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

    /// A drawing view whose width changes inside the group either keeps
    /// AppKit's `.duringViewResize` policy, which drives its frame and redraw
    /// every display frame outside Core Animation and outside `cancel()`, or
    /// (AppKit's other policies, as for NSButton) gets a bounds animation that
    ///
    ///
    /// placement the view is drawn once at its final size, held at its
    /// alignment, and moves with the group's single geometry animation.
    /// `clips` bounds a view that would otherwise draw past its animating frame.
    static func pinDrawnContent(_ view: NSView, to placement: NSView.LayerContentsPlacement, clips: Bool = false) {
        view.layerContentsRedrawPolicy = .beforeViewResize
        view.layerContentsPlacement = placement
        if clips { view.wantsLayer = true; view.layer?.masksToBounds = true }
    }

    /// A floating surface fills the sidebar container, whose bounds grow 10
    ///
    /// sets `floatingSidebarContainer`'s frame and fades its `shadowView`,
    /// `blurView` and `behindWindowBlurView`. With FloatingSidebarBackgroundView
    ///
    /// presumably resizes its subtree every display frame: those views and its
    /// `themeView`, a WindowBackgroundContainerView whose Metal renderer redraws
    /// on each layout, as it does Parc's material, which keeps that policy.
    /// Parc instead pins the rest of the surface, an adaptation that does less
    ///
    /// the material and `content` is drawn once at its final size and scaled
    /// with the container.
    static func pinSurface(of container: NSView, except content: NSView) {
        for surface in container.subviews where surface !== content && !(surface is NSVisualEffectView) {
            pinDrawnContent(surface, to: .scaleAxesIndependently)
        }
    }

    private static func floatingAnimation() -> CASpringAnimation {
        //
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

///
enum SidebarPresentation {
    case locked, floating, hidden

    /// Whether the sidebar shows (SidebarView.isPresented): a hidden one only
    /// while it still slides, so this turns false in the pass that settles a
    /// hide and true in a reveal's preparation.
    func presents(inMotion: Bool) -> Bool { self != .hidden || inMotion }
}

///
///
///
/// activation; once an item is active the activation decides again.
enum EmptyWindowSidebarRule {
    /// The focused content has no sidebar item with no tab, and while Add
    /// Split's pending pane is focused: its content gets one only when a result
    /// fills it. A Peek needs a parent tab here, so the modal test adds nothing.
    /// Windows that cannot present a sidebar now are left alone.
    static func holdsSidebar(focusedTab: UUID?, pendingSplitPane: Bool, creatingSpace: Bool, popup: Bool, library: Bool) -> Bool {
        (focusedTab == nil || pendingSplitPane) && !creatingSpace && !popup && !library
    }
    /// The presentation a request yields: hiding a window with no active item floats it.
    static func presentation(for requested: SidebarPresentation, noActiveItem: Bool) -> SidebarPresentation {
        requested == .hidden && noActiveItem ? .floating : requested
    }
    enum Refresh { case keep, float, applyHover }
    /// After a render: a window left without an active item floats its hidden
    /// sidebar, and the render that gives it one again hands its floating
    /// sidebar back to the hover activation.
    static func refresh(_ presentation: SidebarPresentation, noActiveItem: Bool, heldBefore: Bool) -> Refresh {
        if noActiveItem { return presentation == .hidden ? .float : .keep }
        return heldBefore && presentation == .floating ? .applyHover : .keep
    }
}

///
/// sidebar fills the leading edge; the floating container is inset 5 points
/// (x + 5, y + 5, height − 10) and otherwise waits off-screen at
///
///
enum SidebarPresentationFrame {
    case locked, floating
    /// Hidden: the anchored hide's end, which keeps the locked y and height
    ///
    ///
    ///
    case hiding, hidden, revealing

    /// The frame a layout pass gives `presentation`: a hidden sidebar slides
    /// out of a locked one at the locked height, starts an anchored reveal
    /// (`revealsAnchored`, set for a hidden → locked preparation) at x − width,
    /// and otherwise, settled or behind a floating surface, waits where the
    /// floating container does.
    init(_ presentation: SidebarPresentation, inMotion: Bool, floatingSurface: Bool, revealsAnchored: Bool) {
        switch presentation {
        case .locked: self = .locked
        case .floating: self = .floating
        case .hidden: self = revealsAnchored ? .revealing : inMotion && !floatingSurface ? .hiding : .hidden
        }
    }

    func rect(width: CGFloat, in bounds: NSRect) -> NSRect {
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

///
/// order: a preparation at the old geometry, the geometry-only group, then the
/// newest generation's full pass (docs/sidebar-motion.md).
struct SidebarTransition {
    ///
    ///
    ///
    let style: SidebarMotionController.Style
    /// A floating surface stays drawn through its whole transition.
    let keepsFloatingSurface: Bool
    /// Floating → locked: the style setter prepares the dock's behind-window
    ///
    let docksFloatingSurface: Bool
    ///
    /// starts at x − width.
    let revealsAnchored: Bool
    ///
    ///
    let flushesPreparation: Bool

    init(from previous: SidebarPresentation, to next: SidebarPresentation) {
        style = previous == .locked || next == .locked ? .anchored : .floating
        keepsFloatingSurface = previous == .floating || next == .floating
        docksFloatingSurface = previous == .floating && next == .locked
        revealsAnchored = previous == .hidden && next == .locked
        flushesPreparation = previous == .hidden
    }
}

/// The frames BrowserWindowController.layoutChrome gives the window's chrome
/// in its flipped root view: one model for its full and preparation passes
/// and for the geometry-only pass of the ⌘S group, sidebar-width drags and the
/// Library width group, which assigns only the sidebar, the Library, the
/// page host (the loading indicator follows it) and the extension side panel.
struct SidebarChromeFrames {
    /// WindowContentsContainerViewController.ViewState.contentInsets
    ///
    /// leading one, as `left` does here, is inferred from the view state's
    /// Edge.Set.
    static let pageInset: CGFloat = 10
    ///
    ///
    static let libraryMinimumWidth: CGFloat = 417
    let sidebar, library, popupChrome, pageHost, sidePanel: NSRect
    let showsSidePanel: Bool

    ///
    /// page's content width.
    init(bounds: NSRect, sidebarWidth width: CGFloat, presentation: SidebarPresentation, placement: SidebarPresentationFrame,
         previewingHidden: Bool = false, fullscreen: Bool = false, library: Bool = false, libraryContentWidth: CGFloat = 0,
         popup: Bool = false, sidePanel: Bool = false) {
        var sidebar = placement.rect(width: width, in: bounds)
        // A width drag's hidden preview already shows the hidden geometry.
        if previewingHidden { sidebar.origin.x = -width }
        self.sidebar = sidebar
        //
        let libraryWidth: CGFloat = !library || fullscreen ? 0
            : max(Self.libraryMinimumWidth, min(bounds.width - 56, libraryContentWidth))
        self.library = NSRect(x: 0, y: 0, width: libraryWidth, height: bounds.height)
        let left: CGFloat = fullscreen ? 0 : libraryWidth > 0 ? libraryWidth
            : (!popup && presentation == .locked && !previewingHidden ? width : popup ? 8 : Self.pageInset)
        let inset: CGFloat = fullscreen ? 0 : Self.pageInset
        //
        let popupHeight: CGFloat = popup && !fullscreen ? 47 : 0
        popupChrome = NSRect(x: 8, y: 0, width: max(0, bounds.width - 16), height: popupHeight)
        //
        // is default-off and lacks a presentation capability in the recovered
        // window setup (extensions-geometry.md). Keep the genuine page in a
        // right-side host; its preferred 240–360 width must fit the actual
        // remaining content region, including initial and narrow layouts.
        let panelRight = max(0, bounds.width - inset)
        let panelWidth = min(max(0, panelRight - left), min(360, max(240, bounds.width * 0.3)))
        showsSidePanel = sidePanel && !fullscreen
        let top = inset + popupHeight, height = max(0, bounds.height - 2 * inset - popupHeight)
        pageHost = NSRect(x: left, y: top, width: max(0, bounds.width - left - inset - (showsSidePanel ? panelWidth : 0)), height: height)
        self.sidePanel = NSRect(x: panelRight - panelWidth, y: top, width: panelWidth, height: height)
    }
}

/// Inputs `BrowserWindowController.layoutChrome` uses to place chrome, to
/// decide presentation surfaces, and for full-pass eligibility refreshes
/// (easel `refreshPageVisibility` / peek layout). Identical values mean the
/// pass would only rewrite the same frames and re-run the same no-op
/// eligibility work.
struct LayoutChromeGeometryFingerprint: Equatable {
    var boundsWidth: CGFloat
    var boundsHeight: CGFloat
    var sidebarWidth: CGFloat
    var presentation: SidebarPresentation
    var motionVisible: Bool
    var floatingSurface: Bool
    var revealsAnchored: Bool
    var previewingHidden: Bool
    var fullscreen: Bool
    var library: Bool
    var libraryContentWidth: CGFloat
    var popup: Bool
    var sidePanel: Bool
    var findVisible: Bool
    var resizing: Bool
    /// Full-pass easel/peek eligibility: `activeOwner` and peek layout follow
    /// selection, Peek, command bar and in-flight transfers — not chrome frames.
    var currentTabID: UUID?
    var activePeekID: UUID?
    var commandBarOpen: Bool
    var windowClosePending: Bool
    var transferringTabIDs: [UUID]
}

/// True no-op gate for direct `layoutChrome` callers (Cmd-S, sidebar motion,
/// width/setting ticks). ThemeRenderer's onLayout skip is separate. A changed
/// presentation, page frame, selection/eligibility input, or other chrome
/// geometry input must not skip; a dirty hosted pageHost / side-panel tree
/// still enters so P1-W/P1-S flushes keep working.
enum LayoutChromeGeometrySkip {
    /// Identical fingerprint with a clean hosted tree returns early. A first
    /// apply (`previous == nil`), any input change, or dirty hosted chrome
    /// still runs the pass.
    static func shouldReturnEarly(
        previous: LayoutChromeGeometryFingerprint?,
        next: LayoutChromeGeometryFingerprint,
        dirtyHostedLayout: Bool
    ) -> Bool {
        previous == next && !dirtyHostedLayout
    }
}
