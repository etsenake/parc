import AppKit

@MainActor private final class SplitConstraintHost: NSView {
    override var isFlipped: Bool { true }
}

@MainActor private final class SplitScaleWindow: NSWindow {
    var testScale: CGFloat = 2
    override var backingScaleFactor: CGFloat { testScale }
}

@main @MainActor struct SplitDividerTests {
    static var count = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        count += 1
        if try !value() { throw NSError(domain: message, code: count) }
    }
    static func near(_ values: [Double], _ expected: [Double]) -> Bool {
        values.count == expected.count && zip(values, expected).allSatisfy { abs($0 - $1) < 0.000001 }
    }
    static func main() throws {
        _ = NSApplication.shared
        let scaleWindow = SplitScaleWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 1200),
                                           styleMask: .borderless, backing: .buffered, defer: false)
        scaleWindow.isReleasedWhenClosed = false
        defer { scaleWindow.close() }
        let scaled = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1000, height: 1000))
        let scalePanes = (0..<3).map { _ in NSView() }
        scalePanes.forEach(scaled.addArrangedSubview)
        scaled.configure(orientation: .horizontal, factors: [1,1,1])
        try check(scalePanes.map { $0.frame.width } == [327,327,327] && scalePanes.last?.frame.maxX == 1001,
                  "Detached fallback scale rounds every pane independently without last-pane fill")
        scaleWindow.contentView!.addSubview(scaled)
        try check(scalePanes.map { $0.frame.width } == [327,326,327]
                  && scalePanes.map { $0.frame.minX } == [0,337,673],
                  "Original window backing scale rounds lengths before final integer frame edges")
        scaled.configure(orientation: .vertical, factors: [1,1,1])
        try check(scalePanes.map { $0.frame.height } == [327,326,327]
                  && scalePanes.map { $0.frame.minY } == [0,337,673],
                  "Vertical panes follow the same backing-scale length and prefix-position calculation")
        scaleWindow.testScale = 1; scaled.viewDidChangeBackingProperties()
        try check(scalePanes.map { $0.frame.height } == [327,327,327] && scalePanes.last?.frame.maxY == 1001,
                  "Original window scale change recalculates existing native panes without a model write")
        scaleWindow.testScale = 2; scaled.viewDidChangeBackingProperties()
        scaled.configure(orientation: .horizontal, factors: [0.3,0.3,0.4])
        let scaledBefore = scalePanes.map(\.frame)
        var scaleCommits: [[Double]] = []
        scaled.prepareDividerResize = { { scaleCommits.append($0); return true } }
        let scaleOrigin = NSPoint(x: scalePanes[0].frame.maxX + 5, y: 200)
        try check(scaled.beginDividerResize(at: scaleOrigin), "Scaled native original pair admits a resize")
        scaled.updateDividerResize(at: NSPoint(x: scaleOrigin.x + 30.3, y: 200), velocity: 200)
        let scaledPreview = scalePanes.map(\.frame)
        try check(scaleCommits.isEmpty && scalePanes.map { $0.frame.width } == [325,263,392]
                  && scalePanes.map { $0.frame.minX } == [0,335,608],
                  "Native preview recalculates every original frame from independently rounded lengths")
        scaled.finishDividerResize(commit: true)
        try check(scaleCommits.count == 1 && near(scaleCommits[0], [324.3 / 980, 0.6 - 324.3 / 980, 0.4]),
                  "Durable ratio uses original global available axis rather than displayed pair width")
        try check(scalePanes.map(\.frame) == scaledPreview
                  && zip(scalePanes, scaled.arrangedSubviews).allSatisfy { $0 === $1 },
                  "Accepted native preview and saved layout have identical geometry on original pane identities")
        scaled.configure(orientation: .horizontal, factors: [0.3,0.3,0.4])
        try check(scaled.beginDividerResize(at: scaleOrigin), "A fresh original receipt admits another scaled gesture")
        scaled.updateDividerResize(at: NSPoint(x: scaleOrigin.x + 30.3, y: 200), velocity: 200)
        scaled.viewDidChangeBackingProperties()
        try check(scalePanes.map(\.frame) == scaledPreview, "Same-scale backing notification retains current original preview")
        scaleWindow.testScale = 1; scaled.viewDidChangeBackingProperties(); scaled.finishDividerResize(commit: true)
        try check(scaleCommits.count == 1 && scalePanes.map(\.frame) == scaledBefore,
                  "Actual backing-scale change cancels captured preview and restores authoritative source ratios")
        scaleWindow.testScale = 2; scaled.viewDidChangeBackingProperties()
        try check(scaled.beginDividerResize(at: scaleOrigin), "Scale-restored original pair can admit again")
        scaled.updateDividerResize(at: NSPoint(x: scaleOrigin.x + 30.3, y: 200), velocity: 200)
        scaleWindow.testScale = 1; scaled.finishDividerResize(commit: true)
        try check(scaleCommits.count == 1 && scalePanes.map(\.frame) == scaledBefore,
                  "Completion rejects a changed scale even before its native notification arrives")
        scaleWindow.testScale = 2; scaled.viewDidChangeBackingProperties()
        scaled.configure(orientation: .horizontal, factors: [0.4,0.01,0.59])
        let shiftedOriginal = scalePanes.map(\.frame)
        let movingOrigin = NSPoint(x: scalePanes[1].frame.maxX + 5, y: 200)
        try check(scaled.beginDividerResize(at: movingOrigin), "Minimum-clamped later pair admits its original views")
        let heldPointer = NSPoint(x: movingOrigin.x + 20, y: 200)
        scaled.updateDividerResize(at: heldPointer, velocity: 200)
        try check(scalePanes[0].frame.width == 392 && scalePanes[1].frame.minX == 402
                  && scalePanes[1].frame.width == 240,
                  "Original minimum redistribution can move the live pane's origin while retaining earlier source share")
        scaled.updateDividerResize(at: heldPointer, velocity: 200)
        try check(scalePanes[1].frame.width == 220 && scaleCommits.count == 1,
                  "Next update retains captured handle offset relative to the live original pane")
        scaled.finishDividerResize(commit: false)
        try check(scalePanes.map(\.frame) == shiftedOriginal && scaleCommits.count == 1,
                  "Cancel restores original source ratios after live origin movement")
        scaleWindow.testScale = .nan; scaled.viewDidChangeBackingProperties()
        scaled.configure(orientation: .horizontal, factors: [1,1,1])
        try check(scalePanes.map { $0.frame.width } == [327,327,327],
                  "Invalid owning-window scale cannot produce nonfinite frame geometry")
        scaleWindow.testScale = 2; scaled.viewDidChangeBackingProperties()
        scaled.configure(orientation: .vertical, factors: [0.01,0.01,0.98])
        let impossibleOrigin = NSPoint(x: 20, y: scalePanes[0].frame.maxY + 5)
        let impossibleBefore = scalePanes.map(\.frame)
        try check(scaled.beginDividerResize(at: impossibleOrigin), "Minimum-clamped pair retains original native admission")
        scaled.updateDividerResize(at: NSPoint(x: 20, y: impossibleOrigin.y + 20), velocity: 200)
        scaled.finishDividerResize(commit: true)
        try check(scaleCommits.count == 1 && scalePanes.map(\.frame) == impossibleBefore,
                  "An unpersistable nonpositive original factor refuses instead of corrupting its group")
        var scaledActivity: [Bool] = []
        scaled.onDividerPanActivity = { scaledActivity.append($0) }
        scaled.prepareDividerResize = { { _ in true } }
        scaled.configure(orientation: .horizontal, factors: [1, 1, 1])
        let scaledPanePoint = NSPoint(x: 100, y: 500)
        try check(scaled.hitTest(scaledPanePoint) === scalePanes[0],
                  "Side-by-side panes keep ordinary hit testing outside a pan")
        let lockOrigin = NSPoint(x: scalePanes[0].frame.maxX + 5, y: 200)
        try check(scaled.beginDividerResize(at: lockOrigin), "Side-by-side divider admits a pan")
        scaled.beginDividerPan(at: lockOrigin)
        try check(scaledActivity == [true] && scaled.hitTest(scaledPanePoint) === scaled,
                  "Side-by-side pan sets reason 0x2 and locks pane input")
        scaleWindow.testScale = 1; scaled.viewDidChangeBackingProperties()
        try check(scaledActivity == [true, false] && !scaled.isDividerPanActive && scaled.hitTest(scaledPanePoint) === scalePanes[0],
                  "A backing-scale change mid-pan clears reason 0x2 and the pane lock")
        scaleWindow.testScale = 2; scaled.viewDidChangeBackingProperties()
        scaled.removeFromSuperview()
        let constraintWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                                        styleMask: .borderless, backing: .buffered, defer: false)
        constraintWindow.isReleasedWhenClosed = false
        defer { constraintWindow.close() }
        let windowFrame = constraintWindow.frame
        let host = SplitConstraintHost(frame: NSRect(x: 20, y: 30, width: 500, height: 300))
        constraintWindow.contentView!.addSubview(host)
        let constrained = ParcSplitView(frame: host.bounds)
        host.addSubview(constrained); constrained.constrain(to: host)
        let constraintPanes = (0..<3).map { _ in NSView() }
        constraintPanes.forEach(constrained.addArrangedSubview)
        constrained.configure(orientation: .horizontal, factors: [1, 2, 3])
        try check(constrained.frame == NSRect(x: 0, y: 0, width: 680, height: 382),
                  "Native required split minimum yields only its softer trailing and bottom edges")
        try check(host.frame == NSRect(x: 20, y: 30, width: 500, height: 300) && constraintWindow.frame == windowFrame,
                  "Split minimum does not enlarge or reposition the original host/window")
        try check(constraintPanes.allSatisfy { $0.frame.width == 220 } && constraintPanes.last?.frame.maxX == 680,
                  "All original expanded panes keep minimum width in a small original host")
        let originalConstraints = (host.constraints + constrained.constraints).filter {
            ($0.firstItem as? NSView) === constrained || ($0.secondItem as? NSView) === constrained
        }
        try check(originalConstraints.filter { $0.isActive && ($0.firstAttribute == .trailing || $0.firstAttribute == .bottom) }
                    .allSatisfy { $0.priority == .defaultHigh }
                  && originalConstraints.filter { $0.isActive && ($0.firstAttribute == .leading || $0.firstAttribute == .top) }
                    .allSatisfy { $0.priority == .required },
                  "Native parent edge priority matches original required versus 750 contract")
        host.frame.size = NSSize(width: 1200, height: 900); host.layoutSubtreeIfNeeded()
        try check(constrained.frame == host.bounds && constraintPanes.last?.frame.maxX == 1200,
                  "The same constrained container fills a larger original host")
        let roomyFrames = constraintPanes.map(\.frame)
        constrained.configure(orientation: .vertical, factors: [1, 2, 3])
        host.frame.size = NSSize(width: 500, height: 300); host.layoutSubtreeIfNeeded()
        try check(constrained.frame == NSRect(x: 0, y: 0, width: 680, height: 382)
                  && constraintPanes.allSatisfy { $0.frame.height == 220 }
                  && constraintPanes.last?.frame.maxY == 680,
                  "Original width constraint remains orientation independent; vertical panes do not shrink below minimum")
        host.frame.size = NSSize(width: 1200, height: 900); host.layoutSubtreeIfNeeded()
        constrained.configure(orientation: .horizontal, factors: [1, 2, 3])
        try check(constraintPanes.map(\.frame) == roomyFrames && zip(constrained.arrangedSubviews, constraintPanes).allSatisfy { $0 === $1 },
                  "Growing the host restores original ratio geometry on the same native panes")
        var constraintCommits = 0
        constrained.prepareDividerResize = { { _ in constraintCommits += 1; return true } }
        let constraintOrigin = NSPoint(x: constraintPanes[0].frame.maxX + 5, y: 200)
        try check(constrained.beginDividerResize(at: constraintOrigin), "Constrained actual divider admits an original pair")
        constrained.updateDividerResize(at: NSPoint(x: constraintOrigin.x + 40, y: 200), velocity: 200)
        host.frame.size.width = 900; host.layoutSubtreeIfNeeded(); constrained.finishDividerResize(commit: true)
        try check(constraintCommits == 0 && constrained.frame.width == 900,
                  "Original host resize cancels captured divider without publishing preview ratios")
        constraintPanes.dropFirst().forEach { $0.removeFromSuperview() }
        host.frame.size = NSSize(width: 180, height: 140)
        constrained.configure(orientation: .horizontal, factors: [1])
        try check(constrained.frame == host.bounds && constraintPanes[0].frame == constrained.bounds,
                  "One original pane restores existing single-page/popup sizing without split minima")
        constrained.removeFromSuperview()
        try check(originalConstraints.allSatisfy { !$0.isActive }, "Detachment retires the exact parent constraint lease")
        let axSplit = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1000, height: 500))
        constraintWindow.contentView!.addSubview(axSplit)
        let axPanes = [NSView(), NSView()]
        for pane in axPanes {
            pane.setAccessibilityElement(true); pane.setAccessibilityRole(.group)
            axSplit.addArrangedSubview(pane)
        }
        axSplit.configure(orientation: .horizontal, factors: [1, 1])
        let axChildren = NSAccessibility.unignoredChildren(from: [axSplit]).map { $0 as AnyObject }
        try check(!axSplit.isAccessibilityElement() && axSplit.accessibilityRole() != .splitGroup
                  && (axSplit.accessibilitySplitters() ?? []).isEmpty
                  && axChildren.count == 2 && axChildren[0] === axPanes[0] && axChildren[1] === axPanes[1],
                  "Plain native container is ignored: panes are exposed directly and no splitter exists")
        axSplit.removeFromSuperview()
        let backingHost = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        backingHost.wantsLayer = true
        backingHost.layer?.cornerRadius = 7
        let backingSplit = ParcSplitView(frame: backingHost.bounds)
        backingHost.addSubview(backingSplit)
        let opaquePane = NSView(), translucentPane = NSView()
        opaquePane.wantsLayer = true; opaquePane.layer?.backgroundColor = NSColor.white.cgColor
        translucentPane.wantsLayer = true; translucentPane.layer?.backgroundColor = NSColor.clear.cgColor
        backingSplit.addArrangedSubview(opaquePane); backingSplit.addArrangedSubview(translucentPane)
        backingSplit.configure(orientation: .horizontal, factors: [1,1])
        let backingFrames = backingSplit.arrangedSubviews.map(\.frame)
        backingSplit.configureBacking(in: backingHost, hasTranslucentPane: true)
        try check(!backingSplit.isOpaque && backingSplit.dividerColor.alphaComponent == 0
                  && backingSplit.layer?.backgroundColor == nil && backingSplit.layer?.masksToBounds == false,
                  "Split container exposes original parent backing instead of a fixed separator surface")
        try check(backingHost.layer?.backgroundColor?.alpha == 0 && backingHost.layer?.masksToBounds == false,
                  "Actual split host reveals its original surrounding window surface")
        try check(backingSplit.arrangedSubviews.allSatisfy {
            $0.layer?.cornerRadius == 6 && $0.layer?.cornerCurve == .continuous && $0.layer?.masksToBounds == true
        }, "Each original pane owns its recovered continuous rounded clipping")
        try check(opaquePane.layer?.backgroundColor?.alpha == 1 && translucentPane.layer?.backgroundColor?.alpha == 0,
                  "Per-pane browser and translucent Note backings remain unchanged")
        try check(backingSplit.arrangedSubviews[0] === opaquePane && backingSplit.arrangedSubviews[1] === translucentPane
                  && backingSplit.arrangedSubviews.map(\.frame) == backingFrames,
                  "Backing updates preserve actual pane identity, parent and geometry")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 12,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.magenta.setFill(); NSRect(x: 0, y: 0, width: 12, height: 12).fill()
        backingSplit.drawDivider(in: NSRect(x: 0, y: 0, width: 12, height: 12))
        NSGraphicsContext.restoreGraphicsState()
        let separatorPixel = bitmap.colorAt(x: 6, y: 6)!.usingColorSpace(.sRGB)!
        try check(separatorPixel.redComponent > 0.99 && separatorPixel.greenComponent < 0.01
                  && separatorPixel.blueComponent > 0.99 && separatorPixel.alphaComponent > 0.99,
                  "Actual native divider draw leaves the existing parent pixels intact")
        opaquePane.removeFromSuperview()
        backingSplit.configureBacking(in: backingHost, hasTranslucentPane: true)
        try check(backingHost.layer?.backgroundColor?.alpha == 0 && backingHost.layer?.masksToBounds == true
                  && translucentPane.layer?.cornerRadius == 0 && translucentPane.layer?.masksToBounds == false,
                  "Returning to a single Note restores its original transparent host policy")
        backingSplit.configureBacking(in: backingHost, hasTranslucentPane: false)
        try check(backingHost.layer?.backgroundColor == NSColor.white.cgColor && backingHost.layer?.cornerRadius == 7,
                  "Returning to one ordinary page restores its existing opaque rounded host")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-dividers-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root)
        let ids = (0..<4).map { store.open("https://\($0).invalid") }
        store.setSplit(ids); store.setSplitLayout(orientation: .horizontal, widthFactors: [1,2,3,4])
        let original = store.activeSplitLayout!, originalTabs = store.state.tabs
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 1200), styleMask: .borderless, backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        defer { win.close() }
        let view = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
        win.contentView!.addSubview(view)
        for _ in ids { view.addArrangedSubview(NSView()) }
        view.configure(orientation: .horizontal, factors: original.widthFactors)
        try check(view.dividerThickness == 10, "Browser's actual content inset supplies ten-point dividers")
        try check(view.arrangedSubviews.allSatisfy { $0.frame.width >= 220 }, "Expanded horizontal panes enforce recovered minimum")
        let geometry = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1201, height: 901))
        for _ in 0..<3 { geometry.addArrangedSubview(NSView()) }
        geometry.configure(orientation: .horizontal, factors: [0.01, 0.49, 0.5])
        let geometricPanes = geometry.arrangedSubviews
        func integralEdges(_ rect: NSRect) -> Bool {
            [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy { $0 == $0.rounded() }
        }
        try check(geometricPanes[0].frame.width == 220 && geometricPanes.allSatisfy { integralEdges($0.frame) },
                  "Fractional shares clamp and align actual pane edges")
        try check(zip(geometricPanes, geometricPanes.dropFirst()).allSatisfy { $1.frame.minX - $0.frame.maxX == 10 }
                  && geometricPanes.last?.frame.maxX == geometry.bounds.maxX,
                  "Rounded pane edges preserve exact gaps and fill the original viewport")
        var geometryCommits = 0
        geometry.prepareDividerResize = { { _ in geometryCommits += 1; return true } }
        let geometryOrigin = NSPoint(x: geometricPanes[0].frame.maxX + 5, y: 200)
        try check(geometry.beginDividerResize(at: geometryOrigin), "Actual minimum-size divider admits original pair")
        geometry.updateDividerResize(at: NSPoint(x: -900, y: 200), velocity: -200)
        try check(geometricPanes[0].frame.width == 220 && geometricPanes[2].frame.width == 591 && geometryCommits == 0,
                  "Minimum-clamped live mutation rerenders all panes while preserving the third source factor")
        geometry.finishDividerResize(commit: false)
        geometry.configure(orientation: .vertical, factors: [0.01, 0.49, 0.5])
        try check(geometricPanes[0].frame.height == 220 && geometricPanes.allSatisfy { integralEdges($0.frame) },
                  "Vertical expanded panes use same recovered minimum and aligned edges")
        try check(zip(geometricPanes, geometricPanes.dropFirst()).allSatisfy { $1.frame.minY - $0.frame.maxY == 10 }
                  && geometricPanes.last?.frame.maxY == geometry.bounds.maxY,
                  "Vertical layout preserves exact divider gaps and original viewport extent")
        geometry.frame.size.height = 400; geometry.adjustSubviews()
        try check(geometricPanes.allSatisfy { $0.frame.height == 220 && integralEdges($0.frame) }
                  && geometricPanes.last?.frame.maxY == 680,
                  "Expanded original panes keep their minimum instead of compressing to an undersized viewport")
        geometry.frame.size.height = 901; geometry.adjustSubviews()
        try check(geometricPanes[0].frame.height == 220 && geometryCommits == 0,
                  "Restored viewport recovers source ratios and minimum without rewriting durable layout")
        func grips() -> [CALayer] { (view.layer?.sublayers ?? []).filter { $0.name == "Split divider grip" } }
        func ink(_ layer: CALayer) -> NSColor? { layer.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB) }
        view.appearance = NSAppearance(named: .aqua)
        view.viewDidChangeEffectiveAppearance()
        try check(grips().count == 3 && view.arrangedSubviews.count == ids.count, "Grip layers do not become panes or change the original child list")
        let firstGrip = grips()[0]
        try check(firstGrip.frame.size == NSSize(width: 2, height: 24) && firstGrip.cornerRadius == 1,
                  "Actual horizontal grip has recovered size and radius")
        try check(firstGrip.frame.midX == view.arrangedSubviews[0].frame.maxX + view.dividerThickness / 2 && firstGrip.frame.midY == view.bounds.midY,
                  "Grip centers on the original divider's actual frame")
        try check(abs((ink(firstGrip)?.alphaComponent ?? -1) - 0.2) < 0.000001 && ink(firstGrip)?.redComponent == 0,
                  "Light appearance resolves idle DragHint black at twenty percent")
        let hoverPoint = NSPoint(x: firstGrip.frame.midX, y: firstGrip.frame.midY)
        let originalGripFrames = grips().map(\.frame)
        view.updateDividerHover(at: hoverPoint, animated: false)
        try check(grips().allSatisfy { !$0.isHidden } && ink(firstGrip)?.alphaComponent == 0.5,
                  "Pointed divider highlights its visible grip")
        view.updateDividerHover(at: nil, animated: false)
        try check(grips().allSatisfy { !$0.isHidden } && grips().map(\.frame) == originalGripFrames,
                  "Hover changes only grip ink, never its geometry or visibility")
        let topGap = NSPoint(x: hoverPoint.x, y: 52), regionTop = NSPoint(x: hoverPoint.x, y: 53)
        view.updateDividerHover(at: topGap, animated: false)
        try check(abs((ink(firstGrip)?.alphaComponent ?? -1) - 0.2) < 0.000001,
                  "The top 53 points of a side-by-side divider are outside its original hover region")
        view.updateDividerHover(at: regionTop, animated: false)
        try check(ink(firstGrip)?.alphaComponent == 0.5, "The original region starts 53 points below the divider top")
        view.updateDividerHover(at: nil, animated: false)
        view.prepareDividerResize = { { _ in false } }
        try check(!view.beginDividerResize(at: topGap) && view.beginDividerResize(at: regionTop),
                  "Pan admission uses the same draggable region")
        view.finishDividerResize(commit: false)
        view.updateTrackingAreas()
        try check(view.trackingAreas.count == 3 && view.trackingAreas.allSatisfy {
                      $0.rect.minY == 53 && $0.rect.maxY == view.bounds.maxY && $0.rect.width == view.dividerThickness
                          && $0.options.contains(.enabledDuringMouseDrag) && $0.options.contains(.activeInKeyWindow)
                  }, "Tracking areas cover each draggable region with the original 0x421 options")
        let stacked = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 900, height: 900))
        let stackedPanes = [NSView(), NSView()]
        stackedPanes.forEach(stacked.addArrangedSubview)
        stacked.configure(orientation: .vertical, factors: [1, 1])
        stacked.prepareDividerResize = { { _ in true } }
        let stackedY = stackedPanes[0].frame.maxY + 5
        try check(!stacked.beginDividerResize(at: NSPoint(x: 7, y: stackedY))
                  && !stacked.beginDividerResize(at: NSPoint(x: 893, y: stackedY))
                  && stacked.beginDividerResize(at: NSPoint(x: 8, y: stackedY)),
                  "A stacked-pane divider excludes eight points at each end")
        stacked.finishDividerResize(commit: false)
        var panActivity: [Bool] = []
        stacked.onDividerPanActivity = { panActivity.append($0) }
        func paneHit(_ y: CGFloat) -> Bool { stackedPanes.contains { $0 === stacked.hitTest(NSPoint(x: 450, y: y)) } }
        let stackedPoint = NSPoint(x: 450, y: stackedY)
        try check(stacked.beginDividerResize(at: stackedPoint) && panActivity.isEmpty
                  && paneHit(100) && paneHit(800),
                  "Mouse-down admission alone sets no resize reason and keeps pane input")
        stacked.beginDividerPan(at: stackedPoint)
        try check(panActivity == [true] && stacked.isDividerPanActive
                  && stacked.hitTest(NSPoint(x: 450, y: 100)) === stacked
                  && stacked.hitTest(NSPoint(x: 450, y: 800)) === stacked,
                  "Pan began sets reason 0x2 and every pane refuses hit testing")
        stacked.updateDividerResize(at: NSPoint(x: 450, y: stackedY + 30), velocity: 200)
        stacked.finishDividerResize(commit: true)
        try check(panActivity == [true, false] && !stacked.isDividerPanActive
                  && paneHit(100) && paneHit(800),
                  "Ended pan clears reason 0x2 and restores pane input")
        stacked.configure(orientation: .vertical, factors: [1, 1])
        try check(stacked.beginDividerResize(at: stackedPoint), "A second gesture admits")
        stacked.beginDividerPan(at: stackedPoint)
        stacked.configure(orientation: .vertical, factors: [2, 1])
        try check(panActivity == [true, false, true, false] && paneHit(100),
                  "An owner change that cancels the captured pan also clears its reason")
        stacked.updateDividerResize(at: NSPoint(x: 450, y: stackedY + 30), velocity: 200)
        stacked.finishDividerResize(commit: true)
        try check(panActivity.count == 4, "Later recognizer events after cancellation report nothing further")
        let doubleClickWindow = NSWindow(contentRect: stacked.frame, styleMask: .borderless, backing: .buffered, defer: false)
        doubleClickWindow.isReleasedWhenClosed = false
        defer { doubleClickWindow.close() }
        doubleClickWindow.contentView!.addSubview(stacked)
        stacked.configure(orientation: .vertical, factors: [1, 1])
        var equalizeCommits = 0
        stacked.prepareDividerResize = { { _ in equalizeCommits += 1; return true } }
        for x in [4.0, 450.0] {
            let location = stacked.convert(NSPoint(x: x, y: stackedY), to: nil)
            stacked.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: doubleClickWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!)
        }
        try check(equalizeCommits == 1 && panActivity.count == 4,
                  "Double click equalizes only inside the draggable region and never sets the drag reason")
        try check(stacked.beginDividerResize(at: NSPoint(x: 450, y: stackedY)), "A pan admits before detachment")
        stacked.beginDividerPan(at: NSPoint(x: 450, y: stackedY))
        try check(panActivity.last == true && stacked.isDividerPanActive && !paneHit(100), "The pan is active and locks panes")
        stacked.removeFromSuperview()
        try check(panActivity.last == false && !stacked.isDividerPanActive && paneHit(100) && paneHit(800),
                  "Detachment mid-pan clears reason 0x2 and the pane lock")
        view.updateDividerHover(at: hoverPoint)
        try check(ink(firstGrip)?.alphaComponent == 0.5 && abs((ink(grips()[1])?.alphaComponent ?? -1) - 0.2) < 0.000001,
                  "Only the exact pointed divider receives highlighted ink")
        try check(firstGrip.animation(forKey: "Split grip hover")?.duration == 0.16,
                  "Original hover uses the recovered native animation duration with no Reduce Motion gate (now \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))")
        view.updateDividerHover(at: nil, animated: false)
        try check(firstGrip.animation(forKey: "Split grip hover") == nil && abs((ink(firstGrip)?.alphaComponent ?? -1) - 0.2) < 0.000001,
                  "Immediate owner invalidation clears transition and hover")
        view.updateDividerHover(at: hoverPoint)
        view.appearance = NSAppearance(named: .darkAqua)
        view.viewDidChangeEffectiveAppearance()
        try check(ink(firstGrip)?.redComponent == 1 && ink(firstGrip)?.alphaComponent == 0.5 && firstGrip.animationKeys()?.isEmpty != false,
                  "Appearance changes preserve exact hover but resolve highlighted white without stale animation")
        view.updateDividerHover(at: NSPoint(x: CGFloat.nan, y: 10))
        try check(abs((ink(firstGrip)?.alphaComponent ?? -1) - 0.2) < 0.000001,
                  "Nonfinite pointer cannot retain highlighted divider")
        view.updateDividerHover(at: NSPoint(x: 10, y: 10), animated: false)
        try check(view.hitTest(NSPoint(x: 10, y: 10)) === view.arrangedSubviews[0], "Grip presentation leaves original pane input on its existing view")
        view.updateDividerHover(at: hoverPoint)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: win)
        try check(firstGrip.animationKeys()?.isEmpty != false && abs((ink(firstGrip)?.alphaComponent ?? -1) - 0.2) < 0.000001,
                  "Original window key loss immediately retires highlighted presentation")
        view.updateTrackingAreas()
        try check(view.trackingAreas.allSatisfy { !$0.rect.isNull && !$0.rect.isEmpty && $0.rect.minX.isFinite && $0.rect.minY.isFinite },
                  "Native tracking areas contain only real visible divider geometry")
        func doubleClick(_ divider: Int) {
            let pane = view.arrangedSubviews[divider]
            let local = view.isVertical ? NSPoint(x: pane.frame.maxX + 3, y: 200) : NSPoint(x: 200, y: pane.frame.maxY + 3)
            let point = view.convert(local, to: nil)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: win.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
            view.mouseDown(with: event)
        }
        var calls = 0
        view.prepareDividerResize = {
            let captured = store.activeSplitLayout!
            return { factors in calls += 1; return store.resizeSplit(expected: captured, widthFactors: factors) }
        }
        doubleClick(1)
        let movingLayers = view.arrangedSubviews.compactMap(\.layer) + grips()
        func layoutAnimations() -> [CAAnimationGroup] {
            movingLayers.compactMap { $0.animation(forKey: "Split divider equalization") as? CAAnimationGroup }
        }
        let animation = layoutAnimations().first
        try check(animation?.duration == 0.2 && animation?.timingFunction == CAMediaTimingFunction(name: .easeOut),
                  "Accepted double click uses recovered duration and native ease-out curve whatever the Reduce Motion setting")
        try check(animation?.animations?.compactMap { ($0 as? CABasicAnimation)?.keyPath } == ["position", "bounds"],
                  "Motion transforms only original live geometry, without a snapshot or new surface")
        let durableAfterMotion = store.activeSplitLayout
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: win)
        try check(layoutAnimations().isEmpty && store.activeSplitLayout == durableAfterMotion,
                  "Key loss retires owned motion without reversing accepted durable state")
        try check(calls == 1 && near(store.activeSplitLayout!.widthFactors, [0.1,0.25,0.25,0.4]), "Native double click equalizes only original adjacent pair")
        try check(abs(view.arrangedSubviews[1].frame.width - view.arrangedSubviews[2].frame.width) <= 1, "Native equalization differs by at most one rounded point")
        try check(store.state.selectedTabIDs == ids && store.state.tabs == originalTabs, "Geometry operation leaves page records and selection untouched")
        let changed = store.activeSplitLayout!
        try check(changed.id == original.id && changed.sidebarAnchorID == original.sidebarAnchorID && changed.tabIDs == ids, "Original group and anchor identity retained")
        let loaded = try BrowserStore(directory: root)
        try check(loaded.activeSplitLayout == changed, "Exact layout is durable before publication")
        try check(!store.resizeSplit(expected: original, widthFactors: [1,1,1,1]), "Stale original ratio receipt cannot retarget")
        let frames = view.arrangedSubviews.map(\.frame)
        view.prepareDividerResize = { nil }; doubleClick(2)
        try check(view.arrangedSubviews.map(\.frame) == frames && store.activeSplitLayout == changed, "Unavailable native owner leaves divider unchanged")
        view.prepareDividerResize = { { _ in false } }; doubleClick(2)
        try check(view.arrangedSubviews.map(\.frame) == frames, "Refused completion restores original native geometry")
        try check(layoutAnimations().isEmpty, "Refused original transaction never starts equalization motion")
        view.prepareDividerResize = { { _ in
            view.configure(orientation: .vertical, factors: [1,1,1,1]); return true
        } }
        doubleClick(2)
        try check(!view.isVertical && layoutAnimations().isEmpty,
                  "Synchronous owner orientation change cannot animate or overwrite its new authoritative layout")
        store.setSplitLayout(orientation: .vertical, widthFactors: [1,2,3,4])
        view.configure(orientation: .vertical, factors: store.activeSplitLayout!.widthFactors)
        view.prepareDividerResize = {
            let captured = store.activeSplitLayout!
            return { factors in store.resizeSplit(expected: captured, widthFactors: factors) }
        }
        try check(grips().allSatisfy { $0.frame.size == NSSize(width: 24, height: 2) }, "Vertical layout keeps a horizontal grip on each actual divider")
        try check(grips()[0].frame.midY == view.arrangedSubviews[0].frame.maxY + view.dividerThickness / 2 && grips()[0].frame.midX == view.bounds.midX,
                  "Vertical grip uses current divider and viewport coordinates")
        doubleClick(0)
        try check(near(store.activeSplitLayout!.widthFactors, [0.15,0.15,0.3,0.4]), "Vertical pair operation preserves the other panes' shares")
        try check(abs(view.arrangedSubviews[0].frame.height - view.arrangedSubviews[1].frame.height) <= 1, "Native vertical frames equalize adjacent heights")
        let failure = store.activeSplitLayout!, failureState = store.state
        try store.save(); try FileManager.default.removeItem(at: root); try Data().write(to: root)
        try check(!store.resizeSplit(expected: failure, widthFactors: [1,1,1,1]), "Real disk failure refuses geometry publication")
        try check(store.state == failureState && store.persistenceError != nil, "Failed save retains complete original group and selection")
        try FileManager.default.removeItem(at: root); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try check(store.resizeSplit(expected: failure, widthFactors: [1,1,1,1]), "Original receipt retries after storage recovers")
        try check(store.state.tabs == originalTabs && store.state.selectedTabIDs == ids, "Retry never recreates pages or changes selection")
        let current = store.activeSplitLayout!, state = store.state
        try check(!store.resizeSplit(expected: current, widthFactors: [0,1,1,1]) && store.state == state, "Invalid factors cannot corrupt original geometry")
        _ = store.open("https://different-selection.invalid"); let selected = store.state
        try check(!store.resizeSplit(expected: current, widthFactors: [1,1,1,1]) && store.state == selected, "Selection change during a divider operation refuses stale completion")
        let lastGrip = grips()[0]
        view.updateDividerHover(at: NSPoint(x: lastGrip.frame.midX, y: lastGrip.frame.midY))
        view.removeFromSuperview()
        try check(lastGrip.animationKeys()?.isEmpty != false && abs((ink(lastGrip)?.alphaComponent ?? -1) - 0.2) < 0.000001,
                  "Detaching original view revokes its native hover presentation")
        for pane in view.arrangedSubviews { view.removeArrangedSubview(pane); pane.removeFromSuperview() }
        view.adjustSubviews()
        try check(grips().isEmpty && view.trackingAreas.isEmpty, "Retired panes remove their grip and tracking owners")

        let commandRoot = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-commands-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: commandRoot) }
        let commands = try BrowserStore(directory: commandRoot)
        let commandIDs = (0..<3).map { commands.open("https://command-\($0).invalid") }
        commands.setSplit(commandIDs); commands.setSplitLayout(orientation: .horizontal, widthFactors: [1,1,1])
        let commandWindow = SplitScaleWindow(contentRect: NSRect(x: 0, y: 0, width: 1610, height: 800), styleMask: .borderless, backing: .buffered, defer: false)
        commandWindow.isReleasedWhenClosed = false
        defer { commandWindow.close() }
        let commanded = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1210, height: 800))
        commandWindow.contentView!.addSubview(commanded)
        let commandPanes = commandIDs.map { _ in NSView() }
        commandPanes.forEach(commanded.addArrangedSubview)
        commanded.configure(orientation: .horizontal, factors: commands.activeSplitLayout!.widthFactors)
        func commandMotion() -> Bool {
            let layers = commanded.arrangedSubviews.compactMap(\.layer)
                + (commanded.layer?.sublayers ?? []).filter { $0.name == "Split divider grip" }
            return layers.contains { !($0.animationKeys() ?? []).isEmpty }
        }
        let grouped = commands.activeSplitLayout!
        let expanded = grouped.expandedFactors(focusing: commandIDs[1])!
        try check(grouped.expandedFactors(focusing: UUID()) == nil, "Expand refuses a pane outside the original group")
        try check(commands.resizeSplit(expected: grouped, widthFactors: expanded), "Expand commits through the original resize-end transaction")
        try check(commands.activeSplitLayout!.tabIDs == commandIDs && commands.state.selectedTabIDs == commandIDs,
                  "Expand keeps every original pane displayed and in order")
        try check(try BrowserStore(directory: commandRoot).activeSplitLayout == commands.activeSplitLayout,
                  "Expanded weights persist, reported as a resize end")
        try check(commands.activeSplitLayout!.expandedFactors(focusing: commandIDs[1]) == commands.activeSplitLayout!.widthFactors,
                  "Expanding the already expanded pane computes identical weights, which the command skips")
        commanded.configure(orientation: .horizontal, factors: commands.activeSplitLayout!.widthFactors)
        try check(commandPanes.map { $0.frame.width } == [220, 750, 220] && !commandMotion(),
                  "Expand gives the focused pane the rest and others the expanded minimum, immediately")
        commanded.setFrameSize(NSSize(width: 1610, height: 800))
        try check(commandPanes.map { $0.frame.width } == [220, 1150, 220],
                  "A zero weight stays at the expanded minimum at any window width")
        commanded.configure(orientation: .vertical, factors: commands.activeSplitLayout!.widthFactors)
        try check(commandPanes.map { $0.frame.height } == [220, 340, 220] && !commandMotion(),
                  "Converting orientation lays out immediately with the same weights")
        commanded.configure(orientation: .vertical, factors: [1,1,1])
        try check(commandPanes.map { $0.frame.height }.max()! - commandPanes.map { $0.frame.height }.min()! <= 1 && !commandMotion(),
                  "A saved weight change from another owner lays out immediately")
        commanded.removeArrangedSubview(commandPanes[0]); commandPanes[0].removeFromSuperview()
        commanded.configure(orientation: .vertical, factors: [1,1])
        try check(commandPanes[1].frame.minY == 0 && commandPanes[2].frame.maxY == 800 && !commandMotion(),
                  "Closing or separating a pane lays out the survivors immediately")
        commanded.removeArrangedSubview(commandPanes[2]); commandPanes[2].removeFromSuperview()
        commanded.configure(orientation: .vertical, factors: [1])
        try check(commandPanes[1].frame == commanded.bounds && !commandMotion(),
                  "A one-child split dissolves into a full single pane immediately")
        let pending = NSView()
        commanded.insertArrangedSubview(pending, at: 1)
        commanded.configure(orientation: .horizontal, factors: [1,1])
        try check(pending.frame.minX == commandPanes[1].frame.maxX + 10 && !commandMotion(),
                  "An Add Split pending pane is inserted immediately")
        commanded.removeArrangedSubview(pending); pending.removeFromSuperview()
        commanded.configure(orientation: .horizontal, factors: [1])
        try check(commandPanes[1].frame == commanded.bounds && !commandMotion(),
                  "Cancelling the pending pane restores the original layout immediately")

        let degenerate = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1210, height: 800))
        commandWindow.contentView!.addSubview(degenerate)
        let degeneratePanes = (0..<3).map { _ in NSView() }
        degeneratePanes.forEach(degenerate.addArrangedSubview)
        degenerate.configure(orientation: .horizontal, factors: [0.75, 0.25, 1e-9])
        let degenerateWidths = degeneratePanes.map(\.frame.width)
        try check(degenerateWidths[2] == 220 && degenerateWidths[1] > 220 && degenerateWidths[1] < 0.25 * 1190,
                  "Minimum redistribution displays more than the pair's saved share")
        var degenerateCommits: [[Double]] = []
        degenerate.prepareDividerResize = { { degenerateCommits.append($0); return true } }
        let degenerateOrigin = NSPoint(x: degeneratePanes[1].frame.maxX + 5, y: 200)
        try check(degenerate.beginDividerResize(at: degenerateOrigin), "Degenerate saved pair still admits a resize")
        degenerate.updateDividerResize(at: NSPoint(x: degenerateOrigin.x - 10, y: 200), velocity: 200)
        try check(degeneratePanes[0].frame.width == degenerateWidths[0]
                  && degeneratePanes[1].frame.width == degenerateWidths[1] - 10 && degeneratePanes[2].frame.width == 230,
                  "Its divider moves only the two panes' displayed space")
        degenerate.finishDividerResize(commit: true)
        try check(degenerateCommits.count == 1 && BrowserSplitLayout.normalized(degenerateCommits[0], count: 3) != nil
                  && degeneratePanes[0].frame.width == degenerateWidths[0],
                  "The drag commits valid weights and keeps the other pane's size")
        degenerate.configure(orientation: .horizontal, factors: [0.75, 0.25, 1e-9])
        let degenerateEvent = NSEvent.mouseEvent(with: .leftMouseDown,
            location: degenerate.convert(NSPoint(x: degeneratePanes[1].frame.maxX + 3, y: 200), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: commandWindow.windowNumber, context: nil,
            eventNumber: 1, clickCount: 2, pressure: 1)!
        degenerate.mouseDown(with: degenerateEvent)
        try check(degenerateCommits.count == 2 && degeneratePanes[0].frame.width == degenerateWidths[0]
                  && abs(degeneratePanes[1].frame.width - degeneratePanes[2].frame.width) <= 1,
                  "Double click splits the pair's displayed space and leaves the other pane alone")
        commandWindow.testScale = 1
        let unscaled = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1210, height: 800))
        commandWindow.contentView!.addSubview(unscaled)
        let unscaledPanes = (0..<3).map { _ in NSView() }
        unscaledPanes.forEach(unscaled.addArrangedSubview)
        unscaled.configure(orientation: .horizontal, factors: [0.75, 0.25, 1e-9])
        let unscaledWidths = unscaledPanes.map(\.frame.width)
        try check(unscaledWidths.reduce(0, +) > 1190, "At 1x independently rounded pane lengths overrun the available length")
        unscaled.prepareDividerResize = { { _ in true } }
        let unscaledOrigin = NSPoint(x: unscaledPanes[1].frame.maxX + 5, y: 200)
        try check(unscaled.beginDividerResize(at: unscaledOrigin), "The 1x degenerate pair admits a resize")
        unscaled.updateDividerResize(at: NSPoint(x: unscaledOrigin.x - 10, y: 200), velocity: 200)
        try check(unscaledPanes[0].frame.width == unscaledWidths[0] && unscaledPanes[1].frame.width == unscaledWidths[1] - 10
                  && unscaledPanes[2].frame.width == 229 && unscaledPanes[2].frame.maxX == 1210,
                  "At 1x the pair takes up the rounding remainder and the other pane keeps its size")
        unscaled.finishDividerResize(commit: true)
        try check(unscaledPanes[0].frame.width == unscaledWidths[0], "The 1x commit keeps the other pane's size")
        unscaled.configure(orientation: .horizontal, factors: [0.75, 0.25, 1e-9])
        unscaled.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown,
            location: unscaled.convert(NSPoint(x: unscaledPanes[1].frame.maxX + 3, y: 200), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: commandWindow.windowNumber, context: nil,
            eventNumber: 2, clickCount: 2, pressure: 1)!)
        try check(unscaledPanes[0].frame.width == unscaledWidths[0] && unscaledPanes[1].frame.width == unscaledPanes[2].frame.width,
                  "A 1x double click splits the pair evenly and leaves the other pane alone")
        unscaled.configure(orientation: .horizontal, factors: [1e-9, 0.25, 0.75])
        let leadingWidths = unscaledPanes.map(\.frame.width)
        try check(leadingWidths[0] == 220 && leadingWidths.reduce(0, +) > 1190, "At 1x the leading degenerate pair overruns too")
        let leadingOrigin = NSPoint(x: unscaledPanes[0].frame.maxX + 5, y: 200)
        try check(unscaled.beginDividerResize(at: leadingOrigin), "The 1x leading degenerate pair admits a resize")
        unscaled.updateDividerResize(at: NSPoint(x: leadingOrigin.x + 10, y: 200), velocity: 200)
        try check(unscaledPanes[0].frame.width == 230 && unscaledPanes[2].frame.width == leadingWidths[2]
                  && unscaledPanes[2].frame.maxX == 1210,
                  "At 1x the first divider moves its pair and the last pane keeps its size")
        unscaled.finishDividerResize(commit: true)
        try check(unscaledPanes[2].frame.width == leadingWidths[2], "The 1x leading commit keeps the last pane's size")
        unscaled.removeFromSuperview()
        commandWindow.testScale = 2
        let live = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        commandWindow.contentView!.addSubview(live)
        let first = NSView(), second = NSView()
        live.addArrangedSubview(first)
        live.configure(orientation: .horizontal, factors: [1])
        let firstWidth = first.frame.width
        let inserted = live.reconcileArrangedSubviews([first, second])
        try check(inserted.isEmpty && live.arrangedSubviews.count == 2
                  && live.arrangedSubviews[0] === first && live.arrangedSubviews[1] === second
                  && first.superview === live,
                  "Adding a pane keeps the original child in the same hierarchy")
        live.configure(orientation: .horizontal, factors: [1, 1])
        try check(first.superview === live && first.frame.width < firstWidth && first.frame.width > 0,
                  "The original pane resizes in place")
        final class HostedPage: NSView {
            let inner = NSView()
            override func layout() {
                super.layout()
                if inner.superview !== self { addSubview(inner) }
                inner.frame = bounds
            }
        }
        let hosted = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        commandWindow.contentView!.addSubview(hosted)
        let hostedPane = HostedPage()
        hosted.addArrangedSubview(hostedPane)
        hosted.configure(orientation: .horizontal, factors: [1])
        try check(hostedPane.inner.frame.size == hostedPane.frame.size && hostedPane.frame.width == 800,
                  "A hosted child that sizes in layout follows the pane in the same pass")
        hosted.addArrangedSubview(NSView())
        hosted.configure(orientation: .horizontal, factors: [1, 1])
        try check(hostedPane.inner.frame.size == hostedPane.frame.size && hostedPane.frame.width < 800,
                  "Splitting pushes the new size into the hosted child immediately")
        let reordered = live.reconcileArrangedSubviews([second, first])
        try check(reordered.isEmpty && live.arrangedSubviews[0] === second && first.superview === live,
                  "Reorder does not park surviving panes")
        let departed = live.reconcileArrangedSubviews([first])
        try check(departed.count == 1 && departed[0] === second && first.superview === live,
                  "Only the departing pane leaves the arranged list")
        try check(second.superview === live && second.frame.width > 0,
                  "A departing pane stays on screen where it was until its owner parks it")
        let heldWidth = second.frame.width, heldHeight = second.frame.height, areaWidth = live.bounds.width
        second.autoresizingMask = [.width, .height, .minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        live.setFrameSize(NSSize(width: live.frame.width + 200, height: live.frame.height + 100))
        try check(abs(second.frame.width - (heldWidth + 200 * heldWidth / areaWidth)) < 1 && second.frame.height > heldHeight,
                  "A pane held outside the arrangement follows the page area's size by its share")
        second.autoresizingMask = []
        let released = second.frame
        live.setFrameSize(NSSize(width: live.frame.width - 200, height: live.frame.height - 100))
        try check(second.frame == released, "A released pane keeps its frame until it is parked")
        print("PASS: \(count) original native divider/store checks (no browser)")
    }
}
