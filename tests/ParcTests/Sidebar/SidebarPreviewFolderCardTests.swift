import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarPreviewFolderCardTests {
    final class FlippedHost: NSView { override var isFlipped: Bool { true } }

    static func all<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        view.subviews.flatMap { child -> [T] in ((child as? T).map { [$0] } ?? []) + all(child, type) }
    }

    static let right = SidebarPreviewPlacement(row: NSRect(x: 8, y: 300, width: 212, height: 32), location: .right)
    static let rows = (0..<12).map {
        SidebarPreviewRow(id: "\($0)", tabID: UUID(), title: "Page \($0)", url: URL(string: "https://example.com/\($0)")!, visitedAt: nil)
    }

    @MainActor final class Stage {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let folder = SidebarPreviewCard(title: "Docs", domain: nil, providerURL: nil)
        var actions: [(String, SidebarPreviewAction)] = []
        var escapes = 0
        var held: NSEvent.ModifierFlags = []

        init() {
            window.isReleasedWhenClosed = false
            host.wantsLayer = true; window.contentView = host
            folder.reducesMotion = { false }
            folder.modifierFlags = { [weak self] in self?.held ?? [] }
            folder.onAction = { [weak self] row, action in self?.actions.append((row.id, action)) }
            folder.onEscape = { [weak self] in self?.escapes += 1 }
            folder.setRows(SidebarPreviewFolderCardTests.rows)
            folder.placement = SidebarPreviewFolderCardTests.right
            host.addSubview(folder); folder.place()
            host.layoutSubtreeIfNeeded(); folder.layoutSubtreeIfNeeded(); CATransaction.flush()
        }

        var table: NSTableView { SidebarPreviewFolderCardTests.all(folder, NSTableView.self).first! }
        var field: NSTextField { SidebarPreviewFolderCardTests.all(folder, NSTextField.self).first { $0.isEditable }! }
        var rowView: SidebarPreviewRowView? { table.rowView(atRow: 0, makeIfNecessary: true) as? SidebarPreviewRowView }

        func command(_ selector: Selector) { _ = folder.control(field, textView: NSTextView(), doCommandBy: selector) }
        func search(_ text: String) {
            field.stringValue = text
            folder.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        }
    }

    private func line(_ size: CGFloat) -> CGFloat { ceil(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: size))) }
    private func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
    private var item: CGFloat { SidebarPreviewItemView.height }

    @Test func rowsPad6And8AroundTheir13And11PointLines() {
        #expect(item == 6 + line(13) + line(11) + 8)
    }

    @Test func aShortListIsA56PointHeaderPlusItsRows() {
        let card = SidebarPreviewCard(title: "Docs", domain: nil, providerURL: nil)
        card.setRows(Array(Self.rows.prefix(3)))
        #expect(card.preferredHeight(width: 288) == 56 + 3 * (item + 1) + 5)
    }

    @Test func aLongListIsCappedAt384() {
        #expect(Stage().folder.preferredHeight(width: 288) == 384)
    }

    @Test func theCardUsesTheSolvedPlacement() {
        let s = Stage()
        #expect(s.folder.frame == Self.right.frame(width: 288, height: 384, hostHeight: 700))
        #expect(s.folder.frame.width == 288 && s.folder.content.frame == s.folder.bounds)
    }

    @Test func theCardIsPopoverMaterialWithinTheWindow() {
        let s = Stage()
        let effect = Self.all(s.folder, NSVisualEffectView.self).first
        #expect(effect?.material == .popover && effect?.blendingMode == .withinWindow && effect?.state == .followsWindowActiveState)
        #expect(Self.all(s.folder, PopoverBackgroundView.self).first?.translucency.blendingMode == .withinWindow)
        #expect(s.folder.fill == nil)
        #expect(s.folder.appearance == nil)
    }

    @Test func theContentIsClippedAt14Points() {
        let s = Stage()
        #expect(s.folder.content.layer?.cornerRadius == 14 && s.folder.content.layer?.masksToBounds == true)
    }

    @Test func theCardOwnsAnUnclippedShadowFallingDownward() {
        let s = Stage()
        let layer = s.folder.layer
        let shadow = layer.map { ($0.shadowColor?.alpha ?? 0) * CGFloat($0.shadowOpacity) } ?? 0
        #expect(layer?.masksToBounds == false && near(shadow, 0.4) && layer?.shadowRadius == 19)
        #expect(layer?.shadowOffset == CGSize(width: 0, height: 6) && layer?.shadowPath != nil)
        #expect(layer?.superlayer?.isGeometryFlipped == true)
    }

    @Test(arguments: [(NSAppearance.Name.darkAqua, CGFloat(1), CGFloat(0.065)), (.aqua, 0, 1)])
    func theWashAndTitlesFollowTheAppearance(name: NSAppearance.Name, white: CGFloat, wash: CGFloat) {
        let s = Stage()
        let popover = Self.all(s.folder, PopoverBackgroundView.self).first
        s.host.appearance = NSAppearance(named: name)
        s.folder.layoutSubtreeIfNeeded(); popover?.updateLayer()
        let washColor = popover?.wash.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        #expect(washColor.map { near($0.redComponent, wash) && near($0.alphaComponent, 0.7) } == true)
        var title: NSColor?
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            title = Self.all(s.folder, SidebarPreviewItemView.self).first?.titleLabel.textColor?.usingColorSpace(.sRGB)
        }
        #expect(title.map { near($0.redComponent, white) && near($0.alphaComponent, 1) } == true)
    }

    @Test func theHoverAreaWidens40PointsTowardTheRow() {
        let s = Stage()
        s.folder.updateTrackingAreas()
        let area = s.folder.trackingAreas.first { $0.owner === s.folder }
        #expect(area?.rect == NSRect(x: -40, y: 0, width: 328, height: 384))
        #expect(area?.options.contains([.mouseEnteredAndExited, .activeInKeyWindow]) == true)
        #expect(s.folder.hoverFrame == NSRect(x: 184, y: s.folder.frame.minY, width: 328, height: 384))
    }

    @Test func theListSitsUnderTheHeaderWithoutSystemSelection() {
        let s = Stage()
        #expect(s.table.enclosingScrollView?.frame == NSRect(x: 5, y: 56, width: 278, height: 323))
        #expect(s.table.selectionHighlightStyle == .none && s.table.intercellSpacing.height == 1 && s.table.rowHeight == item)
        #expect(s.table.accessibilityLabel() == "Folder pages")
    }

    @Test func rowCellsSetOneLineOf13And11PointText() throws {
        let s = Stage()
        let cell = try #require(s.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SidebarPreviewItemView)
        cell.layoutSubtreeIfNeeded()
        #expect(cell.titleLabel.font == .systemFont(ofSize: 13) && cell.subtitle.font == .systemFont(ofSize: 11))
        #expect(cell.titleLabel.maximumNumberOfLines == 1 && cell.subtitle.maximumNumberOfLines == 1)
        #expect(cell.titleLabel.frame.minX == 34 && cell.titleLabel.frame.minY == 6)
        #expect(cell.subtitle.frame.maxY == cell.bounds.height - 8 && cell.titleLabel.frame.maxX == cell.bounds.width - 8)
    }

    @Test func hoverAloneHighlightsWithoutSelecting() {
        let s = Stage()
        #expect(s.rowView?.highlightOpacity == 0)
        let point = s.table.convert(NSPoint(x: s.table.rect(ofRow: 0).midX, y: s.table.rect(ofRow: 0).midY), to: nil)
        s.table.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: s.window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        #expect(s.rowView?.isHovered == true && s.rowView?.highlightOpacity == 0.08 && s.table.selectedRow == -1)
    }

    @Test func explicitEntryFocusesSearchAndTheFirstRow() {
        let s = Stage()
        s.folder.focusKeyboard()
        #expect(s.field.placeholderAttributedString?.string == "Search Docs")
        #expect(s.table.selectedRow == 0 && s.folder.ownsFirstResponder)
        #expect(s.rowView?.isFocused == true && s.rowView?.highlightOpacity == 0.08)
    }

    @Test func hoverPlusKeyboardFocusDoubleTheHighlight() {
        let s = Stage()
        let point = s.table.convert(NSPoint(x: s.table.rect(ofRow: 0).midX, y: s.table.rect(ofRow: 0).midY), to: nil)
        s.table.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: s.window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        s.folder.focusKeyboard()
        #expect(s.rowView?.highlightOpacity == 0.16)
        s.command(#selector(NSResponder.moveDown(_:)))
        #expect(s.table.selectedRow == 1 && s.rowView?.highlightOpacity == 0.08 && s.folder.ownsFirstResponder)
    }

    @Test func upStopsAtTheFirstRow() {
        let s = Stage()
        s.folder.focusKeyboard()
        s.command(#selector(NSResponder.moveDown(_:)))
        s.command(#selector(NSResponder.moveUp(_:))); s.command(#selector(NSResponder.moveUp(_:)))
        #expect(s.table.selectedRow == 0)
    }

    @Test func theSelectionScrollsIntoView() {
        let s = Stage()
        s.folder.focusKeyboard()
        for _ in 0..<14 { s.command(#selector(NSResponder.moveDown(_:))) }
        #expect(s.table.selectedRow == 11 && s.table.visibleRect.contains(s.table.rect(ofRow: 11)))
    }

    @Test func returnOpensAndEscapeDismisses() {
        let s = Stage()
        s.folder.focusKeyboard()
        for _ in 0..<11 { s.command(#selector(NSResponder.moveDown(_:))) }
        s.command(#selector(NSResponder.insertNewline(_:)))
        s.command(#selector(NSResponder.cancelOperation(_:)))
        #expect(s.actions.map(\.0) == ["11"] && s.actions.first?.1 == .activate([]) && s.escapes == 1)
    }

    @Test func heldCommandShiftReturnDuplicates() {
        let s = Stage()
        s.folder.focusKeyboard()
        for _ in 0..<11 { s.command(#selector(NSResponder.moveDown(_:))) }
        s.held = [.command, .shift, .capsLock]
        s.command(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
        #expect(s.actions.first?.1 == .activate([.command, .shift, .capsLock]))
        #expect(s.actions.first.flatMap { $0.1.activation(for: Self.rows[11]) } == .duplicate)
    }

    @Test func aSearchMissShowsTheEmptyMessageAndShrinksTheCard() {
        let s = Stage()
        s.search("zzz")
        let miss = Self.all(s.folder, NSTextField.self).first { $0.stringValue == "No tabs matching that search\n🤔" }
        #expect(miss?.isHidden == false && s.table.enclosingScrollView?.isHidden == true)
        #expect(s.folder.preferredHeight(width: 288) < 384)
    }

    @Test func typedSearchFocusesTheFirstMatch() {
        let s = Stage()
        s.search("Page 3")
        #expect(s.table.numberOfRows == 1 && s.table.selectedRow == 0)
    }

    @Test(arguments: [("EXAMPLE.COM/7", 1), ("ago", 0)])
    func searchMatchesTheFullURLCaseInsensitivelyButNotTheSubtitle(text: String, matches: Int) {
        let s = Stage()
        s.search(text)
        #expect(s.table.numberOfRows == matches)
    }

    @Test func aRefreshKeepsTheSearchAndKeyboardSelection() {
        let s = Stage()
        s.search("Page")
        s.command(#selector(NSResponder.moveDown(_:)))
        let copy = SidebarPreviewRow(id: "copy", tabID: UUID(), title: "Page 1", url: URL(string: "https://example.com/1")!, visitedAt: nil)
        s.folder.setRows([copy] + Self.rows)
        #expect(s.table.numberOfRows == 13 && s.table.selectedRow == 2 && s.field.stringValue == "Page")
    }

    @Test func aFolderCardHasNoButtonsAndOneRuleUnderItsSearch() {
        let s = Stage()
        #expect(Self.all(s.folder, NSButton.self).isEmpty)
        #expect(Self.all(s.folder, SidebarPreviewDivider.self).count == 1)
    }
}
