import Foundation
import Testing
@testable import ParcCore

extension SpaceDeletionTestsSupport {
    @MainActor
    struct SpaceDeletionConversionTests {
        @MainActor struct Conversion {
            let state: BrowserState
            let store: BrowserStore
            let directory: URL
            let source: BrowserSpace
            let destinationID: UUID
            let conversion: SpaceFolderConversion
            let today: BrowserTab

            init(fixture: Fixture) throws {
                var state = fixture.initial
                source = state.spaces[0]
                destinationID = state.spaces[1].id
                state.spaces[1].profileID = source.profileID
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-delete-\(UUID())")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
                store = try BrowserStore(directory: directory)
                conversion = SpaceFolderConversion(source: source.id, destination: destinationID, state: store.state,
                                                   documents: fixture.references)!
                today = state.tabs.filter { $0.kind != .favorite }.first { $0.kind == .today }!
                self.state = state
            }
        }

        @Test func aSameProfileConversionRetainsPhysicalPageOwners() throws {
            let fixture = try Fixture()
            let conversion = try Conversion(fixture: fixture)
            defer { try? FileManager.default.removeItem(at: conversion.directory) }
            var retirement = false
            conversion.store.requestPageRetirement = { _, _, _ in retirement = true }
            _ = try conversion.store.convertSpaceToFolder(conversion.conversion)
            #expect(!retirement)
        }

        @Test func conversionRemovesOnlyTheOriginalSpaceAndBuildsTheFolderTree() throws {
            let fixture = try Fixture()
            let c = try Conversion(fixture: fixture)
            defer { try? FileManager.default.removeItem(at: c.directory) }
            _ = try c.store.convertSpaceToFolder(c.conversion)
            #expect(c.store.state.spaces.count == 1)
            #expect(c.store.state.spaces[0].id == c.destinationID)
            #expect(c.store.state.folders.contains { $0.id == c.conversion.folderID && $0.name == c.source.name && $0.parentID == nil })
            #expect(c.store.state.folders.contains { $0.id == c.conversion.todayFolderID && $0.name == "Today" && $0.parentID == c.conversion.folderID })
        }

        @Test func conversionKeepsOriginalTabsLivePinnedAndPlacedAndLeavesFavoritesOut() throws {
            let fixture = try Fixture()
            let c = try Conversion(fixture: fixture)
            defer { try? FileManager.default.removeItem(at: c.directory) }
            _ = try c.store.convertSpaceToFolder(c.conversion)
            let converted = c.store.state.tabs.filter { c.conversion.tabIDs.contains($0.id) }
            #expect(converted.allSatisfy { $0.spaceID == c.destinationID && $0.kind == .pinned && $0.archivedAt == nil })
            #expect(c.store.state.tabs.first { $0.id == c.today.id }?.folderID == c.conversion.todayFolderID)
            #expect(c.store.state.tabs.filter { $0.kind == .favorite }.map(\.id) == c.state.tabs.filter { $0.kind == .favorite }.map(\.id))
        }

        @Test func aConversionSurvivesSessionNormalization() throws {
            let fixture = try Fixture()
            let c = try Conversion(fixture: fixture)
            defer { try? FileManager.default.removeItem(at: c.directory) }
            _ = try c.store.convertSpaceToFolder(c.conversion)
            let loaded = try BrowserStore(directory: c.directory)
            #expect(loaded.state.folders == c.store.state.folders)
            #expect(loaded.state.tabs == c.store.state.tabs)
        }

        @Test func undoingAConversionRestoresPositionAndTreeWithoutRewindingNavigation() throws {
            let fixture = try Fixture()
            let c = try Conversion(fixture: fixture)
            defer { try? FileManager.default.removeItem(at: c.directory) }
            let undo = try #require(try c.store.convertSpaceToFolder(c.conversion))
            c.store.updateTab(c.today.id, title: "New live title")
            #expect(try c.store.undoSpaceFolderConversion(undo))
            #expect(c.store.state.folders == c.state.folders)
            #expect(c.store.state.spaces.map(\.id) == c.state.spaces.map(\.id))
            #expect(c.store.state.tabs.first { $0.id == c.today.id }?.title == "New live title")
            #expect(c.store.state.tabs.first { $0.id == c.today.id }?.kind == .today)
        }

        @Test func aNewDescendantInvalidatesDestructiveUndoOfARedoneConversion() throws {
            let fixture = try Fixture()
            let c = try Conversion(fixture: fixture)
            defer { try? FileManager.default.removeItem(at: c.directory) }
            let undo = try #require(try c.store.convertSpaceToFolder(c.conversion))
            _ = try c.store.undoSpaceFolderConversion(undo)
            let redo = try #require(undo.redo(in: c.store.state))
            let redone = try #require(try c.store.convertSpaceToFolder(redo))
            let root = try #require(c.store.state.folders.first { $0.id == c.conversion.folderID })
            _ = try c.store.createFolder(name: "Added later", in: c.store.state.spaces[0], parent: root)
            #expect(redone.restoring(in: c.store.state) == nil)
        }

        @Test func aChangedDestinationProfileRefusesConversion() throws {
            let fixture = try Fixture()
            let c = try Conversion(fixture: fixture)
            defer { try? FileManager.default.removeItem(at: c.directory) }
            var stale = c.state
            stale.spaces[1].profileID = UUID()
            #expect(c.conversion.applying(to: stale) == nil)
        }

        @Test func aCrossProfileProposalChangesOriginalRecordsTogetherAndCannotBeUndone() throws {
            let fixture = try Fixture()
            let initial = fixture.initial
            let cross = try #require(SpaceFolderConversion(source: initial.spaces[0].id, destination: initial.spaces[1].id,
                                                           state: initial, documents: fixture.references))
            #expect(cross.crossesProfiles)
            let applied = try #require(cross.applying(to: initial))
            #expect(applied.0.tabs.filter { cross.tabIDs.contains($0.id) }.allSatisfy { $0.profileID == initial.spaces[1].profileID })
            #expect(applied.1.restoring(in: applied.0) == nil)
        }
    }
}
