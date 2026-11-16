import AppKit

@MainActor @main struct EmptyWindowTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("EmptyWindow: \(message)") }
    }

    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        presentationRule()
        pendingPanePredicate()
        hoverHandOff()
        placeholderBacking()
        shadowImage()
        pageCardShadowView()
        splitBackingAndShadows()
        closeKeepsSpace()
        print("EmptyWindow: \(count) assertions passed")
    }

    static func page(_ space: BrowserSpace, _ kind: TabKind = .today, accessed: TimeInterval = 0) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: "https://example.test/", title: "Page", kind: kind,
                   createdAt: Date(timeIntervalSince1970: 0), lastAccessed: Date(timeIntervalSince1970: accessed),
                   savedURL: "https://example.test/", savedTitle: "Page")
    }

    static func twoSpaces(_ make: (BrowserSpace) -> [BrowserTab]) -> (BrowserState, BrowserSpace, BrowserTab) {
        var state = BrowserState.initial()
        let home = state.spaces[0]
        let other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle", color: "112233", profileID: home.profileID)
        let elsewhere = page(other, accessed: 99)
        state.spaces.append(other)
        state.tabs = make(home) + [elsewhere]
        state.selectionBySpace[other.id.uuidString] = [elsewhere.id]
        return (state, home, elsewhere)
    }

    static func archived(_ state: BrowserState, _ ids: Set<UUID>) -> BrowserState {
        var next = state
        for index in next.tabs.indices where ids.contains(next.tabs[index].id) && next.tabs[index].kind == .today {
            next.tabs[index].archivedAt = Date(timeIntervalSince1970: 100)
        }
        next.selectedTabIDs.removeAll { ids.contains($0) }
        return next
    }

    static func engineSelects(_ id: UUID, in window: inout WindowPresentation, state: BrowserState, closing: Set<UUID> = []) {
        guard window.admitsEngineSelection(of: id, closing: { closing.contains($0) }) else { return }
        _ = window.selectExistingTab(id, state: state, available: { _ in true })
    }

    static func decide(_ removing: Set<UUID>, _ window: WindowPresentation, _ state: BrowserState) -> FolderRemovalSelection? {
        let space = state.spaces.first { $0.id == window.activeSpaceID }!
        return FolderRemovalSelection.resolve(removing: removing, spaceID: space.id, profileID: space.profileID, state: state,
            selected: window.selectedTabIDs, focused: window.preferredFocusedTabID, referrerPool: window.referrerPool,
            previouslySelectedItemID: window.previouslySelectedItemID, available: { _ in true })
    }

    static func singleSpaceUnchanged() {
        var only = BrowserState.initial()
        let space = only.spaces[0], lone = page(space), favorite = page(space, .favorite, accessed: 99)
        only.tabs = [lone, favorite]
        only.selectedTabIDs = [lone.id]
        var single = WindowPresentation(state: only, ready: true)
        guard let alone = decide([lone.id], single, only) else { return check(false, "a single Space's last close resolves") }
        check(alone.tabIDs.isEmpty && alone.replacementSpaceID == space.id, "a single Space empties when its last tab closes")
        single.closePage(lone.id)
        engineSelects(favorite.id, in: &single, state: only)
        let emptied = archived(only, [lone.id])
        check(single.finishFolderRemoval(alone, state: emptied, available: { _ in true })
              && single.activeSpaceID == space.id && single.selectedTabIDs.isEmpty,
              "a single Space is unchanged: its last close still shows the start page, not a Favorite the engine picks")
    }

    static func closeKeepsSpace() {
        var last: BrowserTab!
        var (state, home, elsewhere) = twoSpaces { home in last = page(home); return [last] }
        state.selectedTabIDs = [last.id]
        var window = WindowPresentation(state: state, ready: true)
        guard let decision = decide([last.id], window, state) else { return check(false, "the last tab's close resolves") }
        check(decision.tabIDs.isEmpty && decision.replacementSpaceID == home.id, "closing the last tab empties its own Space")
        engineSelects(elsewhere.id, in: &window, state: state, closing: [last.id])
        check(window.activeSpaceID == home.id && window.selectedTabIDs == [last.id],
              "the current Space is kept and a second Space isn't selected while the last tab is closing")
        singleSpaceUnchanged()
        window.closePage(last.id)
        engineSelects(elsewhere.id, in: &window, state: state)
        check(!window.selectedTabIDs.contains(elsewhere.id), "a second Space isn't selected after the last tab closes")
        check(window.activeSpaceID == home.id, "the current Space is kept when the engine picks a page in a second Space")
        var landed = archived(state, [last.id])
        window.reconcile(landed) { _ in true }
        check(window.finishFolderRemoval(decision, state: landed, available: { _ in true })
              && window.activeSpaceID == home.id && window.selectedTabIDs.isEmpty,
              "the close lands on the current Space's start page")
        check(!window.admitsEngineSelection(of: elsewhere.id, closing: { _ in false }), "the engine's pick stays refused until the window pushes its own choice")
        window.engineSelectionSynchronized()
        check(window.admitsEngineSelection(of: elsewhere.id, closing: { _ in false }), "once the window pushed its choice a page asking for focus is followed again")
        guard let undo = ClosedTabsUndo(prompt: .archive, ids: [last.id], spaceID: home.id, profileID: home.profileID,
                                        focusedTabID: last.id, before: state, after: landed),
              let restored = undo.restoring(landed) else { return check(false, "the closed tab has an Undo") }
        landed = restored
        check(window.finishClosedTabsUndo(undo, state: landed, available: { _ in true })
              && window.activeSpaceID == home.id && window.selectedTabIDs == [last.id], "Undo brings the tab back into the same Space")

        var left: BrowserTab!, right: BrowserTab!
        var (split, _, splitElsewhere) = twoSpaces { home in left = page(home); right = page(home); return [left, right] }
        split.selectedTabIDs = [left.id, right.id]
        var paired = WindowPresentation(state: split, ready: true)
        paired.closePage(left.id)
        check(paired.admitsEngineSelection(of: right.id, closing: { _ in false })
              && !paired.admitsEngineSelection(of: splitElsewhere.id, closing: { _ in false }),
              "an engine pick of the pane still on screen is followed as before, while a second Space's page is not")

        var today: BrowserTab!, pinned: BrowserTab!
        var (withPinned, pinnedHome, pinnedElsewhere) = twoSpaces { home in
            today = page(home); pinned = page(home, .pinned); return [pinned, today]
        }
        withPinned.selectedTabIDs = [today.id]
        var pinnedWindow = WindowPresentation(state: withPinned, ready: true)
        guard let toPinned = decide([today.id], pinnedWindow, withPinned) else { return check(false, "a close beside a Pinned tab resolves") }
        check(toPinned.tabIDs == [pinned.id] && toPinned.replacementSpaceID == pinnedHome.id,
              "a Pinned tab keeps the Space from emptying, so closing the last Today tab selects it")
        pinnedWindow.closePage(today.id)
        engineSelects(pinnedElsewhere.id, in: &pinnedWindow, state: withPinned)
        withPinned = archived(withPinned, [today.id])
        check(pinnedWindow.finishFolderRemoval(toPinned, state: withPinned, available: { _ in true })
              && pinnedWindow.activeSpaceID == pinnedHome.id && pinnedWindow.selectedTabIDs == [pinned.id],
              "the Pinned tab is selected in the same Space, not the engine's pick in a second Space")

        var opened: BrowserTab!, shared: BrowserTab!
        var (withFavorite, favoriteHome, _) = twoSpaces { home in
            opened = page(home); shared = page(home, .favorite); return [shared, opened]
        }
        withFavorite.selectedTabIDs = [shared.id]
        var favoriteWindow = WindowPresentation(state: withFavorite, ready: true)
        _ = favoriteWindow.selectExistingTab(opened.id, state: withFavorite, available: { _ in true })
        favoriteWindow.recordSelectionForReturn(opened.id, state: withFavorite)
        guard let toFavorite = decide([opened.id], favoriteWindow, withFavorite) else { return check(false, "a close after a Favorite resolves") }
        check(toFavorite.tabIDs == [shared.id] && toFavorite.replacementSpaceID == favoriteHome.id,
              "closing a tab returns to the Favorite selected just before it, in the same Space")
        withFavorite = archived(withFavorite, [opened.id])
        favoriteWindow.closePage(opened.id)
        check(favoriteWindow.finishFolderRemoval(toFavorite, state: withFavorite, available: { _ in true })
              && favoriteWindow.activeSpaceID == favoriteHome.id && favoriteWindow.selectedTabIDs == [shared.id],
              "the Favorite comes back in the current Space")

        var first: BrowserTab!, second: BrowserTab!
        var (cleared, clearedHome, clearedElsewhere) = twoSpaces { home in
            first = page(home, accessed: 2); second = page(home, accessed: 1); return [first, second]
        }
        cleared.selectedTabIDs = [first.id]
        var clearing = WindowPresentation(state: cleared, ready: true)
        guard let wiped = decide([first.id, second.id], clearing, cleared) else { return check(false, "clearing Today resolves") }
        check(wiped.tabIDs.isEmpty && wiped.replacementSpaceID == clearedHome.id, "clearing Today empties the current Space")
        clearing.closePage(first.id)
        clearing.closePage(second.id)
        engineSelects(clearedElsewhere.id, in: &clearing, state: cleared)
        cleared = archived(cleared, [first.id, second.id])
        check(clearing.finishFolderRemoval(wiped, state: cleared, available: { _ in true })
              && clearing.activeSpaceID == clearedHome.id && clearing.selectedTabIDs.isEmpty,
              "clearing Today stays on the current Space instead of following the engine to a second Space")

        var closer: BrowserTab!, sibling: BrowserTab!
        var (selfClosed, selfHome, selfElsewhere) = twoSpaces { home in
            closer = page(home, accessed: 2); sibling = page(home, accessed: 1); return [closer, sibling]
        }
        selfClosed.selectedTabIDs = [closer.id]
        var closing = WindowPresentation(state: selfClosed, ready: true)
        guard let handOver = decide([closer.id], closing, selfClosed) else { return check(false, "a page closing itself resolves") }
        closing.closePage(closer.id)
        check(closing.finishFolderRemoval(handOver, state: selfClosed, available: { _ in true }),
              "a page that closed itself hands over by the close rules")
        engineSelects(selfElsewhere.id, in: &closing, state: selfClosed)
        check(closing.activeSpaceID == selfHome.id && closing.selectedTabIDs == [sibling.id],
              "a page closing itself hands over to a tab in its own Space, not the engine's pick in a second Space")
        selfClosed.tabs.removeAll { $0.id == sibling.id }
        closing = WindowPresentation(state: selfClosed, ready: true)
        guard let lastOut = decide([closer.id], closing, selfClosed) else { return check(false, "a last page closing itself resolves") }
        closing.closePage(closer.id)
        check(closing.finishFolderRemoval(lastOut, state: selfClosed, available: { _ in true })
              && closing.activeSpaceID == selfHome.id && closing.selectedTabIDs.isEmpty,
              "the last page closing itself leaves its own Space's start page")
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
