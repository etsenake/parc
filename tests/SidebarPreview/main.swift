import AppKit
import QuartzCore

@MainActor final class Checks {
    var count = 0
    func expect(_ value: @autoclosure () -> Bool, _ description: String) {
        count += 1
        guard value() else { fatalError("SidebarPreview: \(description)") }
    }
}
final class FlippedHost: NSView { override var isFlipped: Bool { true } }
@MainActor func all<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    view.subviews.flatMap { child -> [T] in ((child as? T).map { [$0] } ?? []) + all(child, type) }
}
@MainActor func basic(_ view: NSView, _ key: String) -> CABasicAnimation? {
    view.layer?.animation(forKey: key) as? CABasicAnimation
}
func transform(_ value: Any?) -> CATransform3D? { (value as? NSValue)?.caTransform3DValue }
func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
func controlPoints(_ function: CAMediaTimingFunction?) -> [Float] {
    guard let function else { return [] }
    return (1...2).flatMap { index -> [Float] in
        var point = [Float](repeating: 0, count: 2); function.getControlPoint(at: index, values: &point); return point
    }
}
@MainActor func run() {
    let c = Checks()
    _ = NSApplication.shared

    //
    let row = NSRect(x: 8, y: 300, width: 212, height: 32)
    let right = SidebarPreviewPlacement(row: row, location: .right)
    c.expect(right.frame(height: 200, hostHeight: 700) == NSRect(x: 224, y: 216, width: 240, height: 200),
             "right: leading row.maxX + 4, centred on the row")
    c.expect(right.anchor == NSPoint(x: 220, y: 316), "right anchor is the row's trailing midpoint")
    let nearTop = SidebarPreviewPlacement(row: NSRect(x: 8, y: 20, width: 212, height: 32), location: .right)
    c.expect(nearTop.frame(height: 200, hostHeight: 700).minY == 18, "required top inset beats centring")
    let nearBottom = SidebarPreviewPlacement(row: NSRect(x: 8, y: 660, width: 212, height: 32), location: .right)
    c.expect(nearBottom.frame(height: 200, hostHeight: 700).maxY == 682, "required bottom inset beats centring")
    c.expect(right.frame(height: 320, hostHeight: 300) == NSRect(x: 224, y: 18, width: 240, height: 264),
             "content height yields only to both window insets")
    c.expect(right.frame(height: 500, hostHeight: 900).height == 320, "320 pt soft maximum")
    c.expect(SidebarPreviewPlacement(row: NSRect(x: 900, y: 300, width: 80, height: 32), location: .right)
        .frame(height: 200, hostHeight: 700).minX == 984, "no leading-side flip")
    let tile = SidebarPreviewPlacement(row: NSRect(x: 172, y: 60, width: 47, height: 47), location: .diagonal)
    c.expect(tile.frame(height: 200, hostHeight: 700) == NSRect(x: 215, y: 103, width: 240, height: 200),
             "diagonal: row.maxX - 4, top at row bottom - 4")
    c.expect(tile.anchor == NSPoint(x: 219, y: 107), "diagonal anchor is the tile's trailing bottom corner")

    //
    func aim(_ last: (CGFloat, CGFloat), _ point: (CGFloat, CGFloat), _ location: SidebarPreviewLocation) -> Bool {
        SidebarPreviewAim.keepsCurrent(from: NSPoint(x: last.0, y: last.1), to: NSPoint(x: point.0, y: point.1), location: location)
    }
    c.expect(aim((100, 300), (110, 300), .right), "level rightward move keeps the card")
    c.expect(aim((470, 300), (490, 300), .right), "level rightward move returns before the reach test")
    c.expect(aim((100, 300), (110, 330), .right) && aim((100, 300), (110, 270), .right), "slope 3 either way")
    c.expect(!aim((100, 300), (110, 331), .right), "steeper than 3 retargets")
    c.expect(!aim((110, 300), (110, 280), .right), "vertical move retargets")
    c.expect(!aim((120, 300), (110, 300), .right), "leftward move retargets")
    c.expect(!aim((470, 300), (480, 310), .right) && aim((460, 300), (477, 310), .right), "478 pt reach")
    c.expect(aim((100, 300), (110, 280), .diagonal) && aim((100, 300), (100, 280), .diagonal), "diagonal right/down")
    c.expect(!aim((100, 300), (110, 301), .diagonal), "diagonal upward retargets")
    c.expect(!aim((110, 300), (100, 290), .diagonal), "diagonal leftward retargets")
    c.expect(!aim((470, 300), (478, 290), .diagonal), "diagonal reach")
    c.expect(SidebarPreviewAim.reach == 478, "reach is the favorites grid plus card")

    let opacity = SidebarPreviewHighlight.opacity
    c.expect(opacity(false, false) == 0 && opacity(true, false) == 0.08 && opacity(false, true) == 0.08
             && opacity(true, true) == 0.16, "hover and keyboard focus add up")

    // Real AppKit hierarchy outside the desktop; no browser, profile, input or preferences.
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    host.wantsLayer = true; window.contentView = host
    window.orderFront(nil)

    // Pointer still on the live session row (non-button): full sidebar walk is a no-op.
    let sessionRow = NSView(frame: NSRect(x: 8, y: 300, width: 212, height: 32))
    host.addSubview(sessionRow)
    host.layoutSubtreeIfNeeded()
    func windowPoint(_ hostPoint: NSPoint) -> NSPoint { host.convert(hostPoint, to: nil) }
    c.expect(SidebarPreviewMotion.keepsSessionTarget(windowPoint: windowPoint(NSPoint(x: 20, y: 310)), anchor: sessionRow),
             "pointer on the live row body keeps the session target")
    c.expect(SidebarPreviewMotion.keepsSessionTarget(windowPoint: windowPoint(NSPoint(x: 100, y: 316)), anchor: sessionRow),
             "interior non-button points keep the session target")
    c.expect(!SidebarPreviewMotion.keepsSessionTarget(windowPoint: windowPoint(NSPoint(x: 240, y: 316)), anchor: sessionRow),
             "leaving the row toward the card is not a stay")
    c.expect(!SidebarPreviewMotion.keepsSessionTarget(windowPoint: windowPoint(NSPoint(x: 20, y: 280)), anchor: sessionRow),
             "leaving the row vertically is not a stay")
    let close = NSButton(frame: NSRect(x: 180, y: 4, width: 24, height: 24))
    sessionRow.addSubview(close)
    sessionRow.layoutSubtreeIfNeeded()
    c.expect(!SidebarPreviewMotion.keepsSessionTarget(windowPoint: windowPoint(NSPoint(x: 192, y: 316)), anchor: sessionRow),
             "row action buttons do not keep the session (previewTarget NSButton exclusion)")
    let stayed = windowPoint(NSPoint(x: 20, y: 310))
    sessionRow.removeFromSuperview()
    c.expect(!SidebarPreviewMotion.keepsSessionTarget(windowPoint: stayed, anchor: sessionRow),
             "a detached anchor cannot keep the session")
    let palette = ThemeChromePalette(theme: SpaceTheme(), isDark: false)
    let rows = (0..<12).map {
        SidebarPreviewRow(id: "\($0)", tabID: UUID(), title: "Page \($0)", url: URL(string: "https://example.com/\($0)")!,
                          visitedAt: nil)
    }
    let folder = SidebarPreviewCard(title: "Docs", domain: nil, providerURL: nil, palette: palette)
    var actions: [(String, SidebarPreviewAction)] = [], escapes = 0
    var held: NSEvent.ModifierFlags = []
    folder.modifierFlags = { held }
    folder.onAction = { row, action in actions.append((row.id, action)) }
    folder.onEscape = { escapes += 1 }
    let item = SidebarPreviewItemView.height
    folder.setRows(Array(rows.prefix(3)))
    c.expect(folder.preferredHeight == 48 + 3 * (item + 1) + 4, "48 pt header plus content height")
    folder.setRows(rows)
    c.expect(folder.preferredHeight == 320, "list is capped at 272 pt")
    folder.placement = right
    host.addSubview(folder); folder.place()
    c.expect(folder.frame == right.frame(height: 320, hostHeight: 700), "card uses the solved placement")
    host.layoutSubtreeIfNeeded(); folder.layoutSubtreeIfNeeded(); CATransaction.flush()

    // PreviewBackgroundView chrome.
    let effect = all(folder, NSVisualEffectView.self).first
    c.expect(effect?.material == .popover && effect?.blendingMode == .withinWindow
             && effect?.state == .followsWindowActiveState, "popover material within the window")
    c.expect(folder.frame.width == 240 && folder.content.frame == folder.bounds, "240 pt content")
    c.expect(folder.content.layer?.cornerRadius == 12 && folder.content.layer?.masksToBounds == true, "content clipped at 12")
    let shadow = folder.layer.map { ($0.shadowColor?.alpha ?? 0) * CGFloat($0.shadowOpacity) }
    c.expect(folder.layer?.masksToBounds == false && near(shadow ?? 0, 0.4) && folder.layer?.shadowRadius == 16
             && folder.layer?.shadowOffset == CGSize(width: 0, height: 5) && folder.layer?.shadowPath != nil,
             "unclipped black 0.4 / 16 pt shadow owner")
    // CALayer.render does not composite shadows as the window server does; the
    // geometry-flipped superlayer is what makes a positive offset fall down.
    c.expect(folder.layer?.superlayer?.isGeometryFlipped == true, "shadow falls 5 pt downward in the flipped root")
    c.expect(folder.fill == nil, "folder card is material only")

    //
    folder.updateTrackingAreas()
    let area = folder.trackingAreas.first { $0.owner === folder }
    c.expect(area?.rect == NSRect(x: -40, y: 0, width: 280, height: 320), "tracking area widened 40 pt left")
    c.expect(area?.options.contains([.mouseEnteredAndExited, .activeInKeyWindow]) == true, "options 0x21")
    c.expect(folder.hoverFrame == NSRect(x: 184, y: folder.frame.minY, width: 280, height: 320), "hover frame")

    // EaselUI ToolTipAnimations entrance about the row edge.
    let anchor = folder.convert(right.anchor, from: host)
    folder.animateIn(from: anchor)
    let grow = basic(folder, "transform"), fade = basic(folder, "opacity")
    c.expect(grow?.duration == 0.1 && fade?.duration == 0.1, "0.1 s entrance")
    c.expect(controlPoints(grow?.timingFunction) == [0.42, 0, 0.58, 1]
             && controlPoints(fade?.timingFunction) == [0.42, 0, 0.58, 1], "ease-in-ease-out")
    c.expect(number(fade?.fromValue) == 0 && number(fade?.toValue) == 1, "opacity 0 to 1")
    c.expect(transform(grow?.toValue).map(CATransform3DIsIdentity) == true, "scale ends at identity")
    let start = transform(grow?.fromValue) ?? CATransform3DIdentity
    c.expect(near(start.m11, 0.8) && near(start.m22, 0.8), "scale starts at 0.8")
    folder.layer!.transform = start
    let fixed = host.layer!.convert(anchor, from: folder.layer!)
    let corner = host.layer!.convert(CGPoint.zero, from: folder.layer!)
    folder.layer!.transform = CATransform3DIdentity
    c.expect(near(fixed.x, right.anchor.x) && near(fixed.y, right.anchor.y), "row edge is the scale's fixed point")
    c.expect(near(corner.x, 220 + 0.8 * (folder.frame.minX - 220)) && near(corner.y, 316 + 0.8 * (folder.frame.minY - 316)),
             "card grows out of the row edge")

    // ItemView rows; hover and keyboard focus are separate states.
    let table = all(folder, NSTableView.self).first!
    c.expect(table.selectionHighlightStyle == .none && table.intercellSpacing.height == 1 && table.rowHeight == item,
             "no system selection; 1 pt row spacing")
    c.expect(table.accessibilityLabel() == "Folder pages", "list accessibility retained")
    let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SidebarPreviewItemView
    cell?.layoutSubtreeIfNeeded()
    c.expect(cell?.titleLabel.font == .systemFont(ofSize: 13) && cell?.subtitle.font == .systemFont(ofSize: 11), "13/11 pt text")
    c.expect(cell?.titleLabel.maximumNumberOfLines == 1 && cell?.subtitle.maximumNumberOfLines == 1, "one line each")
    c.expect(cell?.titleLabel.frame.minX == 32 && cell?.titleLabel.frame.minY == 5
             && cell?.subtitle.frame.maxY == (cell?.bounds.height ?? 0) - 7, "5/7/8 padding and 8 pt spacing")
    let rowView = table.rowView(atRow: 0, makeIfNecessary: true) as? SidebarPreviewRowView
    c.expect(rowView?.highlightOpacity == 0, "hover-only presentation focuses nothing")
    // Deliver the table's own tracking callback directly; nothing is posted to the system.
    let hoverPoint = table.convert(NSPoint(x: table.rect(ofRow: 0).midX, y: table.rect(ofRow: 0).midY), to: nil)
    table.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: hoverPoint, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
    c.expect(rowView?.isHovered == true && rowView?.highlightOpacity == 0.08 && table.selectedRow == -1,
             "hover alone, without selection")

    // Explicit keyboard entry: the search keeps focus and moves the selection.
    folder.focusKeyboard()
    let field = all(folder, NSTextField.self).first { $0.isEditable }!
    c.expect(field.placeholderAttributedString?.string == "Search Docs", "Search placeholder")
    c.expect(table.selectedRow == 0 && folder.ownsFirstResponder, "explicit entry focuses search and the first row")
    c.expect(rowView?.isFocused == true && rowView?.highlightOpacity == 0.16, "hover plus keyboard focus")
    let editor = NSTextView()
    func command(_ selector: Selector) { _ = folder.control(field, textView: editor, doCommandBy: selector) }
    command(#selector(NSResponder.moveDown(_:)))
    c.expect(table.selectedRow == 1 && rowView?.highlightOpacity == 0.08 && folder.ownsFirstResponder, "Down moves focus only")
    command(#selector(NSResponder.moveUp(_:))); command(#selector(NSResponder.moveUp(_:)))
    c.expect(table.selectedRow == 0, "Up stops at the first row")
    for _ in 0..<14 { command(#selector(NSResponder.moveDown(_:))) }
    c.expect(table.selectedRow == 11 && table.visibleRect.contains(table.rect(ofRow: 11)), "selection scrolls into view")
    command(#selector(NSResponder.insertNewline(_:)))
    command(#selector(NSResponder.cancelOperation(_:)))
    c.expect(actions.map(\.0) == ["11"] && actions.first?.1 == .activate([]) && escapes == 1, "Return opens, Escape dismisses")
    //
    held = [.command, .shift, .capsLock]; actions.removeAll()
    command(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
    c.expect(actions.first?.1 == .activate([.command, .shift, .capsLock])
             && actions.first.flatMap { $0.1.activation(for: rows[11]) } == .duplicate, "held Command-Shift Return duplicates")
    held = []
    window.makeFirstResponder(nil)
    field.stringValue = "zzz"; folder.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    let miss = all(folder, NSTextField.self).first { $0.stringValue == "No tabs matching that search\n🤔" }
    c.expect(miss?.isHidden == false && table.enclosingScrollView?.isHidden == true, "recovered search miss")
    c.expect(folder.preferredHeight < 320, "card height follows its content")
    field.stringValue = "Page 3"; folder.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    c.expect(table.numberOfRows == 1 && table.selectedRow == 0, "typed search focuses the first match")
    field.stringValue = "EXAMPLE.COM/7"; folder.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    c.expect(table.numberOfRows == 1, "search matches the full URL case-insensitively")
    field.stringValue = "ago"; folder.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    c.expect(table.numberOfRows == 0, "search ignores the subtitle")
    // A shown folder refreshes in place (a duplicate arrives newest first).
    field.stringValue = "Page"; folder.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    command(#selector(NSResponder.moveDown(_:)))
    let copy = SidebarPreviewRow(id: "copy", tabID: UUID(), title: "Page 1", url: URL(string: "https://example.com/1")!, visitedAt: nil)
    folder.setRows([copy] + rows)
    c.expect(table.numberOfRows == 13 && table.selectedRow == 2 && field.stringValue == "Page", "refresh keeps search and keyboard selection")
    field.stringValue = ""; folder.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    folder.setRows(rows)
    c.expect(all(folder, NSButton.self).isEmpty, "no close or refresh controls")

    // Recents: header, CTA, gear and per-provider empty state; no loading card or search.
    let provider = URL(string: "https://www.notion.so/team/doc")!
    let recents = SidebarPreviewCard(title: "Notion", domain: .notion, providerURL: provider, palette: palette)
    var requested: [URL] = [], created: [URL] = [], settings = 0
    recents.requestFavicon = { url, done in requested.append(url); done(nil) }
    recents.modifierFlags = { [.option] }
    recents.onAction = { row, action in if action == .create(.option) { created.append(row.url) } }
    recents.onSettings = { settings += 1 }
    recents.setRows([])
    c.expect(requested == [provider], "header uses the provider favicon")
    c.expect(all(recents, NSTextField.self).contains { $0.stringValue == "Recents" }, "Recents title")
    c.expect(all(recents, NSTextField.self).contains { $0.stringValue == "Recent Notion docs appear here." && !$0.isHidden },
             "provider empty state")
    c.expect(!all(recents, NSTextField.self).contains { $0.isEditable }, "recents have no search row")
    let buttons = all(recents, NSButton.self)
    c.expect(buttons.map { $0.toolTip ?? "" } == ["New Page", "Previews Settings"], "CTA and gear only")
    buttons.forEach { $0.performClick(nil) }
    c.expect(created == [URL(string: "https://notion.so/new")!] && settings == 1, "CTA and gear actions")
    c.expect(recents.fill != nil, "recents content background")
    c.expect(SidebarRecentDomain.allCases.map(\.createTitle) == ["New Page", "New File", "New Issue", "New Page"]
             && SidebarRecentDomain.allCases.map(\.createURL.absoluteString)
                == ["https://notion.so/new", "https://figma.com/new", "https://linear.app/new", "https://confluence.new"],
             "per-provider CTA")
    c.expect(SidebarRecentDomain.allCases.map(\.emptyMessage) == ["Recent Notion docs appear here.",
        "Recent Figma files appear here.", "Recent Linear projects and issues appear here.",
        "Recent Confluence pages appear here."], "per-provider empty states")

    //
    let now = Date()
    func page(_ title: String, _ url: String, _ age: TimeInterval = 5) -> SidebarPreviewRow {
        SidebarPreviewRow(id: url, tabID: nil, title: title, url: URL(string: url)!, visitedAt: now.addingTimeInterval(-age))
    }
    let pages = SidebarPreviewRow.recentPages([
        page("(2) Roadmap | Notion", "https://www.notion.so/Roadmap-0123456789abcdef0123456789abcdef"),
        page("Roadmap", "https://www.notion.so/Old-fedcba9876543210fedcba9876543210"),
        page("Roadmap moved", "https://www.notion.so/r-0123456789abcdef0123456789abcdef"),
        page("Elsewhere", "https://example.com/notion"),
        page("Spec", "https://acme.notion.site/Spec", 3600),
    ], domain: .notion)
    c.expect(pages.map(\.title) == ["Roadmap", "Spec"], "tidy titles, provider check and first-occurrence dedupe")
    c.expect(pages.first?.subtitle(now: now) == "Just now" && pages.last?.subtitle(now: now) != "Just now", "relative visit subtitle")
    let issue = SidebarPreviewRow.recentPages([page("ENG-7 Fix it", "https://linear.app/acme/issue/ENG-7/fix-it")], domain: .linear)
    c.expect(issue.map(\.title) == ["Fix it"] && issue.first?.subtitle(now: now) == "ENG-7 • Just now", "Linear ID moves to the subtitle")
    c.expect(SidebarPreviewRow.recentPages([page("Plan - Eng - Confluence", "https://acme.atlassian.net/wiki/spaces/E/pages/1")],
             domain: .confluence).map(\.title) == ["Plan"], "Confluence suffix dropped")
    recents.setRows(pages)
    let recentTable = all(recents, NSTableView.self).first!
    let recentCell = recentTable.view(atColumn: 0, row: 0, makeIfNecessary: true) as? SidebarPreviewItemView
    recentCell?.frame = NSRect(x: 0, y: 0, width: 232, height: item); recentCell?.layoutSubtreeIfNeeded()
    c.expect(recentCell.map { all($0, NSImageView.self).isEmpty } == true && recentCell?.titleLabel.frame.minX == 8
             && recentCell?.subtitle.stringValue == "Just now", "recent rows have no icon")
    c.expect(requested == [provider], "no favicon is requested for recent rows")
    recentTable.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    var recentActions: [SidebarPreviewAction] = []
    recents.onAction = { _, action in recentActions.append(action) }
    recents.modifierFlags = { [.command, .option] }
    recentTable.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
    c.expect(recentActions == [.activate([.command, .option])]
             && recentActions.first?.activation(for: pages[1]) == .openNewTab(split: true), "recent Return carries held modifiers")

    //
    //
    //
    func rightClickMenu(_ domain: SidebarRecentDomain?, _ row: SidebarPreviewRow) -> (NSMenu?, SidebarPreviewCard) {
        let card = SidebarPreviewCard(title: "Menu", domain: domain, providerURL: nil, palette: palette)
        card.placement = right; host.addSubview(card); card.place(); card.setRows([row])
        host.layoutSubtreeIfNeeded(); card.layoutSubtreeIfNeeded()
        defer { card.removeFromSuperview() }
        let table = all(card, NSTableView.self).first!
        let point = table.convert(NSPoint(x: table.rect(ofRow: 0).midX, y: table.rect(ofRow: 0).midY), to: nil)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        return (table.menu(for: event), card)
    }
    func menuTitles(_ menu: NSMenu?) -> [String]? { menu?.items.map { $0.isSeparatorItem ? "—" : $0.title } }
    func choose(_ menu: NSMenu?, _ card: SidebarPreviewCard) -> [SidebarPreviewAction] {
        var chosen: [SidebarPreviewAction] = []
        card.onAction = { _, action in chosen.append(action) }
        for item in menu?.items ?? [] where !item.isSeparatorItem { _ = (item.target as? NSObject)?.perform(item.action, with: item) }
        return chosen
    }
    let (folderMenu, folderCard) = rightClickMenu(nil, rows[0])
    c.expect(menuTitles(folderMenu) == ["Copy URL", "Open in Split View", "Duplicate", "—", "Archive"]
             && choose(folderMenu, folderCard) == [.copyURL, .split, .duplicate, .archive], "a folder row has the folder preview menu")
    let (ticketMenu, ticketCard) = rightClickMenu(.linear, page("Fix it", "https://linear.app/acme/issue/ENG-7/fix-it"))
    c.expect(menuTitles(ticketMenu) == ["Copy Issue ID", "Copy Issue URL"]
             && choose(ticketMenu, ticketCard) == [.copyIssueID("ENG-7"), .copyURL], "a Linear ticket row copies its ID or URL")
    c.expect(rightClickMenu(.notion, pages[0]).0 == nil, "a recognized Notion page row has no menu")
    let (figmaMenu, figmaCard) = rightClickMenu(.figma, page("Board", "https://www.figma.com/design/a/Board"))
    c.expect(menuTitles(figmaMenu) == ["Copy URL"] && choose(figmaMenu, figmaCard) == [.copyURL], "an unrecognized page row copies its URL")

    // Folder rows: custom title, then tidy title; newest visit first; badge path.
    let folderURL = URL(string: "https://www.figma.com/design/a/Board")!
    c.expect(SidebarPreviewRow.folderTitle(custom: "Mine", url: folderURL, title: "Board – Figma") == "Mine"
             && SidebarPreviewRow.folderTitle(custom: nil, url: folderURL, title: "Board – Figma") == "Board"
             && SidebarPreviewRow.folderTitle(custom: nil, url: URL(string: "https://example.com")!, title: "Raw") == "Raw",
             "folder title precedence")
    func visited(_ id: String, _ age: TimeInterval?) -> SidebarPreviewRow {
        SidebarPreviewRow(id: id, tabID: UUID(), title: id, url: URL(string: "https://example.com/" + id)!,
                          visitedAt: age.map { now.addingTimeInterval(-$0) })
    }
    c.expect(SidebarPreviewRow.newestFirst([visited("a", 60), visited("b", nil), visited("c", 5), visited("d", 60)]).map(\.id)
             == ["c", "a", "d", "b"], "newest first, sidebar order for ties")
    let older = visited("old", 7200)
    c.expect(older.subtitle(now: now) == RecentPageText.relativeTime(older.visitedAt!, now: now), "folder subtitle is the visit time")
    let linearTab = SidebarPreviewRow(id: "l", tabID: UUID(), title: "Fix it",
        url: URL(string: "https://linear.app/acme/issue/ENG-7/fix-it")!, visitedAt: now)
    c.expect(linearTab.subtitle(now: now) == "Just now", "folder rows have no Linear prefix")
    var badged = visited("new", 5); badged.isBadged = true
    c.expect(badged.subtitle(now: now) == "Recently Added", "badge subtitle")
    let badgedCell = SidebarPreviewItemView(row: badged, title: .labelColor, secondary: .secondaryLabelColor, now: now)
    c.expect(badgedCell.subtitle.font == .boldSystemFont(ofSize: 11) && badgedCell.subtitle.stringValue == "Recently Added",
             "badged subtitle is emphasized")
    let plainCell = SidebarPreviewItemView(row: older, title: .labelColor, secondary: .secondaryLabelColor, now: now)
    c.expect(plainCell.subtitle.font == .systemFont(ofSize: 11) && !all(plainCell, NSImageView.self).isEmpty, "folder rows keep icons")

    // Activation kinds and the session's owner identity.
    c.expect(SidebarPreviewAction.activate(.option).activation(for: older) == .selectOriginal(split: true)
             && SidebarPreviewAction.activate(.option).activation(for: pages[0]) == .navigateSource(split: true)
             && SidebarPreviewAction.create(.command).activation(for: pages[0]) == .openNewTab(split: false)
             && SidebarPreviewAction.split.activation(for: older) == nil, "row kind selects the route")
    let ownerTarget = SidebarPreviewTarget.folder(UUID()), profile = UUID(), space = UUID()
    func source(_ rows: [SidebarPreviewRow], selected: [UUID] = []) -> SidebarPreviewSource {
        SidebarPreviewSource(target: ownerTarget, profileID: profile, spaceID: space, selectedTabIDs: selected, focusedTabID: nil,
            theme: SpaceTheme(), title: "Docs", domain: nil, originalURL: nil, rows: rows)
    }
    c.expect(source([older]).hasSameOwner(as: source([older, badged])) && !source([older]).hasSameOwner(as: source([older], selected: [UUID()])),
             "only rows may refresh within a session")

    // Same-item geometry updates move without animation.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0)); CATransaction.flush()
    let settled = Set(folder.layer?.animationKeys() ?? [])
    folder.placement.row.origin.y += 40; folder.place()
    c.expect(Set(folder.layer?.animationKeys() ?? []) == settled
             && folder.frame.minY == right.frame(height: folder.preferredHeight, hostHeight: 700).minY + 40,
             "reposition is immediate and adds no animation")

    // Exit: retired card takes no input; it is removed after the animation.
    folder.retire()
    c.expect(folder.hitTest(NSPoint(x: folder.frame.midX, y: folder.frame.midY)) == nil, "exiting card takes no clicks")
    c.expect(!folder.trackingAreas.contains { $0.owner === folder }, "exiting card stops tracking hover")
    var removed = false
    let presented = Double(folder.layer?.presentation()?.opacity ?? folder.layer?.opacity ?? 0)
    folder.animateOut { removed = true }
    let shrink = basic(folder, "transform"), exit = basic(folder, "opacity")
    c.expect(exit?.fillMode == .forwards && exit?.isRemovedOnCompletion == false
             && shrink?.fillMode == .forwards && shrink?.isRemovedOnCompletion == false, "fill forwards, not removed")
    c.expect(presented > 0 && near(CGFloat(number(exit?.fromValue) ?? -1), CGFloat(presented)) && number(exit?.toValue) == 0
             && near(CGFloat(exit?.duration ?? 0), CGFloat(0.1 * presented)), "0.1 s times presented opacity")
    c.expect(transform(shrink?.toValue).map { CATransform3DEqualToTransform($0, start) } == true, "shrinks to 0.8 about the anchor")
    c.expect(controlPoints(exit?.timingFunction) == [0.42, 0, 0.58, 1], "exit ease-in-ease-out")
    c.expect(folder.superview === host && !removed, "card stays while exiting")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0)); CATransaction.flush()
    c.expect(removed && folder.superview == nil, "card removed after its exit")
    let faded = SidebarPreviewSurface(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    host.addSubview(faded); faded.layer?.opacity = 0.5; CATransaction.flush()
    faded.animateOut {}
    c.expect(near(CGFloat(basic(faded, "opacity")?.duration ?? 0), 0.05), "partial opacity shortens the exit")
    let hidden = SidebarPreviewSurface(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    host.addSubview(hidden); hidden.layer?.opacity = 0; CATransaction.flush()
    var hiddenRemoved = false
    hidden.animateOut { hiddenRemoved = true }
    c.expect(hiddenRemoved && hidden.superview == nil, "invisible card is removed immediately")
    window.orderOut(nil)
    print("SidebarPreview: \(c.count) assertions passed")
}
MainActor.assumeIsolated { run() }
