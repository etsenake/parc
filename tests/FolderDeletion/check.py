#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
source = (root / 'Sources/ParcApp/SidebarView.swift').read_text()
def body(marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 0
    for end in range(opening, len(source)):
        depth += {'{': 1, '}': -1}.get(source[end], 0)
        if depth == 0:
            return source[start:end + 1]

start = source.index('        let deleteFolder', source.index('let duplicateFolder ='))
end = source.index('        return menu', start)
menu = source[start:end]
method = body('    func performFolderDeletion(') if '    func performFolderDeletion(' in source else ''
edit = body('    @objc func delete(').replace('@objc ', '') if '    @objc func delete(' in source else ''
keys = body('    func handleFolderDeletionKey(') if '    func handleFolderDeletionKey(' in source else ''
plural = body('    private func handleSelectionDeleteKey(').replace('private ', '')
program = '''import AppKit
@MainActor enum NSSound { static var beeps = 0; static func beep() { beeps += 1 } }
struct Folder { let id: UUID; let spaceID: UUID }
struct State { var folders: [Folder] }
enum Item { case folder(UUID), tab(UUID) }
struct Selection { var singleItem: Item?; var items: [Item] = [] }
final class Window { var isKeyWindow = true; weak var firstResponder: AnyObject? }
@MainActor final class Harness {
    var isPrivateBrowsing = false
    var isPresented = true
    var ownsSelectionFocus = true
    var window: Window? = Window()
    var itemSelection = Selection()
    var activeSpaceID: UUID?
    var hierarchyState: State?
    var prepareFolderDeletion: ((UUID) -> (() -> Bool)?)?
    var holdsOnlyEmptyFolders: (([Item]) -> Bool)?
    var prepareSidebarDeletion: (([Item]) -> (() -> Bool)?)?
    var prepareSidebarClose: (([Item]) -> (() -> Bool)?)?
''' + method + '\n' + keys + '\n' + plural + '\n' + edit + '''
    func menu(_ folder: Folder) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let button = NSButton()
''' + menu + '''
        return menu
    }
}
''' + body('final class MenuAction: NSObject') + '''
@main struct Check {
    @MainActor static func main() {
        _ = NSApplication.shared
        let h = Harness(), space = UUID(), id = UUID()
        let folder = Folder(id: id, spaceID: space)
        h.activeSpaceID = space; h.hierarchyState = State(folders: [folder])
        var revision = 0, preparations = 0, commits = 0
        h.prepareFolderDeletion = { target in
            precondition(target == id)
            preparations += 1
            let captured = revision
            return { guard captured == revision else { return false }; commits += 1; return true }
        }
        let menu = h.menu(folder)
        // Live metadata/page owners change while the row and menu survive.
        revision += 1
        let action = menu.items.first { $0.title == "Delete" }!.representedObject as! MenuAction
        action.block()
        precondition(commits == 1, "Delete must prepare current owners, not beep on the render-time lease")
        action.block()
        precondition(commits == 2, "A cancelled/reused menu must prepare a new one-shot action")
        h.hierarchyState = State(folders: [])
        action.block()
        precondition(commits == 2, "Removed folder cannot be retargeted")
        h.hierarchyState = State(folders: [folder]); h.activeSpaceID = UUID()
        action.block()
        precondition(commits == 2, "Changed Space cannot retarget a cached row")
        h.activeSpaceID = space; h.isPrivateBrowsing = true
        action.block()
        precondition(commits == 2 && preparations == 2, "Private context cannot delete saved folders")
        // Restored rows exist before live pages arrive. Empty folders and
        // folders with unloaded tabs also hold the *window* lease, whose
        // selection/hierarchy may change without loading a descendant page.
        for scenario in ["restored at launch, page attached later", "empty folder, window selection changes", "unloaded descendants, window selection changes"] {
            let restored = Harness(), restoredFolder = Folder(id: UUID(), spaceID: space)
            restored.activeSpaceID = space; restored.hierarchyState = State(folders: [restoredFolder])
            var windowRevision = 0, accepted = false
            restored.prepareFolderDeletion = { _ in
                let expected = windowRevision
                return { guard expected == windowRevision else { return false }; accepted = true; return true }
            }
            let restoredMenu = restored.menu(restoredFolder)
            windowRevision += 1
            (restoredMenu.items.first { $0.title == "Delete" }!.representedObject as! MenuAction).block()
            precondition(accepted, scenario)
        }
        h.isPrivateBrowsing = false
        h.window?.firstResponder = h
        h.itemSelection.singleItem = .folder(id)
        func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        for code: UInt16 in [51, 117] {
            precondition(h.handleFolderDeletionKey(event(code)))
        }
        precondition(commits == 4, "Both Delete keys dispatch singleton folder deletion")
        h.isPresented = false
        precondition(!h.handleFolderDeletionKey(event(51)))
        h.isPresented = true; h.window?.isKeyWindow = false
        precondition(!h.handleFolderDeletionKey(event(51)))
        h.window?.isKeyWindow = true; h.window?.firstResponder = nil
        precondition(!h.handleFolderDeletionKey(event(51)))
        h.window?.firstResponder = h
        precondition(!h.handleFolderDeletionKey(event(51, .command)))
        precondition(!h.handleFolderDeletionKey(event(125)))
        h.itemSelection.singleItem = nil; h.itemSelection.items = [.folder(id), .tab(UUID())]
        precondition(!h.handleFolderDeletionKey(event(51)), "Plural selection stays on existing Close route")
        precondition(commits == 4, "Rejected keys never delete")
        let quiet = NSSound.beeps
        h.itemSelection.singleItem = .folder(id); h.isPrivateBrowsing = true
        precondition(h.handleFolderDeletionKey(event(51)) && NSSound.beeps == quiet + 1 && commits == 4, "A single folder Delete that cannot act beeps")
        h.isPrivateBrowsing = false; h.itemSelection.singleItem = nil
        let emptyFolders: Set<UUID> = [UUID(), UUID()], empties = emptyFolders.map(Item.folder)
        var deletions = 0, closes = 0, deletionResult: Bool? = true, closeResult: Bool? = true, deleted: [Item] = [], closed: [Item] = []
        h.holdsOnlyEmptyFolders = { items in
            items.allSatisfy { if case .folder(let folder) = $0 { return emptyFolders.contains(folder) }; return false }
        }
        h.prepareSidebarDeletion = { items in deletionResult.map { result in { deleted = items; deletions += 1; return result } } }
        h.prepareSidebarClose = { items in closeResult.map { result in { closed = items; closes += 1; return result } } }
        h.itemSelection.items = empties; h.handleSelectionDeleteKey()
        precondition(deletions == 1 && closes == 0 && NSSound.beeps == quiet + 1 && deleted.count == 2, "Delete on only empty folders takes the selection's folder Delete, not Close")
        let tabbed: [Item] = [.folder(id), .tab(UUID())]
        h.itemSelection.items = tabbed; h.handleSelectionDeleteKey()
        precondition(deletions == 1 && closes == 1 && NSSound.beeps == quiet + 1 && closed.count == 2, "Selections holding tabs keep Close")
        h.itemSelection.items = empties + [.folder(id)]; h.handleSelectionDeleteKey()
        precondition(deletions == 1 && closes == 2 && closed.count == 3, "Empty folders mixed with a tab-holding folder keep Close")
        deletionResult = nil; h.itemSelection.items = empties; h.handleSelectionDeleteKey()
        precondition(deletions == 1 && closes == 2 && NSSound.beeps == quiet + 2, "Unavailable folder deletion beeps instead of closing")
        deletionResult = false; h.handleSelectionDeleteKey()
        precondition(deletions == 2 && closes == 2 && NSSound.beeps == quiet + 3, "A refused folder deletion beeps")
        closeResult = nil; h.itemSelection.items = tabbed; h.handleSelectionDeleteKey()
        precondition(closes == 2 && NSSound.beeps == quiet + 4, "Unavailable Close beeps")
        closeResult = false; h.handleSelectionDeleteKey()
        precondition(closes == 3 && NSSound.beeps == quiet + 5, "A refused Close beeps")
        h.holdsOnlyEmptyFolders = nil; closeResult = true; deletionResult = true; h.itemSelection.items = empties; h.handleSelectionDeleteKey()
        precondition(deletions == 2 && closes == 4 && NSSound.beeps == quiet + 5, "Without a folder answer Delete keeps Close")
        h.itemSelection.singleItem = .folder(id)
        h.delete(nil)
        precondition(commits == 5, "Edit Delete dispatches the selected folder")
        h.ownsSelectionFocus = false; h.delete(nil)
        precondition(commits == 5, "Edit Delete preserves another responder's ownership")
        print("PASS: restored, empty, unloaded folder menus; both Delete keys and focus guards")
    }
}
'''
if not keys:
    start = program.index('        h.isPrivateBrowsing = false\n        h.window?.firstResponder = h')
    end = program.index('        print("PASS:', start)
    program = program[:start] + program[end:]
with tempfile.TemporaryDirectory(prefix='parc-folder-delete-') as tmp:
    swift = Path(tmp) / 'Check.swift'
    swift.write_text(program)
    binary = Path(tmp) / 'check'
    subprocess.run(['xcrun', 'swiftc', str(root / 'tests/Support/TestFailure.swift'), '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
keys = body('    override func keyDown(with event: NSEvent)')
assert 'handleFolderDeletionKey(event)' in keys and 'handleSelectionDeleteKey()' in keys, 'Singleton folder Delete/Backspace must not fall through to NSResponder'
wiring = (root / 'Sources/ParcApp/BrowserWindowController+Sidebar.swift').read_text()
assert 'sidebar.holdsOnlyEmptyFolders = ' in wiring and '?.holdsOnlyEmptyFolders == true' in wiring, 'Window controller answers the empty-folder Delete question from the keyboard-close model'
print('PASS: singleton folder keyboard routing')
