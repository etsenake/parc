import Combine
import Foundation
import Testing
@testable import ParcCore

extension NoteProcessWide {
    @MainActor final class EaselTabIconsTests {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let root: URL
        let notes: URL
        let profile = UUID()
        var heard: [Set<String>?] = []
        var cancellables: [AnyCancellable] = []

        init() {
            EaselTabIcons.worker = .inline
            root = NoteFileTestSupport.makeFolder("easel-tab-icons")
            notes = NoteFileTestSupport.makeFolder("easel-tab-icon-notes")
        }

        deinit {
            NoteFileTestSupport.remove(root)
            NoteFileTestSupport.remove(notes)
        }

        func icons(_ store: EaselStore) -> EaselTabIcons {
            let icons = EaselTabIcons()
            let directory = store.directory
            let notes = notes
            icons.directory = { _ in directory }
            icons.store = { $0.standardizedFileURL.path == directory.standardizedFileURL.path ? store : nil }
            icons.notesFolder = { _ in notes }
            cancellables.append(icons.changes.sink { [weak self] in self?.heard.append($0) })
            return icons
        }

        func store(_ name: String = "easels") throws -> EaselStore {
            try EaselStore(directory: root.appendingPathComponent(name, isDirectory: true))
        }

        func session(icon: EaselPageIcon? = nil) throws -> (EaselStore, EaselSession) {
            let store = try store()
            let session = try store.create()
            if let icon { try session.perform("Change Icon") { $0.icon = icon } }
            return (store, session)
        }

        func imageFile(_ lookup: NoteTabIcons.Lookup) -> URL? {
            guard case .known(.image(let file)?) = lookup else { return nil }
            return file
        }

        @Test func anEaselWithoutAnIconHasNone() throws {
            let id = try store().create().document.id
            #expect(icons(try store()).lookup(profile: profile, id: id) == .known(nil))
        }

        @Test func aSavedEmojiIconIsReadOffTheFile() throws {
            let (_, session) = try session(icon: EaselPageIcon.emoji("🎉"))
            #expect(icons(try store()).lookup(profile: profile, id: session.document.id) == .known(.emoji("🎉")))
        }

        @Test func aSavedImageIconPointsAtTheEaselsOwnAsset() throws {
            let (_, session) = try session()
            let asset = try session.importPNG(png)
            try session.perform("Add Icon") { $0.icon = EaselPageIcon.image(assetID: asset) }
            let file = try #require(imageFile(icons(try store()).lookup(profile: profile, id: session.document.id)))
            #expect(file.lastPathComponent == asset)
        }

        @Test func aMissingEaselFallsBackToTheMark() throws {
            #expect(icons(try store()).lookup(profile: profile, id: UUID()) == .known(nil))
        }

        @Test func anUnknownProfileFallsBackToTheMark() {
            #expect(EaselTabIcons().lookup(profile: UUID(), id: UUID()) == .known(nil))
        }

        @Test func aLiveEaselsIconShowsAtOnceAndTellsListeners() throws {
            let (store, session) = try session()
            let id = session.document.id
            let icons = icons(store)
            #expect(icons.lookup(profile: profile, id: id) == .known(nil))
            let key = try #require(icons.key(profile: profile, id: id))
            try session.perform("Change Icon") { $0.icon = EaselPageIcon.emoji("🚀") }
            #expect(icons.lookup(profile: profile, id: id) == .known(.emoji("🚀")))
            #expect(heard.contains { EaselTabIcons.touches($0, key: key) })
        }

        @Test func undoTakesTheIconBackOffAndTellsListeners() throws {
            let (store, session) = try session()
            let id = session.document.id
            let icons = icons(store)
            _ = icons.lookup(profile: profile, id: id)
            let key = try #require(icons.key(profile: profile, id: id))
            try session.perform("Change Icon") { $0.icon = EaselPageIcon.emoji("🚀") }
            heard = []
            try session.undo()
            #expect(icons.lookup(profile: profile, id: id) == .known(nil))
            #expect(heard.contains { EaselTabIcons.touches($0, key: key) })
        }

        @Test func aRenameAloneDoesNotTellAnyoneTheIconMoved() throws {
            let (store, session) = try session()
            let icons = icons(store)
            _ = icons.lookup(profile: profile, id: session.document.id)
            try session.perform("Change Icon") { $0.icon = EaselPageIcon.emoji("🚀") }
            heard = []
            try session.perform("Rename Easel") { $0.title = "Renamed" }
            #expect(heard.isEmpty)
        }

        @Test func anotherListenerFollowsTheSameLiveSessionIncludingImageIcons() throws {
            let (store, session) = try session()
            let id = session.document.id
            _ = icons(store).lookup(profile: profile, id: id)
            try session.perform("Change Icon") { $0.icon = EaselPageIcon.emoji("🚀") }
            let other = icons(store)
            #expect(other.lookup(profile: profile, id: id) == .known(.emoji("🚀")))
            let asset = try session.importPNG(png)
            try session.perform("Change Icon") { $0.icon = EaselPageIcon.image(assetID: asset) }
            let file = try #require(imageFile(other.lookup(profile: profile, id: id)))
            #expect(file.lastPathComponent == asset)
        }

        @Test func aCustomEmojiThatIsNotInTheFolderFallsBack() throws {
            let (store, session) = try session(icon: EaselPageIcon.custom(named: "party-parrot"))
            #expect(icons(store).lookup(profile: profile, id: session.document.id) == .known(nil))
        }

        @Test func addingTheCustomEmojiLightsTheIconUpAndTellsListeners() throws {
            let (store, session) = try session(icon: EaselPageIcon.custom(named: "party-parrot"))
            let icons = icons(store)
            _ = icons.lookup(profile: profile, id: session.document.id)
            let entry = try NoteEmojiLibrary.library(root: notes).add(png: png, name: "party-parrot")
            let file = try #require(imageFile(icons.lookup(profile: profile, id: session.document.id)))
            #expect(file.lastPathComponent == entry.file)
            #expect(!heard.isEmpty)
        }

        @Test func deletingTheCustomEmojiTurnsTheIconBackToTheMarkAndTellsListeners() throws {
            let (store, session) = try session(icon: EaselPageIcon.custom(named: "party-parrot"))
            let library = NoteEmojiLibrary.library(root: notes)
            _ = try library.add(png: png, name: "party-parrot")
            let icons = icons(store)
            _ = icons.lookup(profile: profile, id: session.document.id)
            heard = []
            try library.remove("party-parrot")
            #expect(icons.lookup(profile: profile, id: session.document.id) == .known(nil))
            #expect(!heard.isEmpty)
        }

        @Test func aDeletedEaselsIconIsForgottenAndListenersAreTold() throws {
            let (store, session) = try session(icon: EaselPageIcon.emoji("🌱"))
            let id = session.document.id
            let icons = icons(store)
            #expect(icons.lookup(profile: profile, id: id) == .known(.emoji("🌱")))
            try store.delete(id)
            #expect(icons.lookup(profile: profile, id: id) == .known(nil))
            #expect(!heard.isEmpty)
        }

        @Test func aMissingPictureFallsBackToTheMarkAndTellsListeners() throws {
            let (store, session) = try session()
            let asset = try session.importPNG(png)
            try session.perform("Change Icon") { $0.icon = EaselPageIcon.image(assetID: asset) }
            let icons = icons(store)
            #expect(imageFile(icons.lookup(profile: profile, id: session.document.id)) != nil)
            heard = []
            store.removeAssets([asset])
            #expect(icons.lookup(profile: profile, id: session.document.id) == .known(nil))
            #expect(!heard.isEmpty)
        }
    }
}

@MainActor
struct EaselTabIconKeyTests {
    private static let directory = URL(fileURLWithPath: "/tmp/easel-availability", isDirectory: true)

    @Test func aPresentStoreIsOnlyCheckedOnce() {
        var checks = 0
        let availability = EaselStoreAvailability(exists: { _ in checks += 1; return true }, center: NotificationCenter())
        #expect(availability.contains(Self.directory) && availability.contains(Self.directory) && availability.contains(Self.directory))
        #expect(checks == 1)
    }

    @Test func aRemovedEaselChecksTheStoreAgain() {
        var checks = 0
        let center = NotificationCenter()
        let availability = EaselStoreAvailability(exists: { _ in checks += 1; return true }, center: center)
        _ = availability.contains(Self.directory)
        center.post(name: .easelDocumentRemoved, object: UUID())
        #expect(availability.contains(Self.directory))
        #expect(checks == 2)
    }

    @Test func aMissingStoreIsCheckedEveryTimeSoANewOneShowsUp() {
        var checks = 0
        let absent = EaselStoreAvailability(exists: { _ in checks += 1; return false }, center: NotificationCenter())
        #expect(!absent.contains(Self.directory) && !absent.contains(Self.directory))
        #expect(checks == 2)
    }

    private static let id = UUID()
    private static let key = EaselTabIcons.key(directory: URL(fileURLWithPath: "/tmp/easels", isDirectory: true), id: id)

    @Test func anUnscopedChangeTouchesEveryEasel() {
        #expect(EaselTabIcons.touches(nil, key: Self.key))
    }

    @Test func aScopedChangeMatchesByKey() {
        #expect(EaselTabIcons.touches([Self.key], key: Self.key))
    }

    @Test func otherEaselsAreLeftAlone() {
        let other = EaselTabIcons.key(directory: URL(fileURLWithPath: "/tmp/easels", isDirectory: true), id: UUID())
        #expect(!EaselTabIcons.touches([other], key: Self.key))
    }

    @Test func easelKeysNeverCollideWithNotePaths() {
        #expect(!Self.key.hasPrefix("/"))
    }
}
