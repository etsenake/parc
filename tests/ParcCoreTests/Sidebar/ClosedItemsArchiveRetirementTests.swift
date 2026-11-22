import Combine
import Foundation
import Testing
@testable import ParcCore

extension ClosedItemsTestsSupport {
    @MainActor
    struct ClosedItemsArchiveRetirementTests {
        struct ArchiveRetirement {
            let f: Fixture
            let a: UUID, b: UUID
            let record: ClosedItemRecord
            let item: BrowserArchivedItem
            let lease: ArchivePreviewLease
            let now = Date(timeIntervalSince1970: 1_900_000_000)

            @MainActor init() throws {
                let now = self.now
                f = try Fixture(now: { now })
                a = f.store.open("https://a.invalid")
                b = f.store.open("https://b.invalid")
                f.store.setSplit([a, b])
                let intent = f.intent([a, b], focus: a)
                f.store.closeTabs([a, b])
                let closed = ClosedWindow()
                closed.record(intent, in: f.store.state)
                record = closed.next(in: f.store.state)!
                let aID = a
                let found = f.store.archivedItems(profileID: f.profile).first { $0.tabs.contains { $0.id == aID } }!
                item = found
                lease = f.store.acquireArchivePreview(id: found.id, profileID: f.profile)!
            }
        }

        @MainActor private final class RetirementRequests {
            var all: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
        }

        private func requests(for r: ArchiveRetirement) -> RetirementRequests {
            let recorded = RetirementRequests()
            r.f.store.requestPageRetirement = { recorded.all.append(($0, $1, $2)) }
            return recorded
        }

        private func refusedFirstRetirement(_ r: ArchiveRetirement) -> RetirementRequests {
            let recorded = requests(for: r)
            let store = r.f.store
            store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            _ = store.restoreArchivePreview(r.lease, destination: .previousSpace(fallbackSpaceID: r.f.space))
            store.deleteArchivedTabs([r.b], profileID: r.f.profile)
            store.removeTab(r.a)
            recorded.all[0].2(false)
            return recorded
        }

        private func releasedAndConsented(_ r: ArchiveRetirement) -> RetirementRequests {
            let recorded = refusedFirstRetirement(r)
            let store = r.f.store
            store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            _ = recorded.all[1].1()
            recorded.all[1].2(true)
            store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            _ = recorded.all[2].1()
            store.releaseArchivePreview(r.lease)
            recorded.all[2].2(true)
            return recorded
        }

        private func afterStaleConsent(_ r: ArchiveRetirement) -> RetirementRequests {
            let recorded = releasedAndConsented(r)
            recorded.all[0].2(true)
            return recorded
        }

        @Test func aLeasedGroupRefusesASecondPreview() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store
            #expect(store.acquireArchivePreview(id: r.item.id, profileID: r.f.profile) == nil)
        }

        @Test func aLeasedGroupRefusesAnOrdinaryArchiveRestore() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store
            #expect(store.restoreArchivedTab(r.a, profileID: r.f.profile, destination: .previousSpace(fallbackSpaceID: r.f.space)).isEmpty)
        }

        @Test func aLeasedGroupRefusesReopen() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store
            #expect(try !store.restoreClosedItem(r.record))
        }

        @Test func renamingAnArchivedTabKeepsItsPreviewLease() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store
            store.updateTab(r.a, title: "New title")
            #expect(store.archivePreviewIsValid(r.lease))
        }

        @Test func deletingAnArchivedTabAsksToRetireTheWholeGroupsPages() throws {
            let r = try ArchiveRetirement()
            let recorded = requests(for: r)
            r.f.store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            #expect(recorded.all.count == 1)
            #expect(recorded.all[0].0 == [r.a, r.b])
        }

        @Test func aPendingRetirementKeepsTheLeaseValid() throws {
            let r = try ArchiveRetirement()
            _ = requests(for: r)
            r.f.store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            #expect(r.f.store.archivePreviewIsValid(r.lease))
        }

        @Test func aPendingRetirementBlocksRestoringThePreview() throws {
            let r = try ArchiveRetirement()
            _ = requests(for: r)
            r.f.store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            #expect(r.f.store.restoreArchivePreview(r.lease, destination: .previousSpace(fallbackSpaceID: r.f.space)).isEmpty)
        }

        @Test func moreDeletesAndRemovalsWhileRetirementIsPendingAskForNothingMore() throws {
            let r = try ArchiveRetirement()
            let recorded = requests(for: r)
            r.f.store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            r.f.store.deleteArchivedTabs([r.b], profileID: r.f.profile)
            r.f.store.removeTab(r.a)
            #expect(recorded.all.count == 1)
        }

        @Test func aRefusedRetirementKeepsTheTab() throws {
            let r = try ArchiveRetirement()
            _ = refusedFirstRetirement(r)
            #expect(r.f.store.state.tabs.contains { $0.id == r.a })
        }

        @Test func aRefusedRetirementKeepsTheLease() throws {
            let r = try ArchiveRetirement()
            _ = refusedFirstRetirement(r)
            #expect(r.f.store.archivePreviewIsValid(r.lease))
        }

        @Test func aHeldLeaseKeepsTheTabThroughConsent() throws {
            let r = try ArchiveRetirement()
            let recorded = refusedFirstRetirement(r)
            r.f.store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            #expect(recorded.all[1].1())
            recorded.all[1].2(true)
            #expect(r.f.store.state.tabs.contains { $0.id == r.a })
            #expect(r.f.store.archivePreviewIsValid(r.lease))
        }

        @Test func releasingTheLeaseLetsConsentDeleteTheTab() throws {
            let r = try ArchiveRetirement()
            let recorded = refusedFirstRetirement(r)
            r.f.store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            recorded.all[1].2(true)
            r.f.store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            #expect(recorded.all[2].1())
            r.f.store.releaseArchivePreview(r.lease)
            recorded.all[2].2(true)
            #expect(!r.f.store.state.tabs.contains { $0.id == r.a })
            #expect(r.f.store.state.tabs.contains { $0.id == r.b })
        }

        @Test func deletingAReleasedGroupsTabCannotReacquireItsPreviewMidDelete() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store
            let recorded = refusedFirstRetirement(r)
            store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            recorded.all[1].2(true)
            store.deleteArchivedTabs([r.a], profileID: r.f.profile)
            store.releaseArchivePreview(r.lease)
            var reentry: ArchivePreviewLease?
            let observer = store.statePublisher.dropFirst().sink { _ in reentry = store.acquireArchivePreview(id: r.item.id, profileID: r.f.profile) }
            recorded.all[2].2(true)
            observer.cancel()
            #expect(reentry == nil)
        }

        @Test func aStaleConsentForTheFirstRequestChangesNothing() throws {
            let r = try ArchiveRetirement()
            let recorded = releasedAndConsented(r)
            recorded.all[0].2(true)
            #expect(r.f.store.state.tabs.contains { $0.id == r.b })
        }

        @Test func editingATabDuringConsentRefusesTheStaleDelete() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store
            let recorded = afterStaleConsent(r)
            let remaining = try #require(store.archivedItems(profileID: r.f.profile).first { $0.tabs.contains { $0.id == r.b } })
            _ = try #require(store.acquireArchivePreview(id: remaining.id, profileID: r.f.profile))
            store.deleteArchivedTabs([r.b])
            store.updateTab(r.b, title: "Edited during consent")
            #expect(!recorded.all[3].1())
        }

        @Test func aRefusedStaleDeleteKeepsTheTabAndItsLease() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store
            let recorded = afterStaleConsent(r)
            let remaining = try #require(store.archivedItems(profileID: r.f.profile).first { $0.tabs.contains { $0.id == r.b } })
            let second = try #require(store.acquireArchivePreview(id: remaining.id, profileID: r.f.profile))
            store.deleteArchivedTabs([r.b])
            store.updateTab(r.b, title: "Edited during consent")
            recorded.all[3].2(false)
            #expect(store.state.tabs.contains { $0.id == r.b })
            #expect(store.archivePreviewIsValid(second))
        }

        @Test func restoringAPreviewRestoresItsTabAndRetiresTheLease() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store
            let recorded = afterStaleConsent(r)
            let remaining = try #require(store.archivedItems(profileID: r.f.profile).first { $0.tabs.contains { $0.id == r.b } })
            let second = try #require(store.acquireArchivePreview(id: remaining.id, profileID: r.f.profile))
            store.deleteArchivedTabs([r.b])
            store.updateTab(r.b, title: "Edited during consent")
            recorded.all[3].2(false)
            #expect(store.restoreArchivePreview(second, destination: .previousSpace(fallbackSpaceID: r.f.space)) == [r.b])
            #expect(!store.archivePreviewIsValid(second))
        }

        @Test func restoringAPreviewCannotReacquireItMidRestore() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store
            let recorded = afterStaleConsent(r)
            let remaining = try #require(store.archivedItems(profileID: r.f.profile).first { $0.tabs.contains { $0.id == r.b } })
            let second = try #require(store.acquireArchivePreview(id: remaining.id, profileID: r.f.profile))
            store.deleteArchivedTabs([r.b])
            store.updateTab(r.b, title: "Edited during consent")
            recorded.all[3].2(false)
            var reentry: ArchivePreviewLease?
            let remainingID = remaining.id
            let observer = store.statePublisher.dropFirst().sink { _ in reentry = store.acquireArchivePreview(id: remainingID, profileID: r.f.profile) }
            _ = store.restoreArchivePreview(second, destination: .previousSpace(fallbackSpaceID: r.f.space))
            observer.cancel()
            #expect(reentry == nil)
        }

        @Test func clearingTheArchiveWithoutANativeOwnerRemovesItsTabsImmediately() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store, profile = r.f.profile
            store.releaseArchivePreview(r.lease)
            store.closeTabs([r.b])
            store.clearArchive(profileID: profile)
            #expect(!store.state.tabs.contains { $0.id == r.b })
        }

        @Test func refusingNativeRetirementKeepsAnExpiredRecord() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store, now = r.now
            store.releaseArchivePreview(r.lease)
            store.closeTabs([r.b])
            store.clearArchive(profileID: r.f.profile)
            store.clearArchive(profileID: r.f.profile)

            let expiring = store.open("https://expired.invalid")
            store.closeTabs([expiring])
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            store.requestPageRetirement = { requests.append(($0, $1, $2)) }
            store.cleanExpiredArchive(now: now.addingTimeInterval(BrowserStore.archiveRetention))
            #expect(requests.count == 1)
            #expect(requests[0].0 == [expiring])
            requests[0].2(false)
            #expect(store.state.tabs.contains { $0.id == expiring })
        }

        @Test func expiryWithoutANativeOwnerRemovesTheRecordImmediatelyAfterRefusal() throws {
            let r = try ArchiveRetirement()
            let store = r.f.store, now = r.now
            store.releaseArchivePreview(r.lease)
            store.closeTabs([r.b])
            store.clearArchive(profileID: r.f.profile)
            let expiring = store.open("https://expired.invalid")
            store.closeTabs([expiring])
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            store.requestPageRetirement = { requests.append(($0, $1, $2)) }
            store.cleanExpiredArchive(now: now.addingTimeInterval(BrowserStore.archiveRetention))
            requests[0].2(false)
            store.requestPageRetirement = nil
            store.cleanExpiredArchive(now: now.addingTimeInterval(BrowserStore.archiveRetention))
            #expect(!store.state.tabs.contains { $0.id == expiring })
        }

        @Test func openingAnEaselKeepsItsLeasedArchiveIdentitySeparate() throws {
            let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let store = f.store
            let document = UUID()
            let easel = store.openResolvedURL(URL(string: InternalPage.easel(document).urlString)!)
            store.closeTabs([easel])
            let documentLease = try #require(store.acquireArchivePreview(id: easel, profileID: f.profile))
            let other = try #require(store.openEasel(id: document, title: "Board"))
            #expect(other != easel)
            #expect(store.archivePreviewIsValid(documentLease))
            store.releaseArchivePreview(documentLease)
        }

        @Test func anUnreleasedArchivePreviewRefusesEaselDeletion() throws {
            let f = try Fixture(now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let store = f.store
            let document = UUID()
            let easel = store.openResolvedURL(URL(string: InternalPage.easel(document).urlString)!)
            store.closeTabs([easel])
            let documentLease = try #require(store.acquireArchivePreview(id: easel, profileID: f.profile))
            let other = try #require(store.openEasel(id: document, title: "Board"))
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            store.requestPageRetirement = { requests.append(($0, $1, $2)) }
            var deleted = false, completed: Error?
            store.deleteLocalDocument(.easel(document), profileID: f.profile, ownerValid: { true }, deleteDocument: { deleted = true }, completion: { completed = $0 })
            #expect(requests.count == 1)
            #expect(requests[0].0 == [easel, other])
            #expect(requests[0].1())
            requests[0].2(true)
            #expect(!deleted)
            #expect(completed != nil)
            #expect(store.state.tabs.contains { $0.id == easel })
            store.releaseArchivePreview(documentLease)
        }
    }
}
