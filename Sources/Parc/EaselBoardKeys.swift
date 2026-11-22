import AppKit

@MainActor
extension EaselEditorViewController {
    func performBoardKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, isViewLoaded, let window = view.window, window.isKeyWindow,
              !view.isHiddenOrHasHiddenAncestor, window.attachedSheet == nil,
              (window.firstResponder as? NSTextInputClient)?.hasMarkedText() != true,
              let responder = window.firstResponder as? NSView, responder.isDescendant(of: view),
              !isInsideEmbeddedPage(responder) else { return false }
        return find.handleKeyEquivalent(event)
    }

    private func isInsideEmbeddedPage(_ responder: NSView) -> Bool {
        guard responder.isDescendant(of: canvas), let pages = canvas.pageObjects else { return false }
        return session.document.items.contains { item in
            guard item.ownsEmbeddedPage, let surface = pages.surface(for: item) else { return false }
            return responder.isDescendant(of: surface)
        }
    }
}
