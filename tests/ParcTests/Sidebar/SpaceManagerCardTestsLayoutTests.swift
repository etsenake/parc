import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SpaceManagerCardTestsLayoutTests {
    private typealias Layout = SpaceManagerCardTestsSupport.Layout
    private typealias Cards = SpaceManagerCardTestsSupport.Cards

    @Test func theFirstCardIsTwentyFourInAndFortyEightFromTheTopAndBottom() {
        #expect(Layout.cardFrame(index: 0, height: 650) == NSRect(x: 24, y: 48, width: 240, height: 554))
    }

    @Test func cardsSitTwentyFourApart() {
        let expected: CGFloat = 552
        #expect(Layout.cardFrame(index: 2, height: 650).minX == expected)
    }

    @Test func theAddItemFollowsTheLastCardsGapCentredOnTheHeight() {
        #expect(Layout.addItemFrame(count: 3, height: 650) == NSRect(x: 24 + 3 * 264, y: 301, width: 48, height: 48))
    }

    @Test func theAddCircleIsCentredInItsItem() {
        #expect(Layout.addCircleFrame(count: 3, height: 650) == NSRect(x: 24 + 3 * 264 + 9, y: 310, width: 30, height: 30))
    }

    @Test func theCollectionEndsTwentyFourAfterTheAddItem() {
        let expected: CGFloat = 888
        #expect(Layout.contentWidth(count: 3) == expected)
    }

    @Test func theSidebarSitsFiveBelowTheTopAndFortyFourAboveTheBottom() {
        #expect(Layout.sidebarFrame(in: NSRect(x: 0, y: 0, width: 240, height: 554)) == NSRect(x: 0, y: 5, width: 240, height: 505))
    }

    @Test func theControlsAreThirtyFourPointsAndFiveAboveTheBottom() {
        #expect(Layout.controlsFrame(in: NSRect(x: 0, y: 0, width: 240, height: 554)) == NSRect(x: 0, y: 515, width: 240, height: 34))
    }

    @Test func aSingleUnnamedSpacesCardHidesItsHeader() {
        #expect(Cards().header.isHidden)
    }

    @Test func theInertCardListAcceptsFocusBeforeRenaming() {
        let cards = Cards()
        #expect(cards.window.makeFirstResponder(cards.sidebar))
    }

    @Test func renamingRevealsTheOtherwiseHiddenHeader() {
        let cards = Cards()
        _ = cards.window.makeFirstResponder(cards.sidebar)
        #expect(cards.sidebar.beginSpaceNameEditing(cards.first) { _ in })
        #expect(!cards.header.isHidden)
    }

    @Test func theRevealedHeaderSitsItsPaddingBelowTheTopWithTheListAfterIt() {
        let cards = Cards()
        _ = cards.window.makeFirstResponder(cards.sidebar)
        _ = cards.sidebar.beginSpaceNameEditing(cards.first) { _ in }
        let list = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first!.enclosingScrollView!
        #expect(list.frame.minY == cards.header.frame.maxY)
        #expect(cards.header.frame.minY == SidebarChromeLayout.SpaceHeader.topPadding)
    }

    @Test func cancellingTheRenameHidesTheHeaderAgainWithoutACatalogChange() {
        let cards = Cards()
        _ = cards.window.makeFirstResponder(cards.sidebar)
        _ = cards.sidebar.beginSpaceNameEditing(cards.first) { _ in }
        cards.sidebar.cancelSpaceNameEditing()
        cards.sidebar.layoutSubtreeIfNeeded()
        let list = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.first!.enclosingScrollView!
        #expect(cards.header.isHidden)
        #expect(list.frame.minY == 0)
    }

    @Test func aCardPaintsItsThemeWithoutTheBehindWindowMaterial() {
        let cards = Cards()
        let theme = cards.sidebar.superview as! ThemeRendererView
        #expect(!theme.drawsMaterial)
    }

    @Test func theActualCardUsesTheRecoveredFrame() {
        let cards = Cards()
        #expect(cards.card.frame == Layout.cardFrame(index: 0, height: cards.manager.bounds.height))
    }

    @Test func theActualSidebarUsesTheCardsSidebarInset() {
        let cards = Cards()
        #expect(cards.sidebar.frame == Layout.sidebarFrame(in: cards.card.bounds))
    }

    @Test func theMoveHandleIsATwentyEightPointLeadingControl() {
        let cards = Cards()
        let grip = sidebarDescendants(cards.card).first { $0.parcTooltip?.label == "Drag to Reorder Space" }
        let controls = Layout.controlsFrame(in: cards.card.bounds)
        #expect(grip?.frame == NSRect(x: 8, y: controls.midY - 14, width: 28, height: 28))
    }

    @Test func moreOptionsIsATwentyEightPointTrailingControlKeepingItsAccessibleName() {
        let cards = Cards()
        let more = sidebarDescendants(cards.card).compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More options" }
        let controls = Layout.controlsFrame(in: cards.card.bounds)
        #expect(more?.frame == NSRect(x: 240 - 36, y: controls.midY - 14, width: 28, height: 28))
        #expect(more?.accessibilityLabel() == "Space Options")
    }

    @Test func aHiddenHeaderLeavesThePopoversAnchoredOnMore() {
        let cards = Cards()
        let more = sidebarDescendants(cards.card).compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More options" }
        #expect(cards.manager.anchor(for: cards.first.id) === more)
    }

    @Test func moreDrawsAnExteriorKeyboardRingOverItsBounds() {
        let cards = Cards()
        let more = sidebarDescendants(cards.card).compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More options" }
        #expect(more?.focusRingType == .exterior)
        #expect(more?.focusRingMaskBounds == more?.bounds)
    }

    private func focusMaskAlpha(_ cards: Cards) -> (Int, Int) -> CGFloat {
        let more = sidebarDescendants(cards.card).compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More options" }
        let mask = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 28, pixelsHigh: 28, bitsPerSample: 8, samplesPerPixel: 4,
                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mask)
        NSColor.black.setFill()
        more?.drawFocusRingMask()
        NSGraphicsContext.restoreGraphicsState()
        return { x, y in mask.colorAt(x: x, y: y)!.alphaComponent }
    }

    @Test func theRingMaskFillsMoreWithRoundedCorners() {
        let alpha = focusMaskAlpha(Cards())
        #expect(alpha(14, 14) > 0.99)
        #expect(alpha(14, 0) > 0.99)
        #expect(alpha(0, 0) < 0.01)
    }

    @Test func theMasksCornersHaveRadiusSixAsTheHoverFill() {
        let alpha = focusMaskAlpha(Cards())
        #expect(alpha(1, 1) < 0.3)
        #expect(alpha(1, 2) > 0.6)
    }

    @Test func theAddCircleFollowsTheLastCardCentredOnIt() {
        let cards = Cards()
        let add = sidebarDescendants(cards.manager).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Create a Space" }!
        #expect(add.frame.size == NSSize(width: 30, height: 30))
        #expect(add.frame.minX == cards.card.frame.maxX + 24 + 9)
        #expect(add.frame.midY == cards.card.frame.midY)
    }
}
