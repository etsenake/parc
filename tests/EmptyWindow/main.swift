import AppKit

@MainActor @main struct EmptyWindowTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("EmptyWindow: \(message)") }
    }

    static func main() {
        presentationRule()
        pendingPanePredicate()
        hoverHandOff()
        placeholderBacking()
        shadowImage()
        pageCardShadowView()
        splitBackingAndShadows()
        print("EmptyWindow: \(count) assertions passed")
    }

    static func presentationRule() {
        typealias Rule = PendingSplitPaneSidebarRule
        for requested in [SidebarPresentation.locked, .floating, .hidden] {
            check(Rule.presentation(for: requested, pendingPane: false) == requested, "without a pending pane \(requested) presents as asked")
        }
        check(Rule.presentation(for: .hidden, pendingPane: true) == .floating, "hiding while a pane is pending floats the sidebar")
        check(Rule.presentation(for: .locked, pendingPane: true) == .locked, "⌘S still locks a floating sidebar while a pane is pending")
        check(Rule.presentation(for: .floating, pendingPane: true) == .floating, "a reveal while a pane is pending floats")
        check(Rule.refresh(.hidden, pendingPane: true, heldBefore: false) == .float, "opening a pending pane floats a hidden sidebar")
        check(Rule.refresh(.hidden, pendingPane: true, heldBefore: true) == .float, "a hidden sidebar is floated again on any render while the pane is pending")
        check(Rule.refresh(.floating, pendingPane: true, heldBefore: true) == .keep, "a floating sidebar stays while the pane is pending")
        check(Rule.refresh(.locked, pendingPane: true, heldBefore: false) == .keep, "a locked sidebar is untouched")
        check(Rule.refresh(.floating, pendingPane: false, heldBefore: true) == .applyHover, "ending the pane hands the floating sidebar back to the hover rule")
        check(Rule.refresh(.floating, pendingPane: false, heldBefore: false) == .keep, "an ordinary hover-floating sidebar is not re-decided by a render")
        check(Rule.refresh(.hidden, pendingPane: false, heldBefore: true) == .keep, "a hidden sidebar stays hidden once the pane ends")
        check(Rule.refresh(.locked, pendingPane: false, heldBefore: true) == .keep, "a locked sidebar is untouched once the pane ends")
    }

    static func pendingPanePredicate() {
        typealias Rule = PendingSplitPaneSidebarRule
        func holds(pending: Bool = false, space: Bool = false, popup: Bool = false, library: Bool = false) -> Bool {
            Rule.holdsSidebar(pendingSplitPane: pending, creatingSpace: space, popup: popup, library: library)
        }
        check(!holds(), "an empty Space leaves the sidebar to Command-S")
        check(holds(pending: true), "a pending Add Split pane holds the sidebar")
        check(!holds(pending: true, library: true), "the Library is left alone")
        check(!holds(pending: true, popup: true), "a popup is left alone")
        check(!holds(pending: true, space: true), "Space creation is left alone")
        check(Rule.presentation(for: .hidden, pendingPane: holds()) == .hidden, "Command-S hides the sidebar in an empty Space")
        check(Rule.refresh(.hidden, pendingPane: holds(), heldBefore: false) == .keep, "closing the last tab leaves a hidden sidebar hidden")
        check(Rule.refresh(.locked, pendingPane: holds(), heldBefore: false) == .keep, "closing the last tab leaves a docked sidebar docked")
        check(Rule.presentation(for: .hidden, pendingPane: holds(pending: true)) == .floating, "every hide floats while the pane is pending")
        check(Rule.refresh(.floating, pendingPane: holds(), heldBefore: true) == .applyHover,
              "filling or cancelling the pane hands the floating sidebar back to the hover rule")
    }

    static func decide(stored: Bool = true, _ presentation: SidebarHoverZones.Presentation = .floating, info: SidebarHoverInfo = SidebarHoverInfo(),
                       key: Bool = true, owner: Bool = false, interaction: Bool = false) -> SidebarHoverPresentationRule.Decision {
        SidebarHoverPresentationRule.decide(stored: stored, presentation: presentation, info: info, fullscreen: false, includesTopLeft: true,
                                            isKeyWindow: key, ownerDefers: owner, interactionDefers: interaction)
    }

    static func hoverHandOff() {
        var inSidebar = SidebarHoverInfo(); inSidebar[.sidebar] = .inside
        var pressed = SidebarHoverInfo(); pressed[.window] = .inside
        let dismissals: [(String, SidebarHoverPresentationRule.Decision)] = [
            ("the pointer left", decide()),
            ("the window resigned key (all regions none)", decide(key: false)),
            ("an interaction guard outside the key window", decide(key: false, interaction: true)),
            ("a click in the window outside the sidebar", decide(info: pressed)),
        ]
        for (name, decision) in dismissals { check(decision.action == .dismiss, "\(name) dismisses a floating sidebar") }
        check(decide(.hidden, key: true).action == .keep, "no hover reveal without an activation")
        check(decide(stored: true, info: inSidebar).action == .keep, "the pointer still on the sidebar keeps it")
        check(decide(stored: true).action == .dismiss
              && PendingSplitPaneSidebarRule.presentation(for: .hidden, pendingPane: false) == .hidden, "the pointer elsewhere hides it")
    }

    static func placeholderBacking() {
        let pane = SplitPanePlaceholder(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        for (name, alpha) in [(NSAppearance.Name.aqua, 0.666), (.darkAqua, 0.1)] {
            pane.appearance = NSAppearance(named: name)
            pane.updateLayer()
            let color = pane.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB)
            check(color != nil && abs(color!.alphaComponent - alpha) < 0.001 && color!.redComponent == 1
                  && color!.greenComponent == 1 && color!.blueComponent == 1, "empty content is white at \(alpha) in \(name.rawValue)")
        }
        check(pane.subviews.isEmpty, "the empty content has no page, title or control")
        check(pane.isAccessibilityElement() && pane.accessibilityRole() == .group, "the empty content is an accessibility group")
    }

    static func alphas(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<(image.width * image.height)).map { data[$0 * 4 + 3] }
    }
    static func alpha(_ image: CGImage, _ x: Int, _ yFromTop: Int) -> UInt8 { alphas(image)[yFromTop * image.width + x] }

    static func shadowImage() {
        typealias Shadow = ContentShadowImage
        check(PageCard.cornerRadius == 6, "the page card's six-point corner")
        check(Shadow.size == 51, "10-point outset, 6-point corner and 9-point straight edge each side of one stretchable point")
        let edge: CGFloat = 25 / 51, point: CGFloat = 1 / 51
        check(Shadow.stretchableCenter == CGRect(x: edge, y: edge, width: point, height: point), "only the middle point stretches")
        check(Shadow.frame(around: CGRect(x: 220, y: 10, width: 1230, height: 820)) == CGRect(x: 210, y: 0, width: 1250, height: 840),
              "the shadow reaches 10 points beyond the card")
        guard let image = Shadow.image(scale: 2) else { return check(false, "the shadow image renders") }
        check(image.width == 102 && image.height == 102, "drawn at backing scale")
        let middle = image.width / 2, card = 20, inner = image.height - 20
        check(alpha(image, middle, middle) == 0, "the card's interior is clear, so the shadow never darkens the page")
        check(alpha(image, middle, card + 4) == 0 && alpha(image, card + 4, middle) == 0, "no shadow inside the card's edges")
        let below = alpha(image, middle, inner + 1), above = alpha(image, middle, card - 2)
        check(below > above && above > 0, "the shadow falls 1 point down: \(below) below against \(above) above")
        check(alpha(image, middle, inner + 1) <= 64, "at most 0.25 black at the edge")
        check(alpha(image, 0, 0) == 0 && alpha(image, middle, image.height - 1) == 0, "the blur fades out inside the outset")
        let scale: CGFloat = 8
        guard let fine = Shadow.image(scale: scale) else { return check(false, "the shadow image renders at 8×") }
        let mask = CGContext(data: nil, width: fine.width, height: fine.height, bitsPerComponent: 8, bytesPerRow: fine.width,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        mask.scaleBy(x: scale, y: scale); mask.translateBy(x: Shadow.outset, y: Shadow.outset)
        let shape = CALayer()
        shape.bounds = CGRect(x: 0, y: 0, width: Shadow.size - 2 * Shadow.outset, height: Shadow.size - 2 * Shadow.outset)
        shape.backgroundColor = CGColor(gray: 1, alpha: 1); shape.cornerRadius = 6; shape.cornerCurve = .continuous
        shape.render(in: mask)
        let covered = mask.data!.assumingMemoryBound(to: UInt8.self), pixels = alphas(fine)
        let shadowedInside = (0..<pixels.count).filter { covered[$0] == 255 && pixels[$0] != 0 }.count
        check(shadowedInside == 0, "every pixel inside the card's continuous corner is clear (\(shadowedInside) are not)")
    }

    static func pageCardShadowView() {
        let view = PageCardShadowView()
        view.place(around: NSRect(x: 220, y: 10, width: 1230, height: 820))
        check(view.frame == NSRect(x: 210, y: 0, width: 1250, height: 840), "placed around the page host")
        check(view.hitTest(NSPoint(x: 600, y: 400)) == nil && view.hitTest(NSPoint(x: 215, y: 5)) == nil, "it never takes a click")
        check(!view.isAccessibilityElement() && (view.accessibilityChildren() ?? []).isEmpty, "it is not in accessibility")
        check(view.layerContentsRedrawPolicy == .onSetNeedsDisplay, "a resize stretches it without redrawing")
        view.updateLayer()
        check(view.layer?.contents != nil && view.layer?.contentsCenter == ContentShadowImage.stretchableCenter,
              "its layer shows the stretchable shadow")
    }

    static func shadows(_ split: ParcSplitView) -> [CALayer] {
        (split.layer?.sublayers ?? []).filter { $0.name == "Split pane shadow" }
    }

    static func splitBackingAndShadows() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1230, height: 820))
        host.wantsLayer = true
        let split = ParcSplitView()
        host.addSubview(split); split.constrain(to: host)
        let first = NSView(), second = NSView()
        split.configure(orientation: .horizontal, factors: [1])
        split.reconcileArrangedSubviews([first])
        host.layoutSubtreeIfNeeded(); split.adjustSubviews()
        split.configureBacking(in: host, hasTranslucentPane: true)
        check(host.layer?.masksToBounds == true && host.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.alphaComponent == 0,
              "a lone empty content shows through a clear, clipping host")
        check(first.layer?.cornerRadius == 0 && first.layer?.masksToBounds == false, "the host clips a lone pane")
        check(shadows(split).count == 1 && shadows(split).allSatisfy(\.isHidden), "a lone pane's split shadow waits hidden")
        split.configureBacking(in: host, hasTranslucentPane: false)
        check(host.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.alphaComponent == 1, "a lone page keeps the white host")

        split.configure(orientation: .horizontal, factors: [0.5, 0.5])
        split.reconcileArrangedSubviews([first, second])
        split.adjustSubviews()
        split.configureBacking(in: host, hasTranslucentPane: false)
        check(host.layer?.masksToBounds == false, "a divided split is unclipped so each card's shadow shows")
        check([first, second].allSatisfy { $0.layer?.cornerRadius == 6 && $0.layer?.masksToBounds == true }, "each divided pane clips itself")
        let layers = shadows(split)
        check(layers.count == 2 && layers.allSatisfy { !$0.isHidden && $0.zPosition < 0 && $0.contents != nil }, "each pane has a visible shadow below it")
        for pane in [first, second] {
            check(layers.contains { $0.frame == ContentShadowImage.frame(around: pane.frame) }, "a shadow surrounds \(pane.frame)")
        }
        split.reconcileArrangedSubviews([second])
        split.adjustSubviews()
        check(shadows(split).count == 1 && shadows(split).allSatisfy(\.isHidden), "a departing pane takes its shadow; the lone one hides")
        split.reconcileArrangedSubviews([])
        split.adjustSubviews()
        check(shadows(split).isEmpty, "an empty split keeps no shadow")
        stackedInFlippedHost()
    }

    final class FlippedHost: NSView { override var isFlipped: Bool { true } }

    static func stackedInFlippedHost() {
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        host.wantsLayer = true
        let split = ParcSplitView()
        host.addSubview(split); split.constrain(to: host)
        let top = NSView(), bottom = NSView()
        split.configure(orientation: .vertical, factors: [0.3, 0.7])
        split.reconcileArrangedSubviews([top, bottom])
        split.configureBacking(in: host, hasTranslucentPane: false)
        host.layoutSubtreeIfNeeded(); split.adjustSubviews()
        check(top.frame.height < bottom.frame.height && top.frame.minY < bottom.frame.minY, "stacked panes of unequal height")
        let layers = shadows(split)
        for pane in [top, bottom] {
            guard let paneLayer = pane.layer else { return check(false, "the pane is layer-backed") }
            check(layers.contains { $0.frame == ContentShadowImage.frame(around: paneLayer.frame) },
                  "a shadow surrounds the pane's layer at \(paneLayer.frame) (split layer flipped: \(split.layer?.isGeometryFlipped == true))")
        }
    }
}
