import Combine
import Foundation

@main @MainActor
struct EaselTabIconsTests {
    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    static var root: URL!
    static var notes: URL!
    static var heard: [Set<String>?] = []
    static var cancellables: [AnyCancellable] = []

    static func main() {
        exitOnFailure {
            EaselTabIcons.worker = .inline
            root = NoteFileTestSupport.makeFolder("easel-tab-icons")
            notes = NoteFileTestSupport.makeFolder("easel-tab-icon-notes")
            defer { NoteFileTestSupport.remove(root); NoteFileTestSupport.remove(notes) }
            try savedIcons()
            try liveChanges()
            try customEmoji()
            try removal()
            keys()
            print("EaselTabIconsTests passed")
        }
    }

    static func fresh(_ store: EaselStore) -> EaselTabIcons {
        let icons = EaselTabIcons()
        let directory = store.directory
        icons.directory = { _ in directory }
        icons.store = { $0.standardizedFileURL.path == directory.standardizedFileURL.path ? store : nil }
        icons.notesFolder = { _ in notes }
        heard = []
        cancellables = [icons.changes.sink { heard.append($0) }]
        return icons
    }

    static func makeStore(_ name: String) throws -> EaselStore {
        try EaselStore(directory: root.appendingPathComponent(name, isDirectory: true))
    }

    static func savedIcons() throws {
        let store = try makeStore("saved")
        let plain = try store.create(), party = try store.create(), picture = try store.create()
        try party.perform("Add Icon") { $0.icon = EaselPageIcon.emoji("🎉") }
        let asset = try picture.importPNG(png)
        try picture.perform("Add Icon") { $0.icon = EaselPageIcon.image(assetID: asset) }
        let reopened = try makeStore("saved")
        let icons = fresh(reopened)
        let profile = UUID()
        expectEqual(icons.lookup(profile: profile, id: plain.document.id), .known(nil), "an Easel without an icon has none")
        expectEqual(icons.lookup(profile: profile, id: party.document.id), .known(.emoji("🎉")), "a saved emoji icon is read off the file")
        guard case .known(.image(let file)?) = icons.lookup(profile: profile, id: picture.document.id) else {
            failTest("a saved image icon should resolve to its asset")
        }
        expectEqual(file.lastPathComponent, asset, "the image icon points at the Easel's own asset")
        expectEqual(icons.lookup(profile: profile, id: UUID()), .known(nil), "a missing Easel falls back to the mark")
        let lonely = EaselTabIcons()
        expectEqual(lonely.lookup(profile: UUID(), id: UUID()), .known(nil), "an unknown Profile falls back to the mark")
    }

    static func liveChanges() throws {
        let store = try makeStore("live")
        let session = try store.create()
        let id = session.document.id
        let icons = fresh(store)
        let profile = UUID()
        expectEqual(icons.lookup(profile: profile, id: id), .known(nil), "a fresh Easel has no icon")
        let key = icons.key(profile: profile, id: id)!
        try session.perform("Change Icon") { $0.icon = EaselPageIcon.emoji("🚀") }
        expectEqual(icons.lookup(profile: profile, id: id), .known(.emoji("🚀")), "a live Easel's icon shows at once")
        expect(heard.contains { EaselTabIcons.touches($0, key: key) }, "changing the icon tells every listener")
        heard = []
        try session.undo()
        expectEqual(icons.lookup(profile: profile, id: id), .known(nil), "undo takes the icon back off")
        expect(heard.contains { EaselTabIcons.touches($0, key: key) }, "undo tells listeners too")
        heard = []
        try session.redo()
        try session.perform("Rename Easel") { $0.title = "Renamed" }
        expect(heard.count == 1, "a rename alone doesn't tell anyone the icon moved")
        let other = fresh(store)
        expectEqual(other.lookup(profile: profile, id: id), .known(.emoji("🚀")), "another listener follows the same live session")
        let asset = try session.importPNG(png)
        try session.perform("Change Icon") { $0.icon = EaselPageIcon.image(assetID: asset) }
        guard case .known(.image(let file)?) = other.lookup(profile: profile, id: id) else {
            failTest("an image icon should resolve live")
        }
        expectEqual(file.lastPathComponent, asset, "live image icons point at the asset")
    }

    static func customEmoji() throws {
        let store = try makeStore("custom")
        let session = try store.create()
        let id = session.document.id
        try session.perform("Change Icon") { $0.icon = EaselPageIcon.custom(named: "party-parrot") }
        let icons = fresh(store)
        let profile = UUID()
        expectEqual(icons.lookup(profile: profile, id: id), .known(nil), "a custom emoji that isn't in the folder falls back")
        let library = NoteEmojiLibrary.library(root: notes)
        let entry = try library.add(png: png, name: "party-parrot")
        guard case .known(.image(let file)?) = icons.lookup(profile: profile, id: id) else {
            failTest("adding the emoji should light the icon up")
        }
        expectEqual(file.lastPathComponent, entry.file, "the icon uses the folder's emoji image")
        expect(!heard.isEmpty, "adding the emoji tells listeners")
        heard = []
        try library.remove("party-parrot")
        expectEqual(icons.lookup(profile: profile, id: id), .known(nil), "deleting the emoji turns the icon back to the mark")
        expect(!heard.isEmpty, "deleting the emoji tells listeners")
    }

    static func removal() throws {
        let store = try makeStore("removal")
        let session = try store.create()
        let id = session.document.id
        try session.perform("Change Icon") { $0.icon = EaselPageIcon.emoji("🌱") }
        let icons = fresh(store)
        let profile = UUID()
        expectEqual(icons.lookup(profile: profile, id: id), .known(.emoji("🌱")), "the icon is known before the Easel goes")
        try store.delete(id)
        expectEqual(icons.lookup(profile: profile, id: id), .known(nil), "a deleted Easel's icon is forgotten")
        expect(!heard.isEmpty, "deleting an Easel tells listeners")
    }

    static func keys() {
        let directory = URL(fileURLWithPath: "/tmp/easels", isDirectory: true)
        let id = UUID()
        let key = EaselTabIcons.key(directory: directory, id: id)
        expect(EaselTabIcons.touches(nil, key: key), "an unscoped change touches every Easel")
        expect(EaselTabIcons.touches([key], key: key), "a scoped change matches by key")
        expect(!EaselTabIcons.touches([EaselTabIcons.key(directory: directory, id: UUID())], key: key), "other Easels are left alone")
        expect(!key.hasPrefix("/"), "Easel keys never collide with note paths")
    }
}
