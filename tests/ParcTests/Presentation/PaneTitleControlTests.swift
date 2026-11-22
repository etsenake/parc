import AppKit
import Testing
@testable import Parc
@testable import ParcSettings

@MainActor struct PaneTitleControlTests {
    private let url = URL(string: "https://sub.example.test:8443/a%20b?q=%2F#part")!
    private var address: BrowserToolbarAddress { BrowserToolbarAddress(url: url, full: true) }

    private func title(width: CGFloat = 420, appearance: NSAppearance.Name? = nil) -> (PaneTitleControl, NSTextField) {
        _ = NSApplication.shared
        let control = PaneTitleControl(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        if let appearance { control.appearance = NSAppearance(named: appearance) }
        control.update(address)
        control.place(in: NSRect(x: 0, y: 0, width: width, height: 28))
        control.layoutSubtreeIfNeeded()
        let label = control.subviews.compactMap { $0 as? NSTextField }.first!
        return (control, label)
    }

    private func completeWidth() -> CGFloat {
        let (_, label) = title()
        return label.attributedStringValue.size().width
    }

    private func hosted(_ control: PaneTitleControl) -> SidebarTestWindow {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 100))
        let window = sidebarTestWindow(containing: host, deferred: false)
        host.addSubview(control)
        control.updateTrackingAreas()
        return window
    }

    private func hoverControl(center: NotificationCenter = NotificationCenter())
        -> (PaneTitleControl, SidebarTestWindow, CALayer, NotificationCenter) {
        _ = NSApplication.shared
        let control = PaneTitleControl(frame: .zero, displayOptionsCenter: center)
        control.updateTitle("Short title")
        control.place(in: NSRect(x: 0, y: 0, width: 420, height: 28))
        let window = hosted(control)
        control.layoutSubtreeIfNeeded()
        control.updateTrackingAreas()
        control.reducesMotion = { false }
        return (control, window, control.layer!.sublayers!.first!, center)
    }

    private func trackingEvent(_ control: PaneTitleControl) -> SidebarAreaEvent {
        let event = SidebarAreaEvent()
        event.area = control.trackingAreas.first { $0.owner === control && !$0.options.contains(.cursorUpdate) }
        return event
    }


    @Test func theLabelIsDrawnOnceAndHeldCentered() {
        let (_, label) = title()
        #expect(label.layerContentsRedrawPolicy == .beforeViewResize)
        #expect(label.layerContentsPlacement == .center)
    }

    @Test func theLabelRendersTheDomainInMediumAndTheSuffixInRegularThirteenPointType() throws {
        let (_, label) = title()
        let text = label.attributedStringValue
        let primary = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let suffix = try #require(text.attribute(.font, at: (address.primary as NSString).length, effectiveRange: nil) as? NSFont)
        #expect(text.string == address.title)
        #expect(primary.pointSize == 13 && suffix.pointSize == 13)
        #expect(primary != suffix)
    }

    @Test func theGlyphsKeepSixPointsOfPaddingWithoutDoublingTheCellInset() throws {
        let (control, label) = title()
        let text = label.attributedStringValue
        let cell = try #require(label.cell)
        let inset = (cell.cellSize.width - text.size().width) / 2
        #expect(label.frame.minX + inset == 6)
        #expect(label.frame.maxX - inset == control.bounds.maxX - 6)
        #expect(label.frame.minY == 4 && label.frame.maxY == control.bounds.maxY - 4)
        #expect(cell.cellSize.width <= label.frame.width)
        #expect(label.lineBreakMode == .byTruncatingTail)
    }

    @Test func onlyTheButtonIsAnAccessibilityElementAndTheLabelNeverTakesClicks() {
        let (control, label) = title()
        #expect(control.accessibilityChildren()?.isEmpty == true)
        #expect(!label.isAccessibilityElement())
        #expect(label.hitTest(.zero) == nil)
        #expect(control.accessibilityLabel() == "Address: " + url.absoluteString)
    }

    @Test(arguments: [(NSAppearance.Name.aqua, CGFloat(0.6), CGFloat(0)), (.darkAqua, 0.75, 1)])
    func theInkFollowsTheAppearanceWithALighterSuffix(example: (NSAppearance.Name, CGFloat, CGFloat)) throws {
        let (_, label) = title(appearance: example.0)
        let text = label.attributedStringValue
        let primary = try #require(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let suffix = try #require(text.attribute(.foregroundColor, at: (address.primary as NSString).length,
                                                 effectiveRange: nil) as? NSColor)
        #expect(abs(primary.alphaComponent - example.1) < 0.00001)
        #expect(abs(suffix.alphaComponent - example.1 * 5 / 6) < 0.00001)
        #expect(primary.usingColorSpace(.sRGB)?.redComponent == example.2)
    }

    @Test func theCompleteAddressFitsExactlyAtItsMeasuredThreshold() {
        let width = completeWidth() + 26
        let (control, label) = title()
        let slot = NSRect(x: 17, y: 3, width: width, height: 28)
        control.place(in: slot)
        control.layoutSubtreeIfNeeded()
        #expect(label.stringValue == address.title)
        #expect(abs(control.frame.midX - slot.midX) < 0.00001)
        #expect(control.frame.width < slot.width)
    }

    @Test func aRelayoutKeepsTheFitTheParentAllocated() {
        let width = completeWidth() + 26
        let (control, label) = title()
        control.place(in: NSRect(x: 17, y: 3, width: width, height: 28))
        control.viewDidChangeEffectiveAppearance()
        control.needsLayout = true
        control.layoutSubtreeIfNeeded()
        #expect(label.stringValue == address.title)
    }

    @Test func justBelowTheThresholdTheSuffixIsDroppedAndStaysDropped() {
        let width = completeWidth() + 26
        let (control, label) = title()
        control.place(in: NSRect(x: 17, y: 3, width: width - 0.01, height: 28))
        control.layoutSubtreeIfNeeded()
        #expect(label.stringValue == address.primary)
        #expect(label.lineBreakMode == .byTruncatingHead)
        control.needsLayout = true
        control.layoutSubtreeIfNeeded()
        #expect(label.stringValue == address.primary)
    }

    @Test func eachAddressMeasuresItsOwnFitInTheSameAllocation() throws {
        let width = completeWidth() + 26
        let (control, label) = title()
        control.place(in: NSRect(x: 17, y: 3, width: width - 0.01, height: 28))
        let replacement = BrowserToolbarAddress(url: URL(string: "https://short.test/p"), full: true)
        control.update(replacement)
        control.layoutSubtreeIfNeeded()
        #expect(label.stringValue == replacement.title)
        control.update(address)
        control.layoutSubtreeIfNeeded()
        #expect(label.stringValue == address.primary)
        #expect(control.toolTip == url.absoluteString)
        #expect(control.accessibilityLabel() == "Address: " + url.absoluteString)
    }

    @Test func aDocumentKeepsItsAuthoredTitle() {
        let (control, label) = title()
        control.updateTitle("Original Note title")
        control.layoutSubtreeIfNeeded()
        #expect(label.stringValue == "Original Note title")
        #expect(label.lineBreakMode == .byTruncatingTail)
    }

    @Test func clickingTheTitleRunsItsActionOnceAndNotWhileDisabled() {
        let (control, _) = title()
        var actions = 0
        control.actionBlock = { actions += 1 }
        control.sendClick()
        #expect(actions == 1)
        control.isEnabled = false
        control.sendClick()
        #expect(actions == 1)
    }

    @Test func aShortTitleHugsItsTextInsideItsAllocation() throws {
        let (control, label) = title()
        control.updateTitle("Short title")
        control.place(in: NSRect(x: 0, y: 0, width: 420, height: 28))
        control.layoutSubtreeIfNeeded()
        #expect(control.frame.width < 200 && control.frame.midX == 210 && control.frame.midY == 14)
        #expect(try #require(label.cell).cellSize.width <= label.frame.width)
    }

    @Test func outsideAnAnimationGroupTheSurfaceFollowsWithoutMotion() {
        let (control, window, surface, _) = hoverControl()
        control.place(in: NSRect(x: 0, y: 0, width: 300, height: 28))
        control.layoutSubtreeIfNeeded()
        #expect(surface.frame == control.bounds)
        #expect(surface.animation(forKey: "bounds") == nil && surface.animation(forKey: "position") == nil)
        window.close()
    }

    @Test func insideAnAnimationGroupTheSurfaceTakesTheGroupsTiming() {
        let (control, window, surface, _) = hoverControl()
        control.place(in: NSRect(x: 0, y: 0, width: 300, height: 28))
        control.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        control.updateTitle("A longer original title for the group")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.allowsImplicitAnimation = true
            control.place(in: NSRect(x: 0, y: 0, width: 420, height: 28))
            control.layoutSubtreeIfNeeded()
            #expect(surface.frame == control.bounds)
            #expect(abs((surface.animation(forKey: "bounds")?.duration ?? 0) - 0.08) < 0.00001)
        }
        surface.removeAllAnimations()
        window.close()
    }

    @Test func rightClickAsksTheOwnerForAFreshMenuOnlyWhenEnabledInTheKeyWindow() {
        let (control, window, _, _) = hoverControl()
        let menu = NSMenu()
        var requests = 0
        control.menuProvider = { requests += 1; return menu }
        #expect(control.titleMenu() === menu && requests == 1)
        control.isEnabled = false
        #expect(control.titleMenu() == nil)
        control.isEnabled = true
        window.key = false
        #expect(control.titleMenu() == nil)
        #expect(requests == 1)
        window.close()
    }

    @Test func aRetiredTrackingAreaCannotStartOrClearHover() {
        let (control, window, _, _) = hoverControl()
        let old = trackingEvent(control)
        control.updateTrackingAreas()
        control.mouseEntered(with: old)
        #expect(!control.isHovered)
        control.mouseEntered(with: trackingEvent(control))
        control.mouseExited(with: old)
        #expect(control.isHovered)
        window.close()
    }

    @Test func reduceMotionShowsTheHoverSurfaceWithoutAFade() {
        let (control, window, surface, _) = hoverControl()
        control.reducesMotion = { true }
        control.mouseEntered(with: trackingEvent(control))
        #expect(control.isHovered && surface.opacity > 0)
        #expect(surface.animation(forKey: "pane-title-opacity") == nil)
        window.close()
    }

    @Test func hoverAndPressShowTheLightSurfaceWithTheirOwnDurations() throws {
        let (control, window, surface, _) = hoverControl()
        control.appearance = NSAppearance(named: .aqua)
        control.viewDidChangeEffectiveAppearance()
        control.mouseEntered(with: trackingEvent(control))
        #expect(control.isHovered && abs(surface.opacity - 0.07) < 0.00001)
        #expect(abs((surface.animation(forKey: "pane-title-opacity")?.duration ?? 0) - 0.18) < 0.00001)
        let cell = try #require(control.cell)
        cell.highlight(true, withFrame: control.bounds, in: control)
        #expect(control.isPressed && abs(surface.opacity - 0.11) < 0.00001)
        #expect(abs((surface.animation(forKey: "pane-title-opacity")?.duration ?? 0) - 0.16) < 0.00001)
        window.close()
    }

    @Test func aDarkPressReleasesToTheDarkHoverSurface() throws {
        let (control, window, surface, _) = hoverControl()
        control.mouseEntered(with: trackingEvent(control))
        let cell = try #require(control.cell)
        cell.highlight(true, withFrame: control.bounds, in: control)
        control.appearance = NSAppearance(named: .darkAqua)
        control.viewDidChangeEffectiveAppearance()
        #expect(abs(surface.opacity - 0.15) < 0.00001)
        cell.highlight(false, withFrame: control.bounds, in: control)
        #expect(abs(surface.opacity - 0.11) < 0.00001)
        window.close()
    }

    @Test func losingKeyRetiresHoverPressAndMotion() throws {
        let (control, window, surface, _) = hoverControl()
        let event = trackingEvent(control)
        control.mouseEntered(with: event)
        try #require(control.cell).highlight(true, withFrame: control.bounds, in: control)
        window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        control.mouseEntered(with: event)
        #expect(!control.isHovered && !control.isPressed)
        #expect(surface.animationKeys()?.isEmpty != false)
        window.close()
    }

    @Test func regainingKeySamplesThePointerOverTheTitle() {
        let (control, window, _, _) = hoverControl()
        window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        window.pointer = control.convert(NSPoint(x: 12, y: 12), to: nil)
        window.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(control.isHovered)
        window.close()
    }

    @Test func hidingTheTitleRetiresItsHover() {
        let (control, window, surface, _) = hoverControl()
        let event = trackingEvent(control)
        control.mouseEntered(with: event)
        control.isHidden = true
        control.viewDidHide()
        control.mouseEntered(with: event)
        #expect(!control.isHovered)
        #expect(surface.animationKeys()?.isEmpty != false)
        window.close()
    }

    @Test func aDisplayOptionChangeRemovesTheRunningHoverFade() {
        let (control, window, surface, center) = hoverControl()
        control.mouseEntered(with: trackingEvent(control))
        center.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(surface.animationKeys()?.isEmpty != false)
        #expect(control.isHovered)
        window.close()
    }

    @Test func aDetachedTitleRevokesItsTrackingArea() {
        let (control, window, _, _) = hoverControl()
        let event = trackingEvent(control)
        control.removeFromSuperview()
        control.mouseEntered(with: event)
        #expect(!control.isHovered)
        #expect(control.trackingAreas.filter { $0.owner === control && !$0.options.contains(.cursorUpdate) }.isEmpty)
        window.close()
    }

    @Test func itsObserversDoNotKeepARetiredTitleAlive() {
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 100))
        let window = sidebarTestWindow(containing: host)
        weak var retired: PaneTitleControl?
        autoreleasepool {
            let temporary = PaneTitleControl(frame: .zero)
            retired = temporary
            host.addSubview(temporary)
            temporary.removeFromSuperview()
        }
        #expect(retired == nil)
        window.close()
    }
}

struct PaneTitleLayoutTests {
    @Test(arguments: [CGFloat(160), 220, 250, 300, 480, 800])
    func aCompactTitleCentersInThePaneClearOfEssentialControls(width: CGFloat) {
        let rect = NSRect(x: 11, y: 4, width: width, height: 24)
        let slot = PaneTitleLayout.slot(in: rect, leftEssential: 11, rightEssential: rect.maxX - 64,
                                        requiredLeft: rect.minX + 13, requiredRight: rect.maxX - 68, balancesCopy: false)
        #expect(slot.midX == rect.midX)
        #expect(slot.maxX <= rect.maxX - 68)
    }

    @Test func theStackReservesTheLargerEdgeOnBothSidesAndTwoBalancingSlots() {
        let slot = PaneTitleLayout.slot(in: NSRect(x: 10, y: 2, width: 600, height: 28), leftEssential: 100,
                                        rightEssential: 550, requiredLeft: 68, requiredRight: 550, balancesCopy: true)
        #expect(slot.midX == 310 && slot.width == 378)
    }

    @Test func theHundredAndFiftyPointFloorAppliesToTheWholeStack() {
        let slot = PaneTitleLayout.slot(in: NSRect(x: 0, y: 0, width: 250, height: 28), leftEssential: 120,
                                        rightEssential: 230, requiredLeft: 50, requiredRight: 230, balancesCopy: true)
        #expect(slot.width == 112)
    }

    @Test func invalidGeometryGivesNoTitleRegion() {
        #expect(PaneTitleLayout.slot(in: NSRect(x: 0, y: 0, width: CGFloat.nan, height: 28), leftEssential: 0,
                                     rightEssential: 20, requiredLeft: 0, requiredRight: 20, balancesCopy: true) == .zero)
    }
}

struct PaneShareMenuTests {
    @MainActor private func service(_ performed: @escaping () -> Void = {}) -> NSSharingService {
        NSSharingService(title: "Test Service", image: NSImage(size: NSSize(width: 16, height: 16)),
                         alternateImage: nil, handler: performed)
    }

    @Test @MainActor func shareAsksForServicesForThePageURLAndKeepsAPlainTitle() throws {
        _ = NSApplication.shared
        let url = try #require(URL(string: "https://example.test/page"))
        var requested: [URL] = []
        let item = PaneShareMenu.item(for: url) { requested.append(contentsOf: $0); return [service()] }
        #expect(requested == [url])
        #expect(item.title == "Share" && item.image == nil)
        let entry = try #require(item.submenu?.items.first)
        #expect(item.submenu?.items.count == 1)
        #expect(entry.title == "Test Service" && entry.image != nil)
    }

    @Test @MainActor func onMacOS27EachServiceShowsItsImage() throws {
        _ = NSApplication.shared
        guard #available(macOS 27, *) else { return }
        let url = try #require(URL(string: "https://example.test/page"))
        let item = PaneShareMenu.item(for: url) { _ in [service()] }
        let submenu = try #require(item.submenu)
        let entry = try #require(submenu.items.first)
        let hidden = NSMenu()
        hidden.addItem(withTitle: entry.title, action: nil, keyEquivalent: "")
        hidden.items[0].image = entry.image
        #expect(entry.preferredImageVisibility == .visible)
        #expect(submenu.size.width > hidden.size.width)
    }

    @Test @MainActor func choosingAServicePerformsItOnce() throws {
        _ = NSApplication.shared
        let url = try #require(URL(string: "https://example.test/page"))
        var performed = 0
        let item = PaneShareMenu.item(for: url) { _ in [service { performed += 1 }] }
        let entry = try #require(item.submenu?.items.first)
        let target = try #require(entry.target)
        let action = try #require(entry.action)
        _ = (target as AnyObject).perform(action)
        #expect(performed == 1)
    }

    @Test @MainActor func noServicesLeaveShareWithoutASubmenu() throws {
        _ = NSApplication.shared
        let url = try #require(URL(string: "https://example.test/page"))
        #expect(PaneShareMenu.item(for: url) { _ in [] }.submenu == nil)
    }

    @Test @MainActor func noURLsGiveNoShareMenu() {
        _ = NSApplication.shared
        #expect(PaneShareMenu.menu(for: []) { _ in
            Issue.record("Requested services with no links")
            return []
        } == nil)
    }
}

struct PaneContentKindTests {
    @Test(arguments: [
        (true, Optional("parc://note/x"), true, PaneMenuContent.web),
        (false, Optional("https://example.test/"), false, .web),
        (false, Optional("parc://note/x"), true, .document),
        (false, Optional("about:blank"), false, .none),
        (false, Optional(""), false, .none),
        (false, nil, false, .none),
    ])
    func theMenuOffersActionsForTheContentKind(example: (Bool, String?, Bool, PaneMenuContent)) {
        #expect(PaneMenuContent(livePage: example.0, tabURL: example.1, localDocument: example.2) == example.3)
    }

    @Test(arguments: [(PaneSurface.page, true, true), (.failure, true, true), (.local, true, false),
                      (.page, false, false), (.failure, false, false)])
    func onlyALivePageOrItsFailureKeepsTheWebBar(example: (PaneSurface, Bool, Bool)) {
        #expect(example.0.usesPageBar(pageLive: example.1) == example.2)
    }
}
