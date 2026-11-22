import AppKit
import Combine
import ParcEngine

extension BrowserWindowController {
    func retireShortcutHint() {
        if let command = shortcutHintCommand, let page = shortcutHintPage { _ = page.consumeShortcutHint(command) }
        removeShortcutHint(animated: true)
    }
    func removeShortcutHint(animated: Bool = false) {
        let hint = shortcutHint; shortcutHint = nil
        shortcutHintCommand = nil; shortcutHintPage = nil
        hint?.dismiss(animated: animated)
    }

    func existingNativeSelection(_ binding: PCNativeBrowserWindow,
                                         _ page: PCNativePage) -> (UUID, PCBrowserView)? {
        guard binding === nativeBinding, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, transferringTabIDs.isEmpty, !page.isClosed,
              PCNativeBrowserApplication.owner(of: page) === binding,
              let (id, view) = browsers.first(where: { $0.value.nativePage === page }),
              ownership.isClaimed(id), ownership.canUse(id, owner: presentationID),
              !closingTabIDs.contains(id), !modelRetirementIDs.contains(id),
              !store.retiringTabIDs.contains(id), page.observer === view, view.delegate === self,
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              browserProfiles[id] == tab.profileID,
              page.profilePath == store.independentEngineProfilePath(for: tab.profileID),
              let window, binding.window === window, view.window === window else { return nil }
        return (id, view)
    }

    func restoreNativeFullscreenPresentation() {
        nativeFullscreenTabID = nil
        if let saved = nativeFullscreenPresentation {
            sidebarPresentation = saved.sidebar; findHost.isHidden = saved.findHidden
        }
        nativeFullscreenPresentation = nil
    }
    func closeCurrentTab() {
        if let peek = activePeek { peek.requestDismiss(.closeShortcut); return }
        if isPopupWindow { window?.performClose(nil); return }
        if let id = currentTabID { closeTab(id) }
    }
    func togglePinFocusedTab() {
        guard !isPrivateBrowsing else { return }
        if let peek = activePeek { promotePeek(peek, split: false); guard activePeek == nil else { return } }
        guard let id = currentTabID, let tab = store.state.tab(id) else { return }
        if tab.kind == .favorite { _ = moveFavoriteToPinned(id) }
        else { store.setKind(id, tab.kind == .pinned ? .today : .pinned) }
    }
}
