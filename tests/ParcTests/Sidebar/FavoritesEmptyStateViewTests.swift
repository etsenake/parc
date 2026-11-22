import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

private final class FocusStop: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}

@MainActor
struct FavoritesEmptyStateViewTests {
    typealias E = SidebarChromeLayout.AppTrayEmptyState
    typealias L = SidebarChromeLayout

    @MainActor private final class Tray {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-empty-state-view-\(UUID().uuidString)", isDirectory: true)
        let store: BrowserStore
        let profile: UUID
        let other: UUID
        let windows: [NSWindow]
        let views: [FavoritesEmptyStateView]

        static func window() -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 228, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            return window
        }

        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            store = try BrowserStore(directory: directory)
            profile = store.activeSpace.profileID
            other = store.createProfile(name: "Work")
            windows = [Self.window(), Self.window()]
            views = windows.map { _ in FavoritesEmptyStateView() }
            for (window, view) in zip(windows, views) { window.contentView?.addSubview(view) }
            render()
            let view = views[0]
            view.frame = NSRect(x: 0, y: 0, width: 228, height: view.fittingHeight(width: 228))
            view.layoutSubtreeIfNeeded()
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
            MainActor.assumeIsolated { windows.forEach { $0.close() } }
        }

        func render(favorites: Int = 0, profileID: UUID? = nil, noSpace: Bool = false, privateWindow: Bool = false) {
            let resolved: UUID? = noSpace ? nil : (profileID ?? profile)
            for view in views {
                view.update(favorites: favorites, profileID: resolved, settings: store.state.settings, privateWindow: privateWindow) { [weak self] in
                    self?.store.dismissFavoritesEmptyState(profileID: $0)
                }
            }
        }

        var view: FavoritesEmptyStateView { views[0] }
        var height: CGFloat { view.fittingHeight(width: 228) }
        var labels: [NSTextField] { view.subviews.compactMap { $0 as? NSTextField } }
        var title: NSTextField { labels.first { $0.stringValue == FavoritesEmptyStateView.title }! }
        var subtitle: NSTextField { labels.first { $0.stringValue == FavoritesEmptyStateView.subtitle }! }
        var button: NSButton { view.subviews.compactMap { $0 as? NSButton }.first! }
        var icon: NSImageView { view.subviews.compactMap { $0 as? NSImageView }.first! }
        func attribute(_ field: NSTextField, _ key: NSAttributedString.Key) -> Any? { field.attributedStringValue.attribute(key, at: 0, effectiveRange: nil) }
        func holdsText(_ label: NSTextField) -> Bool {
            guard let cell = label.cell else { return false }
            return cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: label.frame.width, height: .greatestFiniteMagnitude)).height <= label.frame.height
        }
    }

    @Test func theEmptyStateStrings() {
        #expect(FavoritesEmptyStateView.title == "Drag to add Favorites")
        #expect(FavoritesEmptyStateView.subtitle == "Favorites keep your most used sites and apps close")
    }

    @Test func theViewHoldsTheIconBothLabelsAndTheDismissButton() throws {
        let tray = try Tray()
        #expect(tray.view.subviews.compactMap { $0 as? NSImageView }.count == 1)
        #expect(tray.labels.count == 2)
        #expect(tray.view.subviews.compactMap { $0 as? NSButton }.count == 1)
    }

    @Test func theTitleIsThirteenPointMedium() throws {
        let tray = try Tray()
        let font = tray.attribute(tray.title, .font) as? NSFont
        #expect(font?.pointSize == 13)
        #expect(font == NSFont.systemFont(ofSize: 13, weight: .medium))
    }

    @Test func theSubtitleIsTwelvePointRegular() throws {
        let tray = try Tray()
        let font = tray.attribute(tray.subtitle, .font) as? NSFont
        #expect(font?.pointSize == 12)
        #expect(font == NSFont.systemFont(ofSize: 12, weight: .regular))
    }

    @Test func theSubtitleAloneIsKernedMinusPointTwo() throws {
        let tray = try Tray()
        #expect((tray.attribute(tray.subtitle, .kern) as? Double) == -0.2)
        #expect(tray.attribute(tray.title, .kern) == nil)
    }

    @Test func bothLabelsAreCentred() throws {
        let tray = try Tray()
        #expect([tray.title, tray.subtitle].allSatisfy { (tray.attribute($0, .paragraphStyle) as? NSParagraphStyle)?.alignment == .center })
    }

    @Test func theFittingHeightIsTheModelsAndTallerThanTheTraysMinimum() throws {
        let tray = try Tray()
        #expect(tray.height == E.height(icon: tray.icon.image?.size ?? .zero, title: tray.title.frame.size, subtitle: tray.subtitle.frame.size))
        #expect(tray.height > E.minimumHeight)
    }

    @Test func subviewsSitAtTheModelsFrames() throws {
        let tray = try Tray()
        let frames = E.frames(width: 228, height: tray.height, icon: tray.icon.image?.size ?? .zero, title: tray.title.frame.size,
                              subtitle: tray.subtitle.frame.size)
        #expect(tray.icon.frame == frames.icon)
        #expect(tray.title.frame == frames.title)
        #expect(tray.subtitle.frame == frames.subtitle)
        #expect(tray.button.frame == frames.close)
    }

    @Test func theSubtitleWrapsWithinOneHundredFiftyPoints() throws {
        let tray = try Tray()
        #expect(tray.subtitle.frame.width <= 150)
        #expect(tray.subtitle.frame.height > tray.title.frame.height * 1.5)
    }

    @Test func theIconIsASixteenPointPaletteStar() throws {
        let tray = try Tray()
        #expect(tray.icon.image?.isTemplate == false)
        #expect((tray.icon.image?.size.height ?? 0) > 12)
    }

    @Test func atTwoHundredTwentyEightTheTitleTakesOneLineAndAllTextShows() throws {
        let tray = try Tray()
        #expect(tray.holdsText(tray.title))
        #expect(tray.holdsText(tray.subtitle))
        #expect(tray.title.frame.height < 20)
    }

    @Test func accessibilityChildrenAreStarTitleSubtitleAndDismissInThatOrder() throws {
        let tray = try Tray()
        let elements = (tray.view.accessibilityChildren() ?? []).compactMap { $0 as AnyObject as? NSAccessibilityProtocol }
        let roles = elements.compactMap { $0.accessibilityRole() }
        let owners = elements.compactMap { ($0 as? NSView) ?? ($0 as? NSCell)?.controlView }
        #expect(roles == [.image, .staticText, .staticText, .button])
        #expect(owners == [tray.icon, tray.title, tray.subtitle, tray.button])
    }

    @Test func dismissHasItsLabelAndIdentifier() throws {
        let tray = try Tray()
        #expect(tray.button.accessibilityLabel() == "Dismiss")
        #expect(tray.button.accessibilityIdentifier() == "sidebarFavoritesEmptyStateDismissButton")
    }

    @Test func dismissCanTakeFocusAndDrawsAppKitsRing() throws {
        let tray = try Tray()
        #expect(tray.button.focusRingType != .none)
        #expect(!tray.button.focusRingMaskBounds.isEmpty)
        #expect(!tray.button.refusesFirstResponder)
    }

    @Test func theTrayMenuHasHide() throws {
        let tray = try Tray()
        let menuView = FavoritesEmptyStateView()
        menuView.update(favorites: 0, profileID: tray.other, settings: tray.store.state.settings, privateWindow: false) { _ in }
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: tray.windows[0].windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        #expect(menuView.menu(for: event)?.items.map(\.title) == ["Hide"])
    }

    @Test func hideCallsBackWithTheProfile() throws {
        let tray = try Tray()
        var hides: [UUID] = []
        let menuView = FavoritesEmptyStateView()
        menuView.update(favorites: 0, profileID: tray.other, settings: tray.store.state.settings, privateWindow: false) { hides.append($0) }
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: tray.windows[0].windowNumber,
                                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        if let hide = menuView.menu(for: event)?.items.first, let action = hide.action { NSApp.sendAction(action, to: hide.target, from: hide) }
        #expect(hides == [tray.other])
    }

    private func narrowed(_ tray: Tray) -> (FavoritesEmptyStateView, CGFloat, [NSTextField]) {
        let view = tray.views[1]
        let height = view.fittingHeight(width: 164)
        view.frame = NSRect(x: 0, y: 0, width: 164, height: height)
        view.layoutSubtreeIfNeeded()
        return (view, height, view.subviews.compactMap { $0 as? NSTextField })
    }

    @Test func atOneHundredSixtyFourBothLabelsWrapWithinOneHundredTwentyEightPoints() throws {
        let tray = try Tray()
        let (_, _, labels) = narrowed(tray)
        #expect(labels.count == 2)
        #expect(labels.allSatisfy(tray.holdsText))
        #expect(labels.allSatisfy { $0.frame.width <= 128 })
    }

    @Test func atOneHundredSixtyFourTheTitleTakesTwoLinesAndTheTrayGrows() throws {
        let tray = try Tray()
        let (_, height, labels) = narrowed(tray)
        #expect(labels.first { $0.stringValue == FavoritesEmptyStateView.title }.map { $0.frame.height > 16 * 1.5 } == true)
        #expect(height > tray.height)
    }

    @Test func idleIsOpaqueTitleSeventyPercentSubtitleAndDashed() throws {
        let tray = try Tray()
        let border = tray.view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
        #expect(tray.title.alphaValue == 1)
        #expect(abs(tray.subtitle.alphaValue - 0.7) < 0.001)
        #expect(border?.lineDashPattern == [5])
    }

    @Test func aDropOverTheShownViewTakesTheDraggingStyle() throws {
        let tray = try Tray()
        #expect(tray.view.showsDrop(true))
    }

    @Test func theStarIsTheSystemsStarCircleFillAtSixteenPointMedium() throws {
        let tray = try Tray()
        let star = NSImage(systemSymbolName: "star.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))?.size
        #expect(tray.icon.image?.size == star)
    }

    @Test func anUndismissedEmptyProfileShowsTheTallTray() throws {
        let tray = try Tray()
        let size = tray.icon.image?.size ?? .zero
        #expect(tray.views.allSatisfy { !$0.isHidden && $0.trayHeight(gridHeight: 0, width: 228) == tray.height })
        #expect(tray.height == 86 + size.height)
        #expect(L.tablistTop(trayHeight: tray.height) == 82 + tray.height)
    }

    @Test func favoritesGiveTheGridsTray() throws {
        let tray = try Tray()
        tray.render(favorites: 1)
        #expect(tray.views.allSatisfy { $0.isHidden && $0.trayHeight(gridHeight: 63, width: 228) == 63 })
    }

    @Test func aPrivateWindowShowsNone() throws {
        let tray = try Tray()
        tray.render(privateWindow: true)
        #expect(tray.views.allSatisfy { $0.isHidden && $0.trayHeight(gridHeight: 0, width: 228) == 0 })
    }

    @Test func noSpaceNoEmptyState() throws {
        let tray = try Tray()
        tray.render(noSpace: true)
        #expect(tray.views.allSatisfy { $0.isHidden })
    }

    @Test func aHiddenViewDrawsNoDraggingStyle() throws {
        let tray = try Tray()
        tray.render(favorites: 1)
        #expect(!tray.view.showsDrop(true))
    }

    private func dismissed(_ tray: Tray) -> FocusStop {
        let stop = FocusStop(frame: NSRect(x: 0, y: 200, width: 20, height: 20))
        tray.windows[0].contentView?.addSubview(stop)
        SidebarAccessibility.link([tray.button, stop], within: tray.windows[0].contentView!, exit: nil, bypassed: false)
        _ = tray.windows[0].makeFirstResponder(tray.button)
        tray.button.sendClick()
        tray.render()
        return stop
    }

    @Test func dismissTakesFocus() throws {
        let tray = try Tray()
        let stop = FocusStop(frame: NSRect(x: 0, y: 200, width: 20, height: 20))
        tray.windows[0].contentView?.addSubview(stop)
        SidebarAccessibility.link([tray.button, stop], within: tray.windows[0].contentView!, exit: nil, bypassed: false)
        #expect(tray.windows[0].makeFirstResponder(tray.button))
        #expect(tray.windows[0].firstResponder === tray.button)
    }

    @Test func dismissRecordsItsProfileInTheStore() throws {
        let tray = try Tray()
        _ = dismissed(tray)
        #expect(tray.store.state.settings.topAppsEmptyStateDismissedForProfiles == [tray.profile])
    }

    @Test func afterDismissEveryWindowOfTheProfileCollapsesItsTray() throws {
        let tray = try Tray()
        _ = dismissed(tray)
        #expect(tray.views.allSatisfy { $0.isHidden && $0.trayHeight(gridHeight: 0, width: 228) == 0 })
        #expect(L.tablistTop(trayHeight: tray.view.trayHeight(gridHeight: 0, width: 228)) == 87)
    }

    @Test func theNextStopTakesDismissesFocusNotTheWindow() throws {
        let tray = try Tray()
        let stop = dismissed(tray)
        #expect(tray.windows[0].firstResponder === stop)
    }

    @Test func anotherProfileKeepsItsEmptyState() throws {
        let tray = try Tray()
        _ = dismissed(tray)
        tray.render(profileID: tray.other)
        #expect(tray.views.allSatisfy { !$0.isHidden })
    }
}
