import AppKit
import PDFKit
import ParcCore
import ParcKit

@MainActor
final class EaselCanvasPageState {
    static let implicitPage = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    var viewports: [UUID: (origin: NSPoint, magnification: CGFloat)] = [:]
    var onPageChange: (() -> Void)?
    var onCopyPageLink: ((UUID?) -> Void)?
    var installed = false
}

package enum EaselPageAddress {
    static let prefix = "page-"

    static func urlString(easel: UUID, page: UUID) -> String {
        InternalPage.easel(easel).urlString + "#" + prefix + page.uuidString.lowercased()
    }

    package static func target(of urlString: String) -> (easel: UUID, page: UUID)? {
        guard let easel = InternalPage(urlString: urlString)?.easelID, let fragment = URLComponents(string: urlString)?.fragment,
              fragment.hasPrefix(prefix), let page = UUID(uuidString: String(fragment.dropFirst(prefix.count))) else { return nil }
        return (easel, page)
    }
}

@MainActor
extension EaselCanvasView {
    package var currentPage: UUID? { session.currentPage }
    var currentPageName: String { EaselPages.page(session.page, in: session.fullDocument)?.name ?? EaselPages.firstPageName }
    var visitablePages: [EaselPage] { EaselPages.contentPages(session.fullDocument) }

    func installPageFollowing() {
        guard !pageState.installed else { return }
        pageState.installed = true
        session.onFollow = { [weak self] page in self?.showPage(page, rememberingViewport: true, finishing: false) }
    }

    private func pageKey(_ page: UUID?) -> UUID { page ?? EaselCanvasPageState.implicitPage }

    private func rememberViewport() {
        guard fixedCanvasSize == nil, let scroll = enclosingScrollView else { return }
        pageState.viewports[pageKey(session.currentPage)] = (scroll.contentView.bounds.origin, scroll.magnification)
    }

    private func restoreViewport() {
        guard fixedCanvasSize == nil, let scroll = enclosingScrollView else { return }
        resizeCanvas(viewport: scroll.contentSize)
        if let saved = pageState.viewports[pageKey(session.currentPage)] {
            scroll.magnification = saved.magnification
            scroll.contentView.scroll(to: saved.origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        } else if session.document.items.isEmpty {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        } else {
            zoomToFit(maximum: 1, animated: false)
        }
    }

    @discardableResult
    package func showPage(_ page: UUID?, rememberingViewport: Bool = true, finishing: Bool = true) -> Bool {
        installPageFollowing()
        let full = session.fullDocument
        let target = EaselPages.resolvedPage(page, in: full)
        guard target != session.currentPage || session.page != target else { return false }
        if finishing {
            cancelPointerInteraction()
            finishImageCrop(save: true)
            guard finishEditing() else { return false }
        }
        if rememberingViewport { rememberViewport() }
        let flip = beginPageFlip(to: target)
        session.show(target)
        selection = []
        arrangeState.enteredGroup = nil
        documentDidChange()
        restoreViewport()
        if let flip { playPageFlip(flip) }
        pageState.onPageChange?()
        let name = currentPageName
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: name, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        return true
    }

    @discardableResult
    func showAdjacentPage(_ delta: Int) -> Bool {
        let pages = visitablePages
        guard pages.count > 1, let index = pages.firstIndex(where: { $0.id == session.currentPage }) else { return false }
        let next = index + delta
        guard pages.indices.contains(next) else { NSSound.beep(); return true }
        return showPage(pages[next].id)
    }

    func handlePageKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 116 || event.keyCode == 121, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              fixedCanvasSize == nil, pageState.installed, visitablePages.count > 1 else { return false }
        return showAdjacentPage(event.keyCode == 116 ? -1 : 1)
    }

    private func applyPages(_ name: String, _ document: EaselDocument, show page: UUID?, select items: Set<UUID> = []) -> Bool {
        cancelPointerInteraction()
        guard finishEditing() else { return false }
        installPageFollowing()
        do { try session.performOnDocument(name) { $0 = document } } catch { onError?(error); return false }
        if !showPage(page, finishing: false) { documentDidChange() }
        if !items.isEmpty {
            selection = items.intersection(Set(session.document.items.map(\.id)))
            invalidateIncrementalDisplay(layout: true)
        }
        pageState.onPageChange?()
        return true
    }

    @discardableResult
    func addPage() -> Bool {
        guard let change = EaselPages.adding(to: session.fullDocument, after: session.currentPage) else { NSSound.beep(); return false }
        return applyPages("Add page", change.document, show: change.page)
    }

    @discardableResult
    func addPageDivider() -> Bool {
        guard let change = EaselPages.addingDivider(to: session.fullDocument, after: session.currentPage) else { NSSound.beep(); return false }
        return applyPages("Add divider", change.document, show: session.currentPage)
    }

    @discardableResult
    func renamePage(_ page: UUID?, to name: String) -> Bool {
        var base = session.fullDocument
        var id = page
        if base.pages == nil {
            base = EaselPages.materialized(base)
            id = base.pages?.first?.id
        }
        guard let id, let next = EaselPages.renaming(id, to: name, in: base) else { return false }
        return applyPages("Rename page", next, show: page == nil ? id : session.currentPage)
    }

    @discardableResult
    func movePage(_ page: UUID?, to index: Int) -> Bool {
        guard let page, let next = EaselPages.moving(page, to: index, in: session.fullDocument) else { return false }
        return applyPages("Move page", next, show: session.currentPage)
    }

    @discardableResult
    func duplicatePage(_ page: UUID?) -> Bool {
        guard let change = EaselPages.duplicating(page ?? session.currentPage, in: session.fullDocument) else { NSSound.beep(); return false }
        return applyPages("Duplicate page", change.document, show: change.page)
    }

    func deletePage(_ page: UUID?) {
        let full = session.fullDocument
        guard let page, let target = full.pages?.first(where: { $0.id == page }),
              EaselPages.deleting(page, in: full) != nil else { NSSound.beep(); return }
        let count = EaselPages.itemCount(on: page, in: full)
        let perform = { [weak self] in
            guard let self, let change = EaselPages.deleting(page, in: self.session.fullDocument) else { return }
            let shown = self.session.currentPage == page ? change.page : self.session.currentPage
            _ = self.applyPages(EaselPages.isDivider(target, in: full) ? "Delete divider" : "Delete page", change.document, show: shown)
        }
        guard count > 0, let window else { perform(); return }
        let message = count == 1 ? "The object on it goes too. Undo brings it back."
            : "All \(count) objects on it go too. Undo brings them back."
        _ = ParcDialog.confirm(in: window, title: "Delete “\(target.name)”?",
                               message: message,
                               confirm: "Delete Page", destructive: true) { confirmed in
            MainActor.assumeIsolated { if confirmed { perform() } }
        }
    }

    @discardableResult
    func moveSelection(toPage page: UUID) -> Bool {
        let ids = EaselArrange.unlocked(selection, in: session.document)
        guard !ids.isEmpty, let change = EaselPages.movingItems(ids, to: page, in: session.fullDocument) else { NSSound.beep(); return false }
        return applyPages(change.items.count == 1 ? "Move to page" : "Move objects to page", change.document, show: page, select: change.items)
    }

    @discardableResult
    func moveSelectionToNewPage() -> Bool {
        guard let added = EaselPages.adding(to: session.fullDocument, after: session.currentPage), let page = added.page else {
            NSSound.beep(); return false
        }
        let ids = EaselArrange.unlocked(selection, in: session.document)
        guard !ids.isEmpty, let change = EaselPages.movingItems(ids, to: page, in: added.document) else { NSSound.beep(); return false }
        return applyPages("Move objects to new page", change.document, show: page, select: change.items)
    }

    func copyLink(toPage page: UUID?) {
        guard !session.isClosed else { NSSound.beep(); return }
        if let onCopyPageLink = pageState.onCopyPageLink { onCopyPageLink(page); return }
        let id = session.fullDocument.id
        let string = page.map { EaselPageAddress.urlString(easel: id, page: $0) } ?? InternalPage.easel(id).urlString
        guard let url = URL(string: string) else { NSSound.beep(); return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        board.setString(url.absoluteString, forType: .string)
    }

    func showPage(containing id: UUID) {
        let full = session.fullDocument
        guard full.pages != nil, let item = full.items.first(where: { $0.id == id }) else { return }
        let page = EaselPages.pageID(of: item, in: full)
        if page != session.currentPage { showPage(page) }
    }

    func pageMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard fixedCanvasSize == nil, pageState.installed, !session.isClosed else { return [] }
        let full = session.fullDocument
        guard context.target != .canvas else {
            guard full.pages != nil, let page = session.currentPage else { return [] }
            return [EaselMenuRow(id: "copy-page-link", title: "Copy Link to Page", symbol: "link", perform: guardedMenuAction { canvas in
                canvas.copyLink(toPage: page)
            })]
        }
        let movable = !EaselArrange.unlocked(Set(context.items.map(\.id)), in: session.document).isEmpty
        var children = EaselPages.contentPages(full).filter { $0.id != session.currentPage }.map { page in
            EaselMenuRow(id: "move-to-page-" + page.id.uuidString, title: page.name, symbol: "doc", perform: guardedMenuAction { canvas in
                canvas.moveSelection(toPage: page.id)
            })
        }
        children.append(EaselMenuRow(id: "move-to-new-page", title: "New Page", symbol: "plus", isEnabled: (full.pages?.count ?? 1) < EaselPage.maximumCount,
                                     separatorBefore: !children.isEmpty, perform: guardedMenuAction { canvas in
            canvas.moveSelectionToNewPage()
        }))
        return [EaselMenuRow(id: "move-to-page", title: "Move to Page", symbol: "arrow.right.doc.on.clipboard", isEnabled: movable,
                             children: children)]
    }
}

@MainActor
extension EaselCanvasView {
    func exportPagesPDF(title: String, pages snapshots: [UUID: EaselPageSnapshot]) -> Data? {
        let full = session.fullDocument
        let exported = EaselPages.exportedPages(full)
        guard exported.count > 1 else {
            guard let only = exported.first, only.id != session.currentPage else { return exportPDF(title: title, pages: snapshots) }
            return withPageShown(only.id) { exportPDF(title: title) }
        }
        let shown = session.currentPage
        let combined = PDFDocument()
        let outline = PDFOutline()
        for page in exported {
            let data = withPageShown(page.id) { exportPDF(title: title, pages: page.id == shown ? snapshots : [:]) }
            guard let data, let part = PDFDocument(data: data), let pdfPage = part.page(at: 0) else { return nil }
            combined.insert(pdfPage, at: combined.pageCount)
            let entry = PDFOutline()
            entry.label = page.name
            entry.destination = PDFDestination(page: pdfPage, at: NSPoint(x: 0, y: pdfPage.bounds(for: .mediaBox).maxY))
            outline.insertChild(entry, at: outline.numberOfChildren)
        }
        combined.outlineRoot = outline
        combined.documentAttributes = [PDFDocumentAttribute.titleAttribute: title, PDFDocumentAttribute.creatorAttribute: "Parc"]
        return combined.dataRepresentation()
    }

    private func withPageShown<T>(_ page: UUID, _ body: () -> T) -> T {
        let previous = session.page
        guard page != session.currentPage else { return body() }
        session.show(page)
        defer { session.show(previous) }
        return body()
    }
}

struct EaselPageFlip {
    let direction: CGFloat
    let snapshot: NSImage?
    let reduced: Bool
}

@MainActor
extension EaselCanvasView {
    private static let pageFlipKey = "easel-page-flip"

    func beginPageFlip(to target: UUID?) -> EaselPageFlip? {
        settlePageFlip()
        guard canAnimateObjects, fixedCanvasSize == nil, let scroll = enclosingScrollView, scroll.contentView.layer != nil else { return nil }
        let pages = visitablePages
        let from = pages.firstIndex { $0.id == session.currentPage }, to = pages.firstIndex { $0.id == target }
        let direction: CGFloat = (from ?? 0) <= (to ?? 0) ? 1 : -1
        let reduced = feedbackReducesMotion
        var snapshot: NSImage?
        let visible = visibleRect
        if !reduced, !items.contains(where: \.ownsEmbeddedPage), !visible.isEmpty, visible.width * visible.height < 16_000_000,
           let rep = bitmapImageRepForCachingDisplay(in: visible) {
            cacheDisplay(in: visible, to: rep)
            let image = NSImage(size: visible.size)
            image.addRepresentation(rep)
            snapshot = image
        }
        return EaselPageFlip(direction: direction, snapshot: snapshot, reduced: reduced)
    }

    func playPageFlip(_ flip: EaselPageFlip) {
        guard let scroll = enclosingScrollView, let layer = scroll.contentView.layer, canAnimateObjects else { return }
        let clip = scroll.contentView
        let duration = flip.reduced ? EaselFeedbackCurve.reducedFade : EaselFeedbackCurve.page
        let timing = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        let slides = !flip.reduced && !items.contains(where: \.ownsEmbeddedPage)
        let travel = CGFloat(EaselFeedbackCurve.pageSlide) * flip.direction
        let down: CGFloat = scroll.isFlipped ? 1 : -1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = duration; fade.timingFunction = timing
        layer.add(fade, forKey: Self.pageFlipKey + "-fade")
        if slides {
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = travel * down; slide.toValue = 0; slide.duration = duration; slide.timingFunction = timing
            layer.add(slide, forKey: Self.pageFlipKey + "-slide")
        }
        if let snapshot = flip.snapshot {
            let overlay = EaselCanvasPageFlipOverlay(frame: clip.frame)
            overlay.wantsLayer = true
            overlay.layer?.contents = snapshot
            overlay.layer?.contentsGravity = .resize
            overlay.layer?.opacity = 0
            scroll.addSubview(overlay, positioned: .above, relativeTo: clip)
            canvasFeedback.pageOverlay = overlay
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = 1; out.toValue = 0; out.duration = duration; out.timingFunction = timing
            overlay.layer?.add(out, forKey: Self.pageFlipKey + "-fade")
            if slides {
                let away = CABasicAnimation(keyPath: "transform.translation.y")
                away.fromValue = 0; away.toValue = -travel * down; away.duration = duration; away.timingFunction = timing
                overlay.layer?.add(away, forKey: Self.pageFlipKey + "-slide")
            }
        }
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self, weak overlay = canvasFeedback.pageOverlay] in
            guard let self, let overlay, self.canvasFeedback.pageOverlay === overlay else { return }
            self.settlePageFlip()
        }
    }

    func settlePageFlip() {
        if let overlay = canvasFeedback.pageOverlay {
            overlay.layer?.removeAllAnimations()
            overlay.removeFromSuperview()
            canvasFeedback.pageOverlay = nil
        }
        guard let layer = enclosingScrollView?.contentView.layer else { return }
        layer.removeAnimation(forKey: Self.pageFlipKey + "-fade")
        layer.removeAnimation(forKey: Self.pageFlipKey + "-slide")
    }
}
