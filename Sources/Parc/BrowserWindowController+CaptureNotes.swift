import AppKit
import ParcCore
import ParcEasels
import ParcNotes

extension BrowserWindowController {
    var allowsCaptureNoteDestinations: Bool { !isPrivateBrowsing && !isPopupWindow }

    func captureNoteDestinations(profileID: UUID) throws -> [CaptureNoteDestination] {
        guard allowsCaptureNoteDestinations else { return [] }
        let notes = try NoteFolderPreferences.library(for: profileID).notes()
        let activity = store.state.openTabs.flatMap { tab in
            [InternalPage.noteFile(tab.url), InternalPage.noteFile(tab.savedURL)].compactMap { $0 }.map {
                CaptureNoteDestination.Activity(url: $0, profileID: tab.profileID, date: tab.lastAccessed)
            }
        }
        return CaptureNoteDestination.catalog(notes: notes, activity: activity, profileID: profileID)
    }

    func placeCaptureInNote(_ image: EaselImageInput, target: CaptureNoteTarget, profileID: UUID) throws {
        guard allowsCaptureNoteDestinations, image.isValid, canOpenNoteOverPeek, profileID == activeProfileID,
              presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty else {
            throw CocoaError(.userCancelled)
        }
        let input = NoteCaptureInput(pngData: image.pngData, sourceURL: image.sourceURL?.absoluteString ?? "",
                                     pageTitle: image.pageTitle, capturedAt: image.capturedAt ?? Date(), captureLayout: image.captureLayout)
        let result = try NoteCaptureDelivery.deliver(input, to: target, notesFolder: NoteFolderPreferences.folder(for: profileID))
        pageCapture?.dismiss(restoreFocus: false)
        openNote(url: result.note, overPeek: true)
        revealCapturedBlock(result.block, in: result.note)
    }

    func revealCapturedBlock(_ block: NoteBlockID, in note: URL, attempt: Int = 0) {
        let target = note.standardizedFileURL.resolvingSymlinksInPath()
        if let editor = currentNoteEditor, editor.file.url.standardizedFileURL.resolvingSymlinksInPath() == target,
           editor.reveal(block: block) { return }
        guard attempt < 12 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.revealCapturedBlock(block, in: note, attempt: attempt + 1) }
        }
    }
}
