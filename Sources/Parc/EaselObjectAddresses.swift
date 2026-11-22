import AppKit
import ParcCore

@MainActor
extension EaselCanvasView {
    func linkMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard context.target == .object, let item = context.items.first, fixedCanvasSize == nil else { return [] }
        let id = item.id
        return [EaselMenuRow(id: "copy-object-link", title: "Copy Link to Object", symbol: "link", perform: guardedMenuAction { canvas in
            canvas.copyLink(toObject: id)
        })]
    }

    func copyLink(toObject id: UUID) {
        guard !session.isClosed, session.document.items.contains(where: { $0.id == id }),
              let url = URL(string: EaselObjectAddress.urlString(easel: session.document.id, object: id)) else {
            NSSound.beep()
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        board.setString(url.absoluteString, forType: .string)
        (window?.windowController as? EaselWindowActions)?.showDocumentToast(.copiedLinks([url]))
    }
}

@MainActor
extension EaselEditorViewController {
    enum ObjectReveal { case shown, missing, notReady }

    func revealObject(_ id: UUID) -> ObjectReveal {
        guard isViewLoaded, !session.isClosed, let window = view.window, !view.isHiddenOrHasHiddenAncestor,
              let scroll = canvas.enclosingScrollView, scroll.contentView.bounds.width > 1, scroll.contentView.bounds.height > 1 else {
            return .notReady
        }
        guard let item = session.document.items.first(where: { $0.id == id }) else { return .missing }
        canvas.showPage(containing: id)
        guard canvas.selectOnly(id) else { return .notReady }
        if window.isKeyWindow { window.makeFirstResponder(canvas) }
        let frame = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        if let plan = EaselViewportMover.plan(for: frame, in: scroll, mode: .focus) { EaselViewportMover().move(scroll, to: plan) }
        return .shown
    }
}
