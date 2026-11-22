import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct DownloadRowAccessoryTests {
    typealias Fixture = DownloadListPresentationTests.Fixture

    @MainActor private final class Row {
        let fixture: Fixture
        let row: NSTableRowView
        let cell: NSView
        let backdrop: DownloadRowBackdrop
        let more: NSButton
        let title: NSTextField

        init() throws {
            fixture = try Fixture()
            fixture.table.selectRowIndexes([], byExtendingSelection: false)
            row = try #require(fixture.table.rowView(atRow: 1, makeIfNecessary: true))
            cell = try fixture.cell(1)
            backdrop = try #require(row.subviews.compactMap { $0 as? DownloadRowBackdrop }.first)
            more = try #require(fixture.more(cell))
            title = try #require(fixture.labels(cell).first)
            row.layoutSubtreeIfNeeded()
            backdrop.updateLayer()
            cell.layoutSubtreeIfNeeded()
        }

        func enter() { row.mouseEntered(with: event(.mouseEntered)); cell.layoutSubtreeIfNeeded(); backdrop.updateLayer() }
        func leave() { row.mouseExited(with: event(.mouseExited)); backdrop.updateLayer() }
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        func select() { fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false) }
        var primaryAlpha: CGFloat {
            var alpha: CGFloat = 0
            title.effectiveAppearance.performAsCurrentDrawingAppearance { alpha = NSColor.labelColor.alphaComponent }
            return alpha
        }
        var backdropAlpha: CGFloat { backdrop.layer?.backgroundColor?.alpha ?? -1 }
        func post(_ name: Notification.Name, _ object: Any?) { NotificationCenter.default.post(name: name, object: object) }
    }

    @MainActor @Test func theRowBackgroundFillsTheFullHeightInsideEightPointsOfPadding() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        #expect(row.backdrop.frame == NSRect(x: 8, y: 0, width: row.row.bounds.width - 16, height: 56))
    }

    @MainActor @Test func theRowBackgroundKeepsContinuousTwelvePointCorners() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        #expect(row.backdrop.layer?.cornerRadius == 12 && row.backdrop.layer?.cornerCurve == .continuous)
    }

    @MainActor @Test func theBackgroundNeitherInterceptsInputNorAddsAnAccessibleItem() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        #expect(row.backdrop.hitTest(NSPoint(x: 16, y: 16)) == nil)
        #expect(row.backdrop.isAccessibilityHidden() && row.backdrop.accessibilityChildren()?.isEmpty == true)
    }

    @MainActor @Test func anUnselectedUnhoveredRowIsClear() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        #expect(!row.backdrop.highlighted && row.backdropAlpha == 0)
    }

    @MainActor @Test func theOrdinaryTitleAppliesItsOpacityToTheSemanticPrimary() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        #expect(abs((row.title.textColor?.alphaComponent ?? 0) - row.primaryAlpha * 0.85) < 0.001)
    }

    @MainActor @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func theTitleKeepsItsSemanticAlphaInLightAndDark(_ name: NSAppearance.Name) throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.fixture.view.appearance = NSAppearance(named: name)
        row.fixture.view.layoutSubtreeIfNeeded()
        row.title.effectiveAppearance.performAsCurrentDrawingAppearance {
            #expect(abs((row.title.textColor?.alphaComponent ?? 0) - NSColor.labelColor.alphaComponent * 0.85) < 0.001)
        }
    }

    @MainActor @Test func anUnavailableImageDrawsTheOriginalTwentyFourPointContinuousPlaceholder() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        let artwork = try #require(row.cell.subviews.compactMap { $0 as? NSImageView }.first)
        let placeholder = try #require(artwork.layer?.sublayers?.first)
        #expect(placeholder.frame.size == NSSize(width: 24, height: 24) && placeholder.cornerRadius == 8)
        #expect(placeholder.cornerCurve == .continuous)
        #expect(abs((placeholder.backgroundColor?.alpha ?? 0) - row.primaryAlpha * 0.05) < 0.001)
    }

    @MainActor @Test func anUnhighlightedUnselectedRowCollapsesMore() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        #expect(row.more.isHidden)
    }

    @MainActor @Test func hoveringRestoresTheFullPrimaryTitleAndExposesTheThirtyTwoPointMore() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.enter()
        #expect(abs((row.title.textColor?.alphaComponent ?? 0) - row.primaryAlpha) < 0.001)
        #expect(!row.more.isHidden && row.more.frame.size == NSSize(width: 32, height: 32))
    }

    @MainActor @Test func hoveringSuppliesThePrimaryTenPercentBackground() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.enter()
        #expect(row.backdrop.highlighted && abs(row.backdropAlpha - NSColor.labelColor.alphaComponent * 0.1) < 0.001)
    }

    @MainActor @Test func revealingMoreReturnsItsThirtyTwoPointsFromTheTitleWidth() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        let collapsed = row.title.frame.width
        row.enter()
        #expect(collapsed - row.title.frame.width == 32)
    }

    @MainActor @Test func theCollapseIsImmediateWhenThePointerLeaves() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.enter()
        row.leave()
        #expect(row.more.isHidden)
    }

    @MainActor @Test func tableSelectionExposesMoreWithoutPointerHover() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.select()
        #expect(!row.more.isHidden)
        #expect(row.more.isAccessibilityElement() && row.more.accessibilityRole() == .button)
    }

    @MainActor @Test func anInactiveSelectionKeepsTheSameRecoveredBackground() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.select()
        row.row.isEmphasized = false
        row.backdrop.updateLayer()
        #expect(row.backdrop.highlighted && abs(row.backdropAlpha - NSColor.labelColor.alphaComponent * 0.1) < 0.001)
    }

    @MainActor @Test func selectionAndTheNativeContrastFocusStateStayDistinct() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.select()
        row.row.isEmphasized = true
        row.backdrop.updateLayer()
        #expect(row.backdrop.highlighted && row.backdrop.emphasized)
    }

    @MainActor @Test func anotherScrollOwnersLiveScrollCannotHideTheSelectedAction() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.select()
        row.post(NSScrollView.willStartLiveScrollNotification, NSScrollView())
        #expect(!row.more.isHidden)
    }

    @MainActor @Test func liveScrollReturnsTheMoreFocusToTheTableAndHidesTheSelectedAction() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.select()
        row.fixture.window.makeFirstResponder(row.more)
        row.post(NSScrollView.willStartLiveScrollNotification, row.fixture.table.enclosingScrollView)
        #expect(row.fixture.window.firstResponder === row.fixture.table)
        #expect(row.more.isHidden)
        #expect(row.backdrop.highlighted)
    }

    @MainActor @Test func aPointerCrossingDuringScrollingDoesNotReviveTheAccessory() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.select()
        row.post(NSScrollView.willStartLiveScrollNotification, row.fixture.table.enclosingScrollView)
        row.enter()
        #expect(row.more.isHidden)
    }

    @MainActor @Test func scrollCompletionRestoresTheSelectedRowAccessory() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.select()
        row.post(NSScrollView.willStartLiveScrollNotification, row.fixture.table.enclosingScrollView)
        row.post(NSScrollView.didEndLiveScrollNotification, row.fixture.table.enclosingScrollView)
        #expect(!row.more.isHidden)
    }

    @MainActor @Test func deselectingAndLeavingClearsTheAccessoryAndTheBackground() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.select()
        row.fixture.table.selectRowIndexes([], byExtendingSelection: false)
        row.leave()
        #expect(row.more.isHidden && !row.backdrop.highlighted && row.backdropAlpha == 0)
    }

    @MainActor @Test func losingWindowFocusClearsInactivePointerPresentation() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.enter()
        row.post(NSWindow.didResignKeyNotification, row.fixture.window)
        #expect(row.more.isHidden)
    }

    @MainActor @Test(arguments: [(NSAppearance.Name.aqua, 0.565, 0.910, 0.141), (NSAppearance.Name.darkAqua, 0.592, 0.923, 0.172)])
    func theMoreGlyphUsesTheRecoveredAppearanceSpecificGrays(_ name: NSAppearance.Name, _ rest: Double, _ hover: Double,
                                                              _ press: Double) throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.more.appearance = NSAppearance(named: name)
        row.enter()
        row.more.mouseExited(with: row.event(.mouseExited))
        #expect(abs(row.more.contentTintColor!.alphaComponent - rest) < 0.001)
        row.more.mouseEntered(with: row.event(.mouseEntered))
        #expect(abs(row.more.contentTintColor!.alphaComponent - hover) < 0.001)
        #expect(abs(DownloadAccessoryColors.background(pressed: true, appearance: row.more.effectiveAppearance).alphaComponent - press) < 0.001)
    }

    @MainActor @Test func aDisabledMoreKeepsItsAccessibleLabel() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.more.isEnabled = false
        #expect(!row.more.isEnabled && row.more.accessibilityLabel() == "More download actions")
    }

    @MainActor @Test func aDetachedRowHasRemovedItsScrollObservation() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.fixture.window.contentView = nil
        row.post(NSScrollView.willStartLiveScrollNotification, row.fixture.table.enclosingScrollView)
        row.row.isSelected = true
        #expect(!row.more.isHidden)
    }

    @MainActor @Test func reattachingARowDoesNotRetainStaleHoverPresentation() throws {
        let row = try Row()
        defer { row.fixture.teardown() }
        row.enter()
        row.fixture.window.contentView = nil
        row.fixture.window.contentView = row.fixture.view
        #expect(row.more.isHidden && !row.backdrop.highlighted)
    }
}
