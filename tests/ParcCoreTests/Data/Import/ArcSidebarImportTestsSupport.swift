import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

enum ArcSidebarImportTestsSupport {
    typealias Item = ArcSidebarImport.Item
    typealias Tab = ArcSidebarImport.Tab
    typealias Destinations = [ArcSidebarImport.ProfileKey: BrowserImportDestination]

    static let profileOne = ArcSidebarImport.ProfileKey.custom(directory: "Profile 1")
    static let profileTwo = ArcSidebarImport.ProfileKey.custom(directory: "Profile 2")
    static let profileThree = ArcSidebarImport.ProfileKey.custom(directory: "Profile 3")
    static let importedAt = Date(timeIntervalSince1970: 1_793_000_000)

    static func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    static func fixtureData() throws -> Data {
        let file = try #require(Bundle.module.url(forResource: "StorableSidebar",
                                                  withExtension: "json", subdirectory: "ArcSidebar"))
        return try Data(contentsOf: file)
    }

    static func loadArc() throws -> ArcSidebarImport {
        try ArcSidebarImport(data: fixtureData())
    }

    static func document(items: [Any], pinned: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [["global": [:]], [
            "items": [["P", ["id": "P", "childrenIds": pinned, "data": ["itemContainer": [:]]]]].flatMap { $0 } + items,
            "spaces": ["S", ["id": "S", "title": "Deep", "profile": ["default": true], "containerIDs": ["pinned", "P"]]],
            "topAppsContainerIDs": []]]]])
    }

    static func roundingFactors(_ items: [Item]) -> [Item] {
        items.map { item in
            switch item {
            case let .split(title, icon, tabs, orientation, factors):
                return .split(title: title, icon: icon, tabs: tabs, orientation: orientation,
                              widthFactors: factors.map { ($0 * 1e6).rounded() / 1e6 })
            case let .folder(title, icon, children): return .folder(title: title, icon: icon, children: roundingFactors(children))
            case .tab, .stackedSplit: return item
            }
        }
    }

    static var allProfiles: [(key: ArcSidebarImport.ProfileKey, name: String)] {
        [(.standard, "Personal"), (profileOne, "Work Profile"), (profileTwo, "Side Projects"), (profileThree, "  Empty  ")]
    }

    struct Imported {
        let store: BrowserStore
        let arc: ArcSidebarImport
        let standardID: UUID
        let existingID: UUID
        let activeBefore: UUID
        let spacesBefore: Int
        let profilesBefore: Int
        let result: Destinations
        let state: BrowserState
        let created: [BrowserSpace]
    }

    @MainActor static func withImport(_ body: (Imported, URL) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try loadArc()
            let importedAt = Self.importedAt
            let store = try BrowserStore(directory: directory, now: { importedAt })
            let standardID = store.state.profiles[0].id
            let existingID = store.createProfile(name: "WORK PROFILE")
            try store.save()
            let activeBefore = store.activeSpaceID
            let spacesBefore = store.state.spaces.count
            let profilesBefore = store.state.profiles.count
            let result = try store.importArcSidebar(arc, profiles: allProfiles, standardProfileID: standardID)
            let state = store.state
            let imported = Imported(store: store, arc: arc, standardID: standardID, existingID: existingID,
                                    activeBefore: activeBefore, spacesBefore: spacesBefore,
                                    profilesBefore: profilesBefore, result: result, state: state,
                                    created: Array(state.spaces.dropFirst(spacesBefore)))
            try body(imported, directory)
        }
    }

    struct CustomPrimary {
        let before: BrowserState
        let state: BrowserState
        let result: Destinations
        let openedID: UUID
        let namesake: UUID
    }

    @MainActor static func withCustomPrimary(_ body: (CustomPrimary) throws -> Void) throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try loadArc()
            let store = try BrowserStore(directory: directory)
            let opened = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
            let namesake = store.createProfile(name: "Work Profile")
            try store.save()
            let before = store.state
            let result = try store.importArcSidebar(arc, profiles: [(profileOne, "Work Profile"), (profileTwo, "Side Projects")],
                standardProfileID: opened.profileID, primary: profileOne, into: opened.profileID)
            try body(CustomPrimary(before: before, state: store.state, result: result,
                                   openedID: opened.profileID, namesake: namesake))
        }
    }
}
