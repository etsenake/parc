import AppKit
import ParcCore
import ParcKit
import ParcEasels

@MainActor
extension BrowserWindowController {
    func revealEaselObject(_ object: UUID, in easel: UUID, attempt: Int = 0) {
        if let editor = currentEaselEditor, editor.session.document.id == easel {
            switch editor.revealObject(object) {
            case .shown:
                return
            case .missing:
                editor.showExportToast(.standard("That object isn’t on this Easel anymore"))
                return
            case .notReady:
                break
            }
        }
        guard attempt < 12 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.revealEaselObject(object, in: easel, attempt: attempt + 1) }
        }
    }

    func shownEaselPage(_ easel: UUID, profileID: UUID) -> UUID? {
        let order = [documentInputTabID].compactMap { $0 } + store.state.tabs.filter { $0.archivedAt == nil }.map(\.id)
        return order.lazy.compactMap { self.easelEditors[$0] }
            .first { $0.documentID == easel && $0.profileID == profileID }?.editor.canvas.currentPage
    }
}
