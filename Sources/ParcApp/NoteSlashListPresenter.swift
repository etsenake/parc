import AppKit

@MainActor
final class NoteSlashListPresenter {
    let list = NoteMenuList()
    private var madePanel: NoteFloatingPanel?
    var panel: NoteFloatingPanel {
        if let madePanel { return madePanel }
        let made = NoteFloatingPanel(content: list)
        made.maximumHeight = 400
        madePanel = made
        return made
    }
    var presentedPanel: NoteFloatingPanel? { madePanel?.isPresented == true ? madePanel : nil }
    private let overlay: () -> NSView?
    private var preview: NoteBlockPreviewCard?
    private var ghost: NoteMenuGhostView?

    init(overlay: @escaping () -> NSView?) {
        self.overlay = overlay
    }

    func show(_ items: [NoteMenuList.Item], detailed: Bool, highlightFirst: Bool, anchor: () -> NSRect?) {
        crossfade {
            list.rowStyle = detailed ? .detailed : .compact
            list.items = items
            if highlightFirst, list.highlightedIndex == nil, let first = items.firstIndex(where: \.isEnabled) {
                list.highlightedIndex = first
            }
        }
        if !detailed { hidePreview(animated: true) }
        guard !panel.isPresented, let rect = anchor(), let host = overlay() else { return }
        panel.present(in: host, anchor: rect, edge: .below, animated: true)
    }

    private func crossfade(_ update: () -> Void) {
        guard panel.isPresented, !NoteAnimation.reduceMotion, let clip = list.superview, let listLayer = list.layer,
              list.bounds.width > 1, list.bounds.height > 1, let rep = list.bitmapImageRepForCachingDisplay(in: list.bounds) else {
            update()
            return
        }
        list.cacheDisplay(in: list.bounds, to: rep)
        let image = NSImage(size: list.bounds.size)
        image.addRepresentation(rep)
        ghost?.removeFromSuperview()
        let fading = NoteMenuGhostView(frame: list.frame)
        fading.image = image
        clip.addSubview(fading, positioned: .above, relativeTo: list)
        ghost = fading
        update()
        NoteAnimation.withoutAnimation { listLayer.opacity = 0 }
        NoteAnimation.spring(listLayer, "opacity", to: Float(1), spring: .highlight, key: NoteAnimation.keyPrefix + "slash.in")
        guard let ghostLayer = fading.layer else { fading.removeFromSuperview(); return }
        NoteAnimation.spring(ghostLayer, "opacity", to: Float(0), spring: .highlight, key: NoteAnimation.keyPrefix + "slash.out") { [weak self, weak fading] in
            fading?.removeFromSuperview()
            if self?.ghost === fading { self?.ghost = nil }
        }
    }

    func highlightDidChange(_ item: NoteMenuList.Item?, block: NoteCatalogBlock?) {
        guard list.rowStyle == .detailed, let item, let block else {
            hidePreview(animated: true)
            return
        }
        showPreview(for: block, item: item)
    }

    func clearVisuals(animated: Bool) {
        ghost?.removeFromSuperview()
        ghost = nil
        hidePreview(animated: animated)
    }

    private func showPreview(for block: NoteCatalogBlock, item: NoteMenuList.Item) {
        guard panel.isPresented, let overlay = panel.superview else { return }
        let card = preview ?? NoteBlockPreviewCard()
        preview = card
        card.show(block, title: item.title, summary: item.subtitle ?? "")
        let size = card.fittingSize
        let gap = NoteTheme.menuGap
        let panelFrame = NoteFloatingPanel.topDown(panel.frame, in: overlay)
        let visible = NoteFloatingPanel.topDown(overlay.visibleRect, in: overlay)
        var x = panelFrame.maxX + gap
        if x + size.width > visible.maxX - NoteTheme.menuScreenMargin { x = panelFrame.minX - gap - size.width }
        guard x >= visible.minX + NoteTheme.menuScreenMargin else { hidePreview(animated: false); return }
        let rowY = list.highlightedIndex.flatMap { _ in highlightedRowTop() } ?? 0
        var y = panelFrame.minY + rowY - 8
        y = min(max(y, visible.minY + NoteTheme.menuScreenMargin), visible.maxY - NoteTheme.menuScreenMargin - size.height)
        let target = NoteFloatingPanel.topDown(NSRect(x: x, y: y, width: size.width, height: size.height), in: overlay).integral
        if card.superview !== overlay {
            card.frame = target
            overlay.addSubview(card)
            NoteAnimation.presentHUD(card, about: NSPoint(x: x > panelFrame.maxX ? 0 : size.width, y: size.height / 2))
        } else if card.frame != target {
            NoteAnimation.slide(card, to: target, spring: .glide)
        }
    }

    private func highlightedRowTop() -> CGFloat? {
        guard let index = list.highlightedIndex, list.items.indices.contains(index) else { return nil }
        let header = NoteTheme.menuHeaderHeight, separator = NoteTheme.menuSeparatorSlot
        var y = NoteTheme.menuInset
        var section: String?
        for position in 0...index {
            let item = list.items[position]
            if let next = item.section, next != section {
                if position > 0 { y += separator }
                y += header
                section = next
            }
            if position < index { y += list.rowHeight }
        }
        let scroll = list.enclosingScrollViewOffset
        return max(0, y - scroll)
    }

    private func hidePreview(animated: Bool) {
        guard let card = preview, card.superview != nil else { return }
        guard animated, !NoteAnimation.reduceMotion else { card.removeFromSuperview(); return }
        NoteAnimation.dismissHUD(card, about: NSPoint(x: 0, y: card.bounds.midY)) { [weak card] in
            card?.removeFromSuperview()
            card?.layer?.opacity = 1
        }
    }
}

@MainActor
final class NoteMenuGhostView: NSImageView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleNone
        imageAlignment = .alignTopLeft
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension NoteMenuList {
    var enclosingScrollViewOffset: CGFloat {
        subviews.compactMap { $0 as? NSScrollView }.first?.contentView.bounds.origin.y ?? 0
    }
}

