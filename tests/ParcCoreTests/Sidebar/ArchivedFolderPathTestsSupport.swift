import Foundation
import Testing
@testable import ParcCore

@MainActor
enum ArchivedFolderPathTestsSupport {
    @MainActor final class Fixture {
        let directory: URL
        let profile: BrowserProfile
        let space: BrowserSpace
        let other: BrowserSpace
        let work: BrowserFolder
        let inner: BrowserFolder
        let p0: UUID, p1: UUID, w1: UUID, w2: UUID, i1: UUID, i2: UUID
        let notePage: InternalPage

        var pinned: SidebarContainerLocation { .init(spaceID: space.id, folderID: nil, section: .pinned) }
        var workContents: SidebarContainerLocation { .init(spaceID: space.id, folderID: work.id, section: .pinned) }
        var innerContents: SidebarContainerLocation { .init(spaceID: space.id, folderID: inner.id, section: .pinned) }

        init(archivedNote: Bool = false) throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("parc-archived-folder-paths-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            profile = BrowserProfile(id: UUID(), name: "Original")
            space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            other = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "123456", profileID: profile.id)
            var work = BrowserFolder(id: UUID(), spaceID: space.id, name: "Work")
            work.customIcon = .icon(.bag)
            self.work = work
            var inner = BrowserFolder(id: UUID(), spaceID: space.id, name: "Inner", parentID: work.id)
            inner.isExpanded = false
            self.inner = inner
            let spaceID = space.id, profileID = profile.id
            func tab(_ title: String, folder: UUID?) -> BrowserTab {
                let url = "https://\(title.lowercased()).example/"
                return .init(id: UUID(), spaceID: spaceID, profileID: profileID, url: url, title: title,
                             kind: .pinned, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                             lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
            }
            let p0 = tab("Before", folder: nil), p1 = tab("After", folder: nil)
            let w1 = tab("WorkFirst", folder: work.id), w2 = tab("WorkLast", folder: work.id)
            let i1 = tab("InnerFirst", folder: inner.id)
            var i2 = tab("InnerLast", folder: inner.id)
            notePage = InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md"))
            if archivedNote {
                i2.url = notePage.urlString
                i2.savedURL = notePage.urlString
                i2.archivedAt = Date(timeIntervalSince1970: 1_800_000_000)
                i2.archiveProvenance = ArchiveProvenance(reason: .manual, spaceID: space.id, spaceName: space.name)
            }
            self.p0 = p0.id; self.p1 = p1.id; self.w1 = w1.id; self.w2 = w2.id; self.i1 = i1.id; self.i2 = i2.id
            var state = BrowserState(profiles: [profile], spaces: [space, other], activeSpaceID: space.id)
            state.folders = [work, inner]
            state.tabs = [p0, p1, w1, w2, i1, i2]
            state.sidebarItemOrder[pinned.key] = [.tab(p0.id), .folder(work.id), .tab(p1.id)]
            state.sidebarItemOrder[workContents.key] = [.tab(w1.id), .folder(inner.id), .tab(w2.id)]
            state.sidebarItemOrder[innerContents.key] = [.tab(i1.id), .tab(i2.id)]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func store() throws -> BrowserStore {
            try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        }

        @discardableResult
        func delete(_ items: [SidebarItemReference], in store: BrowserStore) throws -> FolderDeletionUndo {
            let target = try #require(FolderRemovalTarget(items: items, spaceID: space.id, profileID: profile.id, state: store.state))
            var record: FolderDeletionUndo?, result: Result<Bool, Error>?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { result = $0 }
            #expect(try result?.get() == true)
            return try #require(record)
        }

        func putBack(_ id: UUID, in store: BrowserStore, to space: UUID? = nil) throws {
            let destination: ArchiveRestoreDestination = space.map { .putBack(currentSpaceID: $0, requestedSpaceID: $0) }
                ?? .previousSpace(fallbackSpaceID: self.space.id)
            #expect(store.restoreArchivedTab(id, profileID: profile.id, destination: destination) == [id])
        }

        func tab(_ id: UUID, _ store: BrowserStore) throws -> BrowserTab {
            try #require(store.state.tab(id))
        }

        func folderCount(_ id: UUID, _ store: BrowserStore) -> Int { store.state.folders.filter { $0.id == id }.count }
    }
}
