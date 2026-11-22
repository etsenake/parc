import Foundation
import Testing
@testable import ParcCore

extension SidebarSplitCopyTestsSupport {
    @MainActor
    struct SidebarSplitCopyItemPersistenceTests {
        @Test func aCopiedNoteIsANewEntryForTheSameDocument() throws {
            let i = try Items()
            let noteCopy = try i.place([.tab(i.note.id)], i.targetLocation)
            #expect(i.store.state.tab(noteCopy.tabIDs[0]).map { $0.savedURL == i.note.savedURL && $0.id != i.note.id } == true)
            #expect(noteCopy.openTabIDs.isEmpty)
        }

        @Test func copyingANoteRequiresItsValidatedDocument() throws {
            let i = try Items()
            let noteOnly = try #require(i.copy([.tab(i.note.id)]))
            #expect(!i.store.canCopySidebarItems(noteOnly, to: i.targetLocation, before: nil, destinations: i.sources(noteOnly), documents: [:]))
        }

        @Test func aFolderThatMovedDuringTheDragNoLongerMatchesTheGesture() throws {
            let i = try Items()
            let nestedOnly = try #require(i.copy([.folder(i.nested.id)]))
            var reparented = i.store.state
            reparented.folders[reparented.folders.firstIndex { $0.id == i.nested.id }!].parentID = i.target.id
            reparented.sidebarItemOrder[i.outerLocation.key] = [.tab(i.inOuter.id)]
            #expect(SidebarItemsCopy(items: [.folder(i.nested.id)], spaceID: i.here.id, profileID: i.profile.id, state: reparented)?.matchesPlacement(of: nestedOnly) == false)
        }

        @Test func aFolderWhosePageIsClosingRefusesTheCopy() throws {
            let i = try Items()
            var pending: ((Bool) -> Void)?
            i.store.requestPageRetirement = { _, _, done in pending = done }
            i.store.closeTabs([i.inOuter.id]) { _ in }
            #expect(!i.can([.folder(i.outer.id)], i.targetLocation))
            pending?(false)
            i.store.requestPageRetirement = nil
        }

        @Test func aBigCopyOpensOnlyTheFirstFiveItemsAndStaysSaved() throws {
            let i = try Items()
            var bulk = i.initial
            var bulkRoots: [SidebarItemReference] = []
            func tab(_ title: String) -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: i.here.id, profileID: i.profile.id, url: "https://saved.invalid/" + title, title: title,
                    kind: .pinned, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                    savedURL: "https://saved.invalid/" + title, savedTitle: title)
            }
            for index in 0..<6 {
                let a = tab("SplitA\(index)"), b = tab("SplitB\(index)")
                bulk.tabs += [a, b]
                bulk.splitLayouts.append(BrowserSplitLayout(sidebarAnchorID: a.id, spaceID: i.here.id, tabIDs: [a.id, b.id], widthFactors: [0.5, 0.5]))
                bulkRoots.append(.split(bulk.splitLayouts.last!.id))
            }
            for index in 0..<3 {
                let extra = tab("Extra\(index)")
                bulk.tabs.append(extra)
                bulkRoots.append(.tab(extra.id))
            }
            let bulkRoot = i.root.appendingPathComponent("Bulk-" + UUID().uuidString)
            try SidebarSplitCopyTestsSupport.write(bulk, to: bulkRoot)
            let bulkStore = try BrowserStore(directory: bulkRoot)
            let many = try #require(SidebarItemsCopy(items: bulkRoots, spaceID: i.here.id, profileID: i.profile.id, state: bulkStore.state))
            let result = try #require(try bulkStore.copySidebarItems(many, to: i.todayLocation, before: nil, destinations: i.sources(many)))
            #expect(result.tabIDs.count == 15)
            #expect(result.openTabIDs.count == 10)
        }

        @Test func everyOptionDragCopyIsSaved() throws {
            let i = try Items()
            let looseCopy = try i.place([.tab(i.loose.id)], i.todayLocation, before: .tab(i.today.id))
            let folderCopy = try i.place([.folder(i.outer.id)], i.targetLocation)
            let mixed = try i.place([.tab(i.loose.id), .folder(i.outer.id), .split(i.rootSplit.id)], i.targetLocation)
            let away = try i.place([.tab(i.loose.id), .folder(i.outer.id)], i.therePinned)
            let noteCopy = try i.place([.tab(i.note.id)], i.targetLocation)
            let reload = try BrowserStore(directory: i.root)
            #expect((looseCopy.tabIDs + folderCopy.tabIDs + mixed.tabIDs + away.tabIDs + noteCopy.tabIDs).allSatisfy { reload.state.tab($0) != nil })
        }
    }
}
