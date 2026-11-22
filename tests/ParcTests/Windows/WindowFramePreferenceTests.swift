import Foundation
import ParcTestSupport
import Testing
@testable import Parc

@MainActor private final class Store {
    let defaults: UserDefaults
    let key = "parc.windowFrame.v1"

    init() { defaults = TestDefaults("parc.windowFrame.tests.")! }

}

struct WindowFramePreferenceTests {
    @MainActor @Test func theThicknessDefaultsToTen() {
        let s = Store()
        let fresh = WindowFramePreferences(defaults: s.defaults)
        #expect(fresh.state.thickness == 10)
        #expect(!fresh.loadError)
        #expect(fresh.thickness == 10)
        #expect(!fresh.isAdjusting)
    }

    @MainActor @Test func aNewValueIsStored() throws {
        let s = Store()
        let fresh = WindowFramePreferences(defaults: s.defaults)
        try fresh.setThickness(6)
        #expect(fresh.state.thickness == 6)
    }

    @MainActor @Test func theValuePersistsAcrossLaunches() throws {
        let s = Store()
        try WindowFramePreferences(defaults: s.defaults).setThickness(6)
        #expect(WindowFramePreferences(defaults: s.defaults).state.thickness == 6)
    }

    @MainActor @Test func theValueClampsToTheRange() throws {
        let s = Store()
        let fresh = WindowFramePreferences(defaults: s.defaults)
        try fresh.setThickness(40)
        #expect(fresh.state.thickness == 13)
    }

    @MainActor @Test func aPreviewDoesNotSave() throws {
        let s = Store()
        let fresh = WindowFramePreferences(defaults: s.defaults)
        try fresh.setThickness(40)
        fresh.setPreview(8.4)
        #expect(fresh.isAdjusting)
        #expect(fresh.thickness == 8.4)
        #expect(fresh.state.thickness == 13)
    }

    @MainActor @Test func previewsStayNearTheRange() {
        let s = Store()
        let fresh = WindowFramePreferences(defaults: s.defaults)
        fresh.setPreview(20)
        #expect(fresh.thickness == WindowFramePreferences.previewBounds.upperBound)
    }

    @MainActor @Test func clearingThePreviewRestoresTheSavedValue() throws {
        let s = Store()
        let fresh = WindowFramePreferences(defaults: s.defaults)
        try fresh.setThickness(40)
        fresh.setPreview(8.4)
        fresh.setPreview(nil)
        #expect(!fresh.isAdjusting)
        #expect(fresh.thickness == 13)
    }

    @MainActor private static func future(_ s: Store) throws -> (WindowFramePreferences, Data) {
        let data = try JSONEncoder().encode(["version": 2, "thickness": 7])
        s.defaults.set(data, forKey: s.key)
        return (WindowFramePreferences(defaults: s.defaults), data)
    }

    @MainActor @Test func aFutureRecordFallsBackToTen() throws {
        let (future, _) = try Self.future(Store())
        #expect(future.loadError)
        #expect(future.state.thickness == 10)
    }

    @MainActor @Test func aFutureRecordRefusesWrites() throws {
        let (future, _) = try Self.future(Store())
        #expect(throws: (any Error).self) { try future.setThickness(5) }
    }

    @MainActor @Test func aFutureRecordIsPreserved() throws {
        let s = Store()
        let (future, data) = try Self.future(s)
        _ = try? future.setThickness(5)
        #expect(s.defaults.data(forKey: s.key) == data)
    }

    @MainActor @Test func anOutOfRangeRecordIsTreatedAsUnreadable() throws {
        let s = Store()
        s.defaults.set(try JSONEncoder().encode(WindowFramePreferences.State(version: 1, thickness: 30)), forKey: s.key)
        #expect(WindowFramePreferences(defaults: s.defaults).loadError)
    }

    @MainActor @Test func aMalformedRecordIsReportedAndPreserved() {
        let s = Store()
        s.defaults.set("garbage", forKey: s.key)
        let garbage = WindowFramePreferences(defaults: s.defaults)
        #expect(garbage.loadError)
        #expect(s.defaults.string(forKey: s.key) == "garbage")
    }
}
