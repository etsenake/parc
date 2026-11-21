import AppKit
import Testing
@testable import Parc
import ParcCore

struct SidebarPlusMenuModelTests {
    private static func liveShortcut(_ id: String) -> String {
        switch id {
        case "newTab:": "⌘T"
        case "createEasel:": "⌃⇧E"
        case "createNote:": "⌃⇧N"
        case "split:": "⌃⇧="
        default: ""
        }
    }

    private let rows = SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true, canCreateNote: true,
                                                 canSplit: true, shortcut: liveShortcut)

    @Test func theRowsRunSpaceFolderEaselNoteSplitTab() {
        #expect(rows.map(\.title) == ["New Space", "New Folder", "New Easel", "New Note", "New Split", "New Tab"])
        #expect(rows.map(\.action) == [.space, .folder, .easel, .note, .split, .tab])
    }

    @Test func everyCreationRowIsEnabledInAnOrdinaryWindow() {
        #expect(rows.allSatisfy { $0.enabled })
    }

    @Test func theMenuIsNotTheSpaceContextMenu() {
        let excluded = ["Boost", "Settings", "Theme", "Rename", "preview"]
        #expect(!rows.contains { row in excluded.contains { row.title.contains($0) } })
    }

    @Test func theRowsUseTheBundledArtworkAndSymbols() {
        #expect(rows.map(\.symbol) == ["add-space", "folder", "scribble", "doc.text", "split-add-right", "add-tab"])
    }

    @Test(arguments: [(SidebarPlusAction.note, "⌃⇧N"), (.tab, "⌘T"), (.easel, "⌃⇧E"), (.split, "⌃⇧="), (.space, "")])
    func eachRowShowsItsLiveShortcut(action: SidebarPlusAction, shortcut: String) {
        #expect(rows.first { $0.action == action }?.shortcut == shortcut)
    }

    @Test(arguments: [(true, false), (false, true)])
    func easelAndNoteAvailabilityAreIndependent(easel: Bool, note: Bool) {
        let rows = SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: easel, canCreateNote: note, canSplit: true)
        #expect(rows.first { $0.action == .easel }?.enabled == easel)
        #expect(rows.first { $0.action == .note }?.enabled == note)
    }

    @Test func aPrivateWindowStillCreatesATab() {
        let rows = SidebarPlusMenuModel.rows(privateBrowsing: true, canCreateEasel: false, canCreateNote: false, canSplit: false)
        #expect(rows.first { $0.action == .tab }?.enabled == true)
    }

    @Test func aPrivateWindowDisablesEverythingButNewTab() {
        let rows = SidebarPlusMenuModel.rows(privateBrowsing: true, canCreateEasel: false, canCreateNote: false, canSplit: false)
        #expect(rows.filter { $0.action != .tab }.allSatisfy { !$0.enabled })
    }
}

@MainActor
struct SidebarPlusMenuArtworkTests {
    private var fixtures: URL? { Bundle.module.url(forResource: "SidebarPlusMenu", withExtension: nil) }

    @Test func theArtworkComesFromTheAppBundlesSidebarPlusMenuResources() {
        #expect(SidebarPlusMenuArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("SidebarPlusMenu", isDirectory: true))
    }

    @Test(arguments: ["add-space", "split-add-right", "add-tab"])
    func eachTemplateLoadsAt28PointsWithItsDoubleRendition(name: String) throws {
        let directory = try #require(fixtures)
        let image = try #require(SidebarPlusMenuArtwork.image(name, in: directory))
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 28, height: 28))
        #expect(image.representations.contains { $0.pixelsWide == 56 })
    }

    @Test func anSFSymbolRowDoesNotResolveAsCopiedArtwork() throws {
        let directory = try #require(fixtures)
        #expect(SidebarPlusMenuArtwork.image("folder", in: directory) == nil)
    }
}
