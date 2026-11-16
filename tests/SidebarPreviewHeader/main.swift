import AppKit

@MainActor final class Checks {
    var count = 0
    func expect(_ value: @autoclosure () -> Bool, _ description: String) {
        count += 1
        guard value() else { fatalError("SidebarPreviewHeader: \(description)") }
    }
}

@MainActor func all<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    view.subviews.flatMap { ($0 as? T).map { [$0] } ?? [] + all($0, type) }
}

@MainActor func run() {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let c = Checks()
    let url = URL(string: "https://www.coastalfieldnotes.org/tide-pools")!
    let row = SidebarPreviewRow(id: "tab", tabID: UUID(), title: "Tide pools", url: url, visitedAt: nil)
    let title = "Tide pools of the Pacific coast: a field guide to every rock and creature"
    func card(width: CGFloat = 288, offers: ((SidebarPreviewRow) -> Bool)?) -> SidebarPreviewCard {
        let card = SidebarPreviewCard(title: title, domain: nil, providerURL: url,
                                      picture: NSImage(size: NSSize(width: 320, height: 200)), site: "coastalfieldnotes.org")
        card.offersPeek = offers
        card.setRows([row])
        card.frame = NSRect(x: 0, y: 0, width: width, height: card.preferredHeight(width: width))
        card.layoutSubtreeIfNeeded()
        return card
    }
    func button(_ card: SidebarPreviewCard, _ label: String) -> ActionButton? {
        all(card, ActionButton.self).first { $0.toolTip == label }
    }
    func text(_ card: SidebarPreviewCard, _ value: String) -> NSTextField? {
        all(card, NSTextField.self).first { $0.stringValue == value }
    }

    let artwork = SidebarPreviewArtwork.openInPeek
    c.expect(artwork?.isTemplate == true && artwork?.size == NSSize(width: 16, height: 16), "Open in Peek artwork is a 16 pt template")
    let reps = artwork?.representations ?? []
    c.expect(reps.contains { $0.pixelsWide == 16 } && reps.contains { $0.pixelsWide == 32 } && reps.contains { $0 is NSPDFImageRep },
             "artwork combines the 1× and 2× bitmaps with the vector")

    let plain = card(offers: nil)
    c.expect(button(plain, "Open in Peek") == nil && all(plain, ActionButton.self).map(\.toolTip) == ["Open in Split View"],
             "without a Peek offer the header has only Split View")
    let declined = card(offers: { _ in false })
    c.expect(button(declined, "Open in Peek") == nil, "a declined offer shows no Open in Peek button")
    let todaySplit = NSRect(x: 256, y: 16, width: 24, height: 24)
    for (name, card) in [("no offer", plain), ("declined", declined)] {
        c.expect(button(card, "Open in Split View")?.frame == todaySplit, "\(name): Split View stays at the header's right edge")
        c.expect(text(card, title)?.frame == NSRect(x: 37, y: 12, width: 211, height: 17)
                 && text(card, "coastalfieldnotes.org")?.frame == NSRect(x: 37, y: 29, width: 211, height: 14),
                 "\(name): title and site keep today's width")
    }

    var asked: [SidebarPreviewRow] = []
    var offered = true
    let peekCard = card(offers: { asked.append($0); return offered })
    var actions: [SidebarPreviewAction] = []
    peekCard.onAction = { value, action in if value == row { actions.append(action) } }
    let peek = button(peekCard, "Open in Peek"), split = button(peekCard, "Open in Split View")
    c.expect(peek != nil && asked.last == row, "the Peek offer is asked about the card's own tab")
    c.expect(peek?.frame == NSRect(x: 230, y: 16, width: 24, height: 24) && split?.frame == todaySplit,
             "Open in Peek sits directly left of Split View, on the Recents header's 26 pt pitch")
    c.expect(peek?.image === artwork && peek?.imagePosition == .imageOnly && peek?.title == "", "Open in Peek shows the artwork alone")
    c.expect(peek?.accessibilityLabel() == "Open in Peek", "VoiceOver reads Open in Peek")
    c.expect(peek?.focusRingType == .exterior && peek?.focusRingCornerRadius == split?.focusRingCornerRadius
             && peek?.contentTintColor == split?.contentTintColor, "Open in Peek matches Split View's focus ring and tint")
    c.expect(peek?.showsHoverFill == true && split?.showsHoverFill == true, "both header buttons show the hover plate")
    let heading = text(peekCard, title), site = text(peekCard, "coastalfieldnotes.org")
    c.expect(heading?.frame == NSRect(x: 37, y: 12, width: 185, height: 17) && site?.frame == NSRect(x: 37, y: 29, width: 185, height: 14),
             "title and site end 8 pt before Open in Peek")
    c.expect(heading?.lineBreakMode == .byTruncatingTail && site?.lineBreakMode == .byTruncatingTail, "title and site truncate at the tail")
    c.expect((heading?.attributedStringValue.size().width ?? 0) > heading?.frame.width ?? .infinity, "fixture: the title is long enough to need truncating")

    peek?.performClick(nil)
    c.expect(actions == [.peek], "Open in Peek opens the tab in a Peek")
    split?.performClick(nil)
    c.expect(actions == [.peek, .split], "Split View still opens the tab in Split View")

    offered = false
    actions.removeAll()
    peek?.performClick(nil)
    peekCard.layoutSubtreeIfNeeded()
    c.expect(actions.isEmpty && button(peekCard, "Open in Peek") == nil, "a click after the offer lapses does nothing and hides the button")
    c.expect(heading?.frame.width == 211, "the title takes the space back")
    offered = true
    peekCard.setRows([row]); peekCard.layoutSubtreeIfNeeded()
    c.expect(button(peekCard, "Open in Peek")?.frame == NSRect(x: 230, y: 16, width: 24, height: 24) && heading?.frame.width == 185,
             "a refreshed source brings the button back when Peek is offered again")
    offered = false
    peekCard.setRows([row]); peekCard.layoutSubtreeIfNeeded()
    c.expect(button(peekCard, "Open in Peek") == nil && heading?.frame.width == 211, "a refreshed source drops the button when Peek is no longer offered")
    offered = true
    peekCard.refreshPeek(); peekCard.layoutSubtreeIfNeeded()
    c.expect(button(peekCard, "Open in Peek") != nil && heading?.frame.width == 185, "a render-time refresh shows the button once Peek is offered")
    offered = false
    peekCard.refreshPeek(); peekCard.layoutSubtreeIfNeeded()
    c.expect(button(peekCard, "Open in Peek") == nil && heading?.frame.width == 211, "a render-time refresh hides the button once the offer lapses")

    let narrow = card(width: 240, offers: { _ in true })
    c.expect(button(narrow, "Open in Split View")?.frame.minX == 208 && button(narrow, "Open in Peek")?.frame.minX == 182
             && text(narrow, title)?.frame.width == 137, "a narrowed card keeps both buttons and narrows the title")

    let retiring = card(offers: { _ in true })
    var retiredActions: [SidebarPreviewAction] = []
    retiring.onAction = { _, action in retiredActions.append(action) }
    let retiringPeek = button(retiring, "Open in Peek")
    retiring.retire()
    retiring.layoutSubtreeIfNeeded()
    c.expect(retiringPeek?.superview != nil && text(retiring, title)?.frame.width == 185, "a retiring card keeps its header still while it fades")
    retiringPeek?.performClick(nil)
    retiring.refreshPeek(); retiring.layoutSubtreeIfNeeded()
    c.expect(retiredActions.isEmpty && retiringPeek?.superview != nil && text(retiring, title)?.frame.width == 185,
             "a retired card's Open in Peek does nothing and its header stays put")

    let recents = SidebarPreviewCard(title: "Notion", domain: .notion, providerURL: URL(string: "https://www.notion.so")!)
    recents.offersPeek = { _ in true }
    recents.setRows([SidebarPreviewRow(id: "page", tabID: nil, title: "Plan", url: URL(string: "https://www.notion.so/Plan-1")!, visitedAt: nil)])
    c.expect(Set(all(recents, ActionButton.self).compactMap(\.toolTip)) == ["New Page", "Previews Settings"]
             && all(recents, ActionButton.self).allSatisfy { !$0.showsHoverFill }, "the Recents header is unchanged")
    let folder = SidebarPreviewCard(title: "Docs", domain: nil, providerURL: nil)
    folder.offersPeek = { _ in true }
    folder.setRows([row])
    c.expect(all(folder, ActionButton.self).isEmpty, "a folder card gets no header button")
    print("SidebarPreviewHeader: \(c.count) assertions passed")
}

MainActor.assumeIsolated { exitOnFailure(run) }
