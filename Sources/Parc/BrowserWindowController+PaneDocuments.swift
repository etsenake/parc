import AppKit
import ParcCore

extension BrowserWindowController {
    func paneDocumentRoutes(_ tabID: UUID?) -> [PaneDocumentRoute] {
        guard let tabID, currentTabID == tabID, selectedTabIDs.contains(tabID), activePeek == nil,
              let tab = store.state.tab(tabID, where: { $0.archivedAt == nil }) else { return [.newTab] }
        let holdsWebPage = tab.showsNoteOverPage || (!InternalPage.isInternal(tab.url) && !BrowserState.isBlankPage(tab.url))
        return PaneDocumentRoute.routes(paneCount: selectedTabIDs.count, paneHoldsWebPage: holdsWebPage)
    }

    @discardableResult
    func openNote(url: URL, inPane tabID: UUID?) -> Bool {
        let routes = paneDocumentRoutes(tabID)
        guard let tabID, routes != [.newTab], let file = InternalPage.noteFile(url) else { return openNote(url: url) }
        guard canCreateNote else { return false }
        guard NoteFilePaths.isOpenableFile(file) else {
            showNoteError(NoteFilePaths.itemExists(file) ? NoteFileError.notANote : NoteFileError.missing)
            return true
        }
        for route in routes {
            switch route {
            case .newTab:
                return openNote(url: url)
            case .overPage:
                if openDocumentOverPage(.note(file), title: noteFileTitle(file), sourceID: tabID,
                                        page: browsers[tabID]?.nativePage, anchor: url.fragment) { return true }
            case .replacePane:
                return showDocument(.note(file), title: InternalPage.noteTitle(noteFileTitle(file), file: file),
                                    inPane: tabID, anchor: url.fragment)
            }
        }
        return false
    }

    func openEasel(id: UUID, title: String, inPane tabID: UUID?) {
        let routes = paneDocumentRoutes(tabID)
        guard let tabID, routes != [.newTab] else { openEasel(id: id, title: title); return }
        guard canCreateNote else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for route in routes {
            switch route {
            case .newTab:
                openEasel(id: id, title: title); return
            case .overPage:
                if openDocumentOverPage(.easel(id), title: title, sourceID: tabID,
                                        page: browsers[tabID]?.nativePage) { return }
            case .replacePane:
                if !showDocument(.easel(id), title: name.isEmpty ? "Untitled Easel" : name, inPane: tabID) { NSSound.beep() }
                return
            }
        }
    }

    func createsDocumentInPane(_ command: KeyboardShortcuts.MenuCommand, tabID: UUID) -> Bool {
        switch command.id {
        case "createNote:":
            guard paneDocumentRoutes(tabID) != [.newTab], canCreateNote else { return false }
            do {
                let file = try NoteFolderPreferences.library(for: activeProfileID).createNote()
                openNote(url: file, inPane: tabID)
            } catch { showNoteError(error) }
            return true
        case "createEasel:":
            guard paneDocumentRoutes(tabID) != [.newTab], canCreateNote else { return false }
            do {
                let easels = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: activeProfileID))
                let session = try easels.create()
                openEasel(id: session.document.id, title: session.document.title, inPane: tabID)
            } catch { showEaselError(error) }
            return true
        default:
            return false
        }
    }

    private func showDocument(_ page: InternalPage, title: String, inPane tabID: UUID, anchor: String? = nil) -> Bool {
        guard currentTabID == tabID, selectedTabIDs.contains(tabID), peekPages(forTabID: tabID).isEmpty,
              nativeFullscreenTabID != tabID, !closingTabIDs.contains(tabID), !transferringTabIDs.contains(tabID),
              !store.retiringTabIDs.contains(tabID), prepareNotesToClose([tabID]) else { return false }
        closeLibrary(restoreFocus: false)
        let shows = page.matcher()
        var shown = false
        performWindowCommand {
            requestedURLs.removeValue(forKey: tabID)
            store.updateTab(tabID, title: title, url: page.urlString)
            shown = store.state.tab(tabID).map { shows($0.url) } == true
        }
        guard shown else { return false }
        focusSelectedLocalContent()
        if let anchor, !anchor.isEmpty { revealNoteAnchor(anchor, inTab: tabID) }
        return true
    }
}
