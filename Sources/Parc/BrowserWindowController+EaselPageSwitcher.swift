import AppKit
import ParcCore
import ParcKit
import ParcEasels

@MainActor
extension BrowserWindowController {
    func revealEaselPage(_ page: UUID, in easel: UUID, attempt: Int = 0) {
        if let editor = currentEaselEditor, editor.session.document.id == easel, editor.isViewLoaded, editor.view.window != nil {
            if editor.session.document.pages?.contains(where: { $0.id == page }) == true {
                editor.canvas.showPage(page)
            } else {
                editor.showExportToast(.standard("That page isn’t on this Easel anymore"))
            }
            return
        }
        guard attempt < 12 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.revealEaselPage(page, in: easel, attempt: attempt + 1) }
        }
    }
}
