import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeTests {
    @Test @MainActor static func engineProfilePathsAreDirectChildrenOfTheVersionedRoot() throws {
        try BrowserStoreTests.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let originalProfile = store.activeSpace.profileID
            let path = store.independentEngineProfilePath(for: originalProfile)
            #expect(path == directory.appendingPathComponent("Chromium-v1").appendingPathComponent(originalProfile.uuidString).path, "Each independent Profile must be an immediate child of its versioned engine root")
            #expect(URL(fileURLWithPath: path).deletingLastPathComponent() == store.independentEngineRoot, "CEF must receive a direct child profile, not a nested path that silently becomes private")
        }
    }

    @Test(arguments: [false, true])
    @MainActor static func profileLookupRefusesLegacyAndPrivatePaths(_ legacy: Bool) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let profile = store.activeSpace.profileID
            let path = legacy
                ? directory.appendingPathComponent("Profiles").appendingPathComponent(profile.uuidString).path
                : store.independentEngineProfilePath(for: profile) + "/Private"
            #expect(store.profileID(forEnginePath: path) == nil)
        }
    }

    @Test @MainActor static func adoptingAnUnknownNativePageDoesNotMutateTheSession() throws {
        try BrowserStoreTests.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let originalSpace = store.activeSpaceID
            _ = store.open("https://example.org/source")
            let path = store.independentEngineProfilePath(for: store.activeSpace.profileID)
            let unknownState = store.state
            #expect(store.adoptNativePage(url: nil, title: "", profilePath: path + "/Other",
                                            preferredSpaceID: originalSpace, select: true) == nil, "Unknown profile adoption must fail")
            #expect(store.state == unknownState, "Refused adoption must not mutate saved tabs or selection")
        }
    }

    @Test @MainActor static func adoptingABackgroundExtensionPagePreservesItsMetadataAndSelection() throws {
        try BrowserStoreTests.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let originalSpace = store.activeSpaceID
            let originalProfile = store.activeSpace.profileID
            let selected = store.open("https://example.org/source")
            let path = store.independentEngineProfilePath(for: originalProfile)
            let destination = URL(string: "chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html?x=1#tab")!
            guard let adopted = store.adoptNativePage(url: destination, title: "Extension options", profilePath: path,
                                                      preferredSpaceID: originalSpace, select: false) else {
                throw BrowserStoreTests.Failure(description: "A known profile could not adopt its extension page")
            }
            let page = try BrowserStoreTests.tab(adopted, in: store)
            #expect(page.url == destination.absoluteString && page.savedURL == destination.absoluteString, "Native adoption must retain an actual engine URL without search resolution")
            #expect(page.title == "Extension options" && page.profileID == originalProfile && page.spaceID == originalSpace, "Native page metadata must belong to its actual profile and compatible Space")
            #expect(store.selectedTabID == selected, "Background adoption must not steal selection")
        }
    }

    @Test @MainActor static func aBlankPopupKeepsItsOpenerProfileEvenFromAnotherSpace() throws {
        try BrowserStoreTests.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let originalSpace = store.activeSpaceID
            let originalProfile = store.activeSpace.profileID
            let path = store.independentEngineProfilePath(for: originalProfile)
            let secondSpace = store.createSpace(name: "Second")
            let secondProfile = store.createProfile(name: "Separate")
            store.assignProfile(secondProfile, toSpace: secondSpace)
            store.selectSpace(secondSpace)
            guard let popup = store.adoptNativePage(url: nil, title: "", profilePath: path,
                                                    preferredSpaceID: secondSpace, select: true) else {
                throw BrowserStoreTests.Failure(description: "The original profile could not adopt its popup after Space selection changed")
            }
            #expect(try BrowserStoreTests.tab(popup, in: store).profileID == originalProfile && store.activeSpaceID == originalSpace, "An opener's profile must not be replaced by the currently selected different profile")
            #expect(try store.selectedTabID == popup && (try BrowserStoreTests.tab(popup, in: store)).url == "about:blank", "A not-yet-navigated popup must retain its existing blank page record")
        }
    }

    @Test @MainActor static func adoptedNativePageMetadataSurvivesRestart() throws {
        try BrowserStoreTests.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let originalSpace = store.activeSpaceID
            let originalProfile = store.activeSpace.profileID
            let path = store.independentEngineProfilePath(for: originalProfile)
            let destination = URL(string: "chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html?x=1#tab")!
            guard let adopted = store.adoptNativePage(url: destination, title: "Extension options", profilePath: path,
                                                      preferredSpaceID: originalSpace, select: false) else {
                throw BrowserStoreTests.Failure(description: "A known profile could not adopt its extension page")
            }
            let page = try BrowserStoreTests.tab(adopted, in: store)
            try store.save()
            let restored = try BrowserStore(directory: directory)
            #expect(try BrowserStoreTests.tab(adopted, in: restored) == page, "Adopted page metadata must survive session persistence")
        }
    }

    @Test @MainActor static func cancellingNativeRetirementRestoresTheLiveRecord() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/form")
            let original = try BrowserStoreTests.tab(id, in: store)
            store.closeTab(id)
            let expected = try BrowserStoreTests.tab(id, in: store)
            #expect(store.restoreLiveTab(original, replacing: expected), "Cancelled native retirement must restore its exact saved record")
            #expect(try BrowserStoreTests.tab(id, in: store) == original && !store.state.recentlyClosedIDs.contains(id), "A cancelled close must not leave its live page in Archive or Recently Closed")
        }
    }

    @Test @MainActor static func aStaleRetirementCancellationCannotOverwriteNewerEdits() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/form")
            let original = try BrowserStoreTests.tab(id, in: store)
            store.closeTab(id)
            let earlier = try BrowserStoreTests.tab(id, in: store)
            store.updateTab(id, title: "Newer edit")
            let edited = store.state
            #expect(!store.restoreLiveTab(original, replacing: earlier), "A stale cancellation must not overwrite later edits")
            #expect(store.state == edited, "Rejected rollback must preserve all newer state")
        }
    }

    @Test @MainActor static func aPendingNativeCloseCannotPersistAnArchive() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            let original = try BrowserStoreTests.tab(id, in: store)
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            store.closeTab(id)
            #expect(try BrowserStoreTests.tab(id, in: store) == original, "Requesting native close must leave the saved tab unchanged")
            #expect(store.retiringTabIDs == [id] && decisions.count == 1 && decisions[0].0 == [id], "Retirement must identify exactly the page that needs approval")
            try store.save()
            let pending = try BrowserStore(directory: directory)
            #expect(try BrowserStoreTests.tab(id, in: pending).archivedAt == nil, "Saving during beforeunload must not persist an unapproved archive")
        }
    }

    @Test @MainActor static func refusingNativeCloseClearsTheReservationWithoutChangingTheTab() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            let original = try BrowserStoreTests.tab(id, in: store)
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            store.closeTab(id)
            decisions.removeFirst().1(false)
            #expect(try BrowserStoreTests.tab(id, in: store) == original && store.retiringTabIDs.isEmpty, "Cancelling close must retain the record and clear pending retirement")
        }
    }

    @Test @MainActor static func acceptingNativeCloseArchivesTheTab() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            store.closeTab(id)
            decisions.removeFirst().1(true)
            #expect(try BrowserStoreTests.tab(id, in: store).archivedAt != nil, "Accepted actual close may archive the saved Today tab")
        }
    }

    @Test @MainActor static func nativeRemovalWaitsForConsentAndPreservesThePageOnRefusal() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            store.removeTab(id)
            #expect(store.state.tabs.contains(where: { $0.id == id }), "Removing a record must also wait for native page approval")
            decisions.removeFirst().1(false)
            #expect(store.state.tabs.contains(where: { $0.id == id }), "Cancelling removal must preserve the saved page")
        }
    }

    @Test @MainActor static func aCrossProfileMoveWaitsForConsentAndStaysPutOnRefusal() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            let original = try BrowserStoreTests.tab(id, in: store)
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            let secondSpace = store.createSpace(name: "Other")
            let otherProfile = store.createProfile(name: "Other profile")
            store.assignProfile(otherProfile, toSpace: secondSpace)
            if !decisions.isEmpty { decisions.removeFirst().1(true) }
            store.moveTab(id, toSpace: secondSpace)
            #expect(try BrowserStoreTests.tab(id, in: store).profileID == original.profileID, "A profile-changing move must not retarget a live document before consent")
            decisions.removeFirst().1(false)
            #expect(try BrowserStoreTests.tab(id, in: store).spaceID == original.spaceID, "A cancelled profile-changing move must retain the source Space")
        }
    }

    @Test @MainActor static func reassigningASpaceProfileCommitsOnlyAfterNativeConsent() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/unsaved-form")
            let original = try BrowserStoreTests.tab(id, in: store)
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            store.requestPageRetirement = { ids, validate, callback in decisions.append((ids, { callback($0 && validate()) })) }
            let otherProfile = store.createProfile(name: "Other profile")
            store.assignProfile(otherProfile, toSpace: original.spaceID)
            #expect(store.state.spaces.first(where: { $0.id == original.spaceID })?.profileID == original.profileID, "Space profile reassignment must wait before changing its profile")
            decisions.removeFirst().1(true)
            #expect(try BrowserStoreTests.tab(id, in: store).profileID == otherProfile, "Accepted profile retirement may update saved page ownership")
        }
    }

    @Test @MainActor static func nativeCompletionWithoutValidationCannotArchiveThePage() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/approval-boundary")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            requests[0].1(true)
            #expect(try results == [false] && (try BrowserStoreTests.tab(id, in: store)).archivedAt == nil, "A native completion that skips pre-unload validation must not mutate saved pages")
            #expect(!requests[0].0(), "Completed retirement validators must never authorize later unload")
        }
    }

    @Test @MainActor static func preUnloadValidationIsSingleUseAndDoesNotArchiveThePage() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/approval-boundary")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            #expect(requests[0].0(), "Current retirement must validate immediately before actual unload")
            #expect(!requests[0].0(), "Pre-unload approval must be single-use")
            #expect((try BrowserStoreTests.tab(id, in: store)).archivedAt == nil && results.isEmpty, "Validation alone is not evidence that the native page was destroyed")
        }
    }

    @Test @MainActor static func anApprovedCloseCannotBeSupersededAndCommitsOnlyOnce() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/approval-boundary")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            try #require(requests[0].0())
            store.closeTabs([id]) { results.append($0) }
            #expect(requests.count == 1 && results == [false], "A second close must not supersede a transaction already unloading its actual page")
            requests[0].1(true)
            #expect(try results == [false, true] && (try BrowserStoreTests.tab(id, in: store)).archivedAt != nil, "The validated transaction commits after the real close completion")
            requests[0].1(false)
            requests[0].1(true)
            #expect(results == [false, true] && store.retiringTabIDs.isEmpty, "Repeated native replies must not repeat model publication or completion")
        }
    }

    @Test @MainActor static func staleNativeRetirementRepliesCannotRevokeTheReplacement() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/replaced-close")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.closeTabs([id]) { results.append($0) }
            store.removeTab(id)
            #expect(!requests[0].0(), "A superseded preflight must refuse before unloading the page")
            requests[0].1(false)
            #expect(store.retiringTabIDs == [id] && results == [false], "A stale refusal must preserve the newer retirement reservation")
            #expect(requests[1].0(), "The replacement operation must retain its own approval")
            requests[1].1(true)
            #expect(!store.state.tabs.contains { $0.id == id } && store.retiringTabIDs.isEmpty, "Only the current approved operation may remove the page record")
        }
    }

    @MainActor
    private static func withOverduePages(
        _ body: (BrowserStore, UUID, UUID) throws -> Void
    ) throws {
        try BrowserStoreTests.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let first = store.open("https://example.org/first-old-page")
            let second = store.open("https://example.org/second-old-page")
            _ = store.open("https://example.org/current-page")
            _ = store.archiveExpiredTabs()
            now.addTimeInterval(13 * 60 * 60)
            try body(store, first, second)
        }
    }

    @Test @MainActor static func addingProtectionInAnotherWindowCancelsTheWholeArchiveBeforeUnload() throws {
        try withOverduePages { store, first, second in
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            var results: [[UUID]] = []
            var currentProtection = Set<UUID>()
            var unloads = 0
            store.requestPageRetirement = { ids, validate, completion in requests.append((ids, validate, completion)) }
            store.archiveExpiredTabs(protectedTabIDs: [], currentProtection: { currentProtection }) { results.append($0) }
            #expect(requests[0].0.isSuperset(of: [first, second]), "The native archive preflight must cover both overdue pages")
            currentProtection.insert(first)
            let permitted = requests[0].1()
            if permitted { unloads += requests[0].0.count }
            requests[0].2(permitted)
            #expect(!permitted && unloads == 0 && results == [[]], "Protection added in another window must cancel the whole group before any native unload")
            #expect([first, second].allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }, "A cancelled archive group must preserve every saved live page")
        }
    }

    @Test @MainActor static func selectingOneOverduePageCancelsTheWholeArchiveBeforeUnload() throws {
        try withOverduePages { store, first, second in
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { ids, validate, completion in requests.append((ids, validate, completion)) }
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            store.selectTab(first)
            #expect(!requests[0].1(), "Selecting an overdue tab while consent is pending must refuse before unload")
            requests[0].2(false)
            let retained = try BrowserStoreTests.tab(second, in: store)
            #expect(results == [[]] && retained.archivedAt == nil, "Selecting one member cancels the complete automatic archive transaction")
        }
    }

    @Test @MainActor static func changingArchivePolicyWhileConsentIsPendingCancelsTheArchive() throws {
        try withOverduePages { store, _, _ in
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { ids, validate, completion in requests.append((ids, validate, completion)) }
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            _ = store.setAutoArchiveInterval(.thirtyDays, for: store.activeSpace.profileID)
            #expect(!requests[0].1(), "Changing archive policy during approval must preserve actual pages")
            requests[0].2(false)
            #expect(results == [[]] && store.retiringTabIDs.isEmpty, "Policy cancellation must finish once and clear reservations")
        }
    }

    @Test @MainActor static func reenteringFromNativeProtectionLetsTheReplacementRetirementWin() throws {
        try withOverduePages { store, first, second in
            var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { ids, validate, completion in requests.append((ids, validate, completion)) }
            var replaceDuringValidation = false
            store.archiveExpiredTabs(protectedTabIDs: [], currentProtection: {
                if replaceDuringValidation {
                    replaceDuringValidation = false
                    store.closeTab(first)
                }
                return []
            }) { results.append($0) }
            replaceDuringValidation = true
            #expect(!requests[0].1() && requests.count == 2, "Native protection callback reentry must invalidate an older transaction before unload")
            requests[0].2(false)
            #expect(store.retiringTabIDs == [first] && results.count == 1, "Reentrant replacement must keep its own page reservation when the archive is cancelled")
            #expect(requests[1].1(), "The reentrant close retains its own pre-unload validation")
            requests[1].2(true)
            let retired = try BrowserStoreTests.tab(first, in: store)
            let retained = try BrowserStoreTests.tab(second, in: store)
            #expect(retired.archivedAt != nil && retained.archivedAt == nil, "Only the replacement manual close may retire a page after cancelling the older group")
        }
    }

    @Test @MainActor static func newPagesInvalidateAProfileReassignmentBeforeUnload() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/original-profile")
            let originalProfile = store.activeSpace.profileID
            let spaceID = store.activeSpaceID
            let otherProfile = store.createProfile(name: "Second profile")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            store.assignProfile(otherProfile, toSpace: spaceID)
            let added = store.open("https://example.org/created-during-consent")
            #expect(!requests[0].0(), "A newly created page must invalidate the profile-wide preflight before any page unloads")
            requests[0].1(false)
            #expect(store.activeSpace.profileID == originalProfile && [id, added].allSatisfy { id in
                store.state.tabs.contains { $0.id == id && $0.profileID == originalProfile && $0.archivedAt == nil }
            }, "Cancelled reassignment must preserve all original page ownership")
        }
    }

    @Test @MainActor static func aRemovedDestinationInvalidatesTheMoveBeforeUnload() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.open("https://example.org/original-profile")
            let originalProfile = store.activeSpace.profileID
            let spaceID = store.activeSpaceID
            let otherProfile = store.createProfile(name: "Second profile")
            var requests: [(() -> Bool, (Bool) -> Void)] = []
            store.requestPageRetirement = { _, validate, completion in requests.append((validate, completion)) }
            let destination = store.createSpace(name: "Destination")
            store.assignProfile(otherProfile, toSpace: destination)
            let folder = store.createFolder(name: "Destination folder")
            store.moveTab(id, toSpace: destination, folderID: folder)
            let moveRequest = requests.last!
            let deletion = FolderRemovalTarget(folderID: folder, spaceID: destination, profileID: store.activeSpace.profileID, state: store.state)!
            store.deleteFolder(deletion, shouldCommit: { true }) { _ in }
            #expect(!moveRequest.0(), "A removed move destination must be rejected before native page unload")
            moveRequest.1(false)
            #expect(try (try BrowserStoreTests.tab(id, in: store)).spaceID == spaceID && (try BrowserStoreTests.tab(id, in: store)).profileID == originalProfile, "Invalid move destination must preserve the original page and profile")
        }
    }

    @Test @MainActor static func aWindowCommandUsesOnlyItsOwnSelectionAndPreservesTheOutgoingWindow() throws {
        try BrowserStoreTests.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let firstSpace = store.activeSpaceID
            let first = store.open("https://example.org/window-one")
            let cached = store.open("https://example.org/cached-other-window")
            let cachedBefore = try BrowserStoreTests.tab(cached, in: store)
            let secondSpace = store.createSpace(name: "Second window")
            let other = store.open("https://example.org/window-two")
            var snapshots: [BrowserState] = []
            let subscription = store.statePublisher.sink { snapshots.append($0) }
            defer { subscription.cancel() }
            now.addTimeInterval(60)
            #expect(store.setWindowPresentation(spaceID: firstSpace, selectedTabIDs: [first, first, other, UUID()]), "A known window Space must provide its command context")
            #expect(store.selectedTabID == first && store.state.selectedTabIDs == [first], "Window context must deduplicate and exclude pages outside its Space")
            #expect(try BrowserStoreTests.tab(cached, in: store) == cachedBefore, "Switching window context must not stamp another window's cached selection")
            #expect(try BrowserStoreTests.tab(first, in: store).lastAccessed == now, "Only the initiating window's supplied selection gets an activity stamp")
            #expect(snapshots.dropFirst().allSatisfy { $0.activeSpaceID == firstSpace && $0.selectedTabIDs == [first] }, "Window context publication must keep Space and page selection consistent")
            #expect(store.state.selectionBySpace[secondSpace.uuidString] == [other], "Switching command context must retain the outgoing saved selection")
        }
    }

    @Test @MainActor static func anEmptyWindowSelectionDoesNotRestoreItsCachedPage() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let firstSpace = store.activeSpaceID
            _ = store.open("https://example.org/window-one")
            _ = store.createSpace(name: "Second window")
            store.setWindowPresentation(spaceID: firstSpace, selectedTabIDs: [])
            #expect(store.state.selectedTabIDs.isEmpty, "An intentionally empty native window must not restore a cached fallback page")
        }
    }

    @Test @MainActor static func anUnknownWindowSpaceLeavesTheSessionUntouched() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://example.org/window-one")
            let before = store.state
            #expect(!store.setWindowPresentation(spaceID: UUID(), selectedTabIDs: [first]) && store.state == before, "An invalid window Space must leave the model unchanged")
        }
    }

    @Test @MainActor static func pendingGroupedCloseSavesAllPagesUntilConsent() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://example.org/first-form")
            let second = store.open("https://example.org/second-form")
            _ = store.open("https://example.org/keep")
            store.selectTab(first)
            let ids: Set<UUID> = [first, second]
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            var results: [Bool] = []
            store.requestPageRetirement = { requested, validate, callback in decisions.append((requested, { callback($0 && validate()) })) }
            store.closeTabs(ids) { results.append($0) }
            #expect(decisions.count == 1 && decisions[0].0 == ids && store.retiringTabIDs == ids, "Grouped close must reserve all records in one native retirement request")
            #expect(results.isEmpty && ids.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }, "No group member may archive before the aggregate decision")
            try store.save()
            let pending = try BrowserStore(directory: directory)
            #expect(ids.allSatisfy { id in pending.state.tabs.contains { $0.id == id && $0.archivedAt == nil } }, "Saving a pending group must retain every page")
        }
    }

    @Test @MainActor static func refusedGroupedClosePublishesNothing() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://example.org/first-form")
            let second = store.open("https://example.org/second-form")
            _ = store.open("https://example.org/keep")
            store.selectTab(first)
            let ids: Set<UUID> = [first, second]
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            var results: [Bool] = []
            var snapshots: [BrowserState] = []
            let subscription = store.statePublisher.sink { snapshots.append($0) }
            defer { subscription.cancel() }
            store.requestPageRetirement = { requested, validate, callback in decisions.append((requested, { callback($0 && validate()) })) }
            store.closeTabs(ids) { results.append($0) }
            decisions.removeFirst().1(false)
            #expect(results == [false] && store.retiringTabIDs.isEmpty && snapshots.count == 1, "A refused group must report once and publish no partial closure")
        }
    }

    @Test @MainActor static func approvedGroupedCloseArchivesAllPagesInOnePublication() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://example.org/first-form")
            let second = store.open("https://example.org/second-form")
            let survivor = store.open("https://example.org/keep")
            store.selectTab(first)
            let ids: Set<UUID> = [first, second]
            var decisions: [(Set<UUID>, (Bool) -> Void)] = []
            var results: [Bool] = []
            var snapshots: [BrowserState] = []
            let subscription = store.statePublisher.sink { snapshots.append($0) }
            defer { subscription.cancel() }
            store.requestPageRetirement = { requested, validate, callback in decisions.append((requested, { callback($0 && validate()) })) }
            store.closeTabs(ids) { results.append($0) }
            decisions.removeFirst().1(true)
            #expect(results == [true] && store.retiringTabIDs.isEmpty, "An approved group must finish only after the native aggregate result")
            #expect(ids.allSatisfy { id in store.state.tabs.contains { $0.id == id && $0.archivedAt != nil } }, "Approved group must archive every requested Today tab")
            #expect(snapshots.dropFirst().allSatisfy { snapshot in
                ids.allSatisfy { id in snapshot.tabs.contains { $0.id == id && $0.archivedAt != nil } }
            }, "Subscribers must never observe one group member closed and another still live")
            #expect(store.selectedTabID == survivor && store.state.recentlyClosedIDs.suffix(2) == [first, second], "Grouped fallback must exclude all retired pages and preserve close history order")
        }
    }

    @Test @MainActor static func anEmptyCloseGroupSucceedsWithoutNativeRetirement() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            var requests = 0
            var results: [Bool] = []
            store.requestPageRetirement = { _, _, _ in requests += 1 }
            store.closeTabs([]) { results.append($0) }
            #expect(results == [true] && requests == 0)
        }
    }

    @Test @MainActor static func automaticArchiveWaitsForNativeConsentAndHonorsRefusal() throws {
        try BrowserStoreTests.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.open("https://example.org/old-form")
            _ = store.open("https://example.org/selected")
            _ = store.archiveExpiredTabs()
            now.addTimeInterval(13 * 60 * 60)
            var decisions: [(Bool) -> Void] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { _, validate, completion in decisions.append { completion($0 && validate()) } }
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            #expect(try BrowserStoreTests.tab(id, in: store).archivedAt == nil && results.isEmpty, "Automatic archive must wait for the live page's result")
            decisions.removeFirst()(false)
            #expect(try results == [[]] && (try BrowserStoreTests.tab(id, in: store)).archivedAt == nil, "Cancelled automatic retirement must report no archive and retain the tab")
        }
    }

    @Test @MainActor static func selectingAnOverdueTabDuringConsentProtectsIt() throws {
        try BrowserStoreTests.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let id = store.open("https://example.org/old-form")
            _ = store.open("https://example.org/selected")
            _ = store.archiveExpiredTabs()
            now.addTimeInterval(13 * 60 * 60)
            var decisions: [(Bool) -> Void] = []
            var results: [[UUID]] = []
            store.requestPageRetirement = { _, validate, completion in decisions.append { completion($0 && validate()) } }
            store.archiveExpiredTabs(protectedTabIDs: []) { results.append($0) }
            store.selectTab(id)
            decisions.removeFirst()(true)
            #expect(try results.last == [] && (try BrowserStoreTests.tab(id, in: store)).archivedAt == nil, "A tab selected during consent must be revalidated and remain unarchived")
        }
    }

    @Test @MainActor static func aSplitDropWithStaleDestinationSelectionDoesNotChangeTheSession() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            let third = store.open("https://three.example")
            store.selectTab(first)
            let before = store.state
            #expect(!store.dropTabIntoSplit(second, expectedSelection: [third], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal), "Stale destination selection must reject atomically")
            #expect(store.state == before, "Refusal must not mutate any tab or group")
        }
    }

    @Test @MainActor static func aNewSplitDropKeepsOrderedIdentitiesTheAnchorAndOriginalPageMetadata() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            let originalTab = try BrowserStoreTests.tab(second, in: store)
            #expect(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]), "Sidebar identity must join the original selected page")
            let group = store.activeSplitLayout!
            #expect(group.tabIDs == [first, second] && group.sidebarAnchorID == second, "New split keeps ordered children and the original ordinary sidebar anchor")
            let afterTab = try BrowserStoreTests.tab(second, in: store)
            #expect(afterTab.url == originalTab.url && afterTab.savedURL == originalTab.savedURL
                && afterTab.kind == originalTab.kind && afterTab.folderID == originalTab.folderID, "Joining a split must preserve original child destination and placement")
        }
    }

    @Test @MainActor static func selectingAnOriginalChildActivatesItsWholeTypedSplit() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.selectTab(third)
            store.setSplit([third, fourth])
            store.selectTab(second)
            #expect(store.activeSplitLayout == group && store.state.selectedTabIDs == [first, second], "Selecting a child activates its whole typed container")
        }
    }

    @MainActor
    private static func withExpandedDropGroup(
        _ body: (BrowserStore, BrowserSplitLayout, BrowserSplitLayout, BrowserSplitLayout, UUID, UUID, UUID, UUID) throws -> Void
    ) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            let third = store.open("https://three.example")
            let fourth = store.open("https://four.example")
            store.selectTab(third)
            store.setSplit([third, fourth])
            let other = store.activeSplitLayout!
            store.selectTab(second)
            try #require(store.dropTabIntoSplit(third, expectedSelection: [first, second], expectedLayout: group,
                target: .insert(1), orientation: .horizontal), "Move an original child from a second group")
            let expanded = store.activeSplitLayout!
            try body(store, group, other, expanded, first, second, third, fourth)
        }
    }

    @Test @MainActor static func insertingAPaneFromAnotherGroupDissolvesOnlyTheSourceGroup() throws {
        try withExpandedDropGroup { store, group, other, expanded, first, second, third, fourth in
            #expect(expanded.id == group.id && expanded.tabIDs == [first, third, second], "Insertion retains destination container identity")
            #expect(!store.state.splitLayouts.contains(where: { $0.id == other.id }), "The one-child source container dissolves while its surviving tab stays alive")
            let survivor = try BrowserStoreTests.tab(fourth, in: store)
            #expect(survivor.archivedAt == nil, "Source survivor must remain alive")
        }
    }

    @Test @MainActor static func aPaneCannotBeDroppedIntoItsOwnSplit() throws {
        try withExpandedDropGroup { store, _, _, expanded, _, second, _, _ in
            let unchanged = store.state
            #expect(!store.dropTabIntoSplit(second, expectedSelection: expanded.tabIDs, expectedLayout: expanded,
                target: .insert(0), orientation: .horizontal), "A member is not a drop source; members reorder through pane Move")
            #expect(store.state == unchanged, "A refused member drop publishes nothing")
        }
    }

    @Test @MainActor static func replacingAPaneKeepsTheDestinationGroupAndTheDisplacedPage() throws {
        try withExpandedDropGroup { store, group, _, expanded, first, second, third, fourth in
            #expect(store.dropTabIntoSplit(fourth, expectedSelection: expanded.tabIDs, expectedLayout: expanded,
                target: .replace(1), orientation: .horizontal), "Typed replacement uses the original tab")
            let replaced = store.activeSplitLayout!
            #expect(replaced.tabIDs == [first, fourth, second] && replaced.id == group.id, "Replacement retains destination geometry and identity")
            let displaced = try BrowserStoreTests.tab(third, in: store)
            #expect(displaced.archivedAt == nil, "Displaced page is preserved, not closed")
        }
    }

    @Test @MainActor static func separatingAPanePreservesTheSiblingsAndInvalidatesTheOldGroupToken() throws {
        try withExpandedDropGroup { store, _, _, expanded, first, second, third, _ in
            #expect(store.separateTabFromSplit(first, expected: expanded))
            #expect(store.activeSplitLayout?.tabIDs == [third, second])
            #expect(!store.separateTabFromSplit(second, expected: expanded))
        }
    }

    @Test @MainActor static func typedSplitGroupsPersistAndAppearExactlyOnceInTheSidebar() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            let remaining = group
            try store.save()
            let restored = try BrowserStore(directory: directory)
            #expect(restored.activeSplitLayout == remaining, "Group identity, ordering, anchor and geometry persist")
            let projected = SidebarSplitItems.groups(in: restored.state, spaceID: restored.activeSpaceID)
            #expect(projected.map(\.id) == [remaining.id], "Sidebar projection emits each typed group exactly once")
            #expect(Set(projected.flatMap(\.tabIDs)).count == projected.flatMap(\.tabIDs).count, "A Space cannot assign one tab to two sidebar containers")
        }
    }

    @Test @MainActor static func anUnknownDropSourceCannotCreateAPlaceholder() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            let snapshot = store.state
            #expect(!store.dropTabIntoSplit(UUID(), expectedSelection: group.tabIDs, expectedLayout: group,
                target: .insert(0), orientation: .vertical), "Unknown source identity cannot create a placeholder")
            #expect(store.state == snapshot, "Unknown source refusal preserves exact state")
        }
    }

    enum DropDamage: CaseIterable { case outOfRange, existingMember, invalidGeometry }

    @Test(arguments: DropDamage.allCases) @MainActor static func invalidDropPlansDoNotCreateTransactions(_ damage: DropDamage) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            let group = try #require(store.activeSplitLayout)
            var layout = group
            var source = UUID()
            var index = 0
            switch damage {
            case .outOfRange: index = 99
            case .existingMember: source = second
            case .invalidGeometry: layout.widthFactors = []
            }
            #expect(SplitDropTransaction.make(source: source, selection: group.tabIDs, layout: layout,
                target: .insert(index), orientation: .horizontal, spaceID: store.activeSpaceID) == nil)
        }
    }

    @Test @MainActor static func legacyOverlappingSplitMembershipKeepsAndPersistsTheActiveGroup() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example")
            store.selectTab(first)
            try #require(store.dropTabIntoSplit(second, expectedSelection: [first], expectedLayout: nil,
                target: .insert(1), orientation: .horizontal, savedHomeIDs: [first: UUID()]))
            store.closeSplit()
            let fourth = store.open("https://four.example")
            store.setSplit([fourth, second])
            let remaining = try #require(store.activeSplitLayout)
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var layouts = legacy["splitLayouts"] as! [[String: Any]]
            layouts[0].removeValue(forKey: "id"); layouts[0].removeValue(forKey: "sidebarAnchorID")
            var overlap = layouts[0]
            overlap["tabIDs"] = [first.uuidString, second.uuidString]
            overlap["widthFactors"] = [0.5, 0.5]
            layouts.insert(overlap, at: 0); legacy["splitLayouts"] = layouts
            try JSONSerialization.data(withJSONObject: legacy).write(to: file)
            let migrated = try BrowserStore(directory: directory)
            #expect(migrated.state.splitLayouts.count == 1 && migrated.activeSplitLayout?.tabIDs == remaining.tabIDs, "Active typed group wins legacy overlapping layout cache membership")
            let migratedID = migrated.activeSplitLayout?.id
            let secondRead = try BrowserStore(directory: directory)
            #expect(secondRead.activeSplitLayout?.id == migratedID, "Legacy group identity migration is saved immediately and stable across rereads")
        }
    }

    @Test static func modifierSelectionFollowsTheStableSidebarAnchor() {
        let active = SidebarItemReference.tab(UUID()), neighbor = SidebarItemReference.tab(UUID())
        let folder = SidebarItemReference.folder(UUID()), split = SidebarItemReference.split(UUID())
        let order = [active, neighbor, folder, split]
        var selection = SidebarItemSelection()
        selection.select(folder, order: order, active: active, extending: false, toggling: true)
        #expect(selection.items == [active, folder], "Command selection retains active item without activating the target")
        selection.select(split, order: order, active: active, extending: true, toggling: false)
        #expect(selection.items == [active, folder, split], "Shift range uses the stable original-item anchor and retains active item")
        selection.select(neighbor, order: order, active: active, extending: true, toggling: false)
        #expect(selection.items == [active, neighbor, folder], "Reversing range shrinks around the same anchor")
        selection.select(active, order: order, active: active, extending: false, toggling: true)
        #expect(selection.items == [active, neighbor, folder], "Active item remains in a multi-selection")
    }

    @Test static func reconcilingSidebarSelectionDropsCollapsedRows() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection(items: [rows.active, rows.neighbor, rows.folder],
                                             anchor: rows.active, focus: rows.active)
        selection.reconcile(order: [rows.active, rows.split])
        #expect(selection.items.isEmpty && selection.focus == rows.active, "Removed or collapsed rows cannot retain a hidden multi-selection")
    }

    @Test static func aRangeStartsFromTheActiveRowAndExitsWhenOnlyItRemains() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.tab(UUID())
        let c = SidebarItemReference.folder(UUID()), d = SidebarItemReference.split(UUID())
        let order = [a, b, c, d]
        var selection = SidebarItemSelection()
        selection.select(b, order: order, active: a, extending: true, toggling: false)
        #expect(selection.items == [a, b], "First range starts at current active item")
        selection.select(b, order: order, active: a, extending: false, toggling: true)
        #expect(selection.items.isEmpty, "Returning to active singleton exits multi-selection")
    }

    @Test static func aStaleTargetCannotEnterSidebarSelection() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.tab(UUID())
        let c = SidebarItemReference.folder(UUID()), d = SidebarItemReference.split(UUID())
        let order = [a, b, c, d]
        var selection = SidebarItemSelection()
        selection.select(.tab(UUID()), order: order, active: a, extending: true, toggling: false)
        #expect(selection.items.isEmpty, "Stale target IDs cannot enter selection")
    }

    @Test static func anOffSidebarActivePageDoesNotEnterAMultiSelection() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.tab(UUID())
        let c = SidebarItemReference.folder(UUID()), d = SidebarItemReference.split(UUID())
        let order = [a, b, c, d]
        var selection = SidebarItemSelection()
        selection.select(b, order: order, active: .tab(UUID()), extending: false, toggling: true)
        #expect(selection.items.isEmpty && selection.singleItem == b, "An off-outline active page yields genuine singleton activation, never an invisible grant")
        selection.select(a, order: order, active: b, extending: false, toggling: true)
        #expect(selection.items == [a, b] && selection.singleItem == nil, "The next modifier press forms the original native multi-set")
    }

    @Test @MainActor static func movingSelectedSidebarItemsIsAtomic() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let first = store.open("https://one.example", kind: .pinned)
            let second = store.open("https://two.example", kind: .pinned)
            let third = store.open("https://three.example", kind: .pinned)
            let parent = store.createFolder(name: "Parent")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let target = store.createFolder(name: "Target")
            @MainActor func snapshot() -> SidebarHierarchySnapshot { SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)! }
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let destination = SidebarContainerLocation(spaceID: space, folderID: target, section: .pinned)
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            let original = store.state
            #expect(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: nil, expected: snapshot()), "Batch moves every original target in one transaction")
            #expect(publications == 1, "Bulk move publishes exactly once")
            #expect(SidebarHierarchy.children(in: destination, state: store.state) == [.tab(first), .tab(third)], "Original selection order is retained")
            #expect(store.state.selectedTabIDs == original.selectedTabIDs && store.state.history == original.history, "Bulk movement does not change page selection/history")
            #expect(try BrowserStoreTests.tab(first, in: store).url == (try BrowserStoreTests.tab(first, in: BrowserStore(directory: directory))).url, "Persisted originals retain their URLs")
            let stale = snapshot(); store.toggleFolder(parent)
            let unchanged = store.state
            #expect(!(try store.moveSidebarItems([.tab(first), .tab(second)], to: root, before: nil, expected: stale)), "Stale hierarchy rejects the whole batch")
            #expect(store.state == unchanged, "Stale batch leaves every item untouched")
            #expect(!(try store.moveSidebarItems([.tab(first), .folder(parent)], to: .init(spaceID: space, folderID: nested, section: .pinned), before: nil, expected: snapshot())), "A later cycle rejects the whole proposed batch")
            #expect(store.state == unchanged, "Earlier proposal steps never leak on later refusal")
            #expect(SidebarHierarchy.roots([.folder(parent), .folder(nested)], state: store.state, spaceID: space) == [.folder(parent)], "Selected ancestor owns a selected descendant once")
            #expect(!(try store.moveSidebarItems([.tab(second), .tab(second)], to: destination, before: nil, expected: snapshot())), "Duplicate original IDs reject")
            #expect(!(try store.moveSidebarItems([.tab(first), .tab(third)], to: destination, before: .tab(third), expected: snapshot())), "Selection-relative destination cannot consume one of its own source rows")
            store.selectTab(first); store.selectTab(third, extendingSplit: true)
            let split = store.activeSplitLayout!
            let beforeSplit = store.state
            #expect(try store.moveSidebarItems([.split(split.id), .folder(parent), .folder(nested)], to: root, before: .tab(second), expected: snapshot()), "Whole splits and normalized subtrees move together")
            #expect(store.state.splitLayouts == beforeSplit.splitLayouts && store.state.selectedTabIDs == beforeSplit.selectedTabIDs, "Split identity, geometry and original page focus survive")
            #expect(SidebarHierarchy.children(in: root, state: store.state).prefix(3) == [.split(split.id), .folder(parent), .tab(second)], "Mixed bulk insertion uses the exact typed target order")
            let stable = store.state, expected = snapshot(), file = directory.appendingPathComponent("session.json"), backup = directory.appendingPathComponent("backup.json")
            try FileManager.default.moveItem(at: file, to: backup); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.moveSidebarItems([.split(split.id), .tab(second)], to: destination, before: nil, expected: expected) } catch { failed = true }
            #expect(failed && store.state == stable, "Disk failure preserves every original item and selection")
            try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
            observation.cancel()
        }
    }

    @Test @MainActor static func folderDuplication() throws {
        try BrowserStoreTests.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Research")
            let nested = store.createFolder(name: "Articles", parentID: parent)
            _ = store.createFolder(name: "Empty", parentID: nested)
            let first = store.open("https://example.org/saved", kind: .pinned)
            let splitA = store.open("https://example.org/a")
            let splitB = store.open("https://example.org/b")
            store.moveTab(first, toSpace: space, folderID: parent)
            try BrowserStoreTests.savedSplit(store, [splitA, splitB], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(splitA)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
            let group = store.activeSplitLayout!
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            let snap = SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!
            _ = try store.moveSidebarItem(.folder(nested), to: inside, before: .tab(first), expected: snap)
            store.toggleFolder(nested)
            store.updateTab(first, title: "Live title", url: "https://example.org/current")
            let original = store.state
            let target = FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: profile, state: original)!
            let urls = Dictionary(uniqueKeysWithValues: target.tabs.map { ($0.id, $0.id == first ? "https://example.org/live-at-command" : $0.savedURL) })
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            let copy = try store.duplicateFolder(target, destinations: urls)!
            #expect(publications == 1, "Whole duplicate tree publishes once after its save")
            #expect(copy.folderID != parent && Set(copy.tabIDs).isDisjoint(with: Set(target.tabs.map(\.id))), "Copies receive fresh identities")
            #expect(original.tabs.allSatisfy { value in store.state.tabs.contains(value) }, "Original saved tabs remain byte-for-byte values")
            #expect(original.folders.allSatisfy { store.state.folders.contains($0) } && store.state.splitLayouts.contains(group), "Original folder and split identity/geometry remain intact")
            #expect(store.state.selectedTabIDs == original.selectedTabIDs && store.state.activeSpaceID == original.activeSpaceID, "Copy leaves active original page selection unchanged")
            #expect(store.state.history == original.history && store.state.downloads == original.downloads, "Duplication does not fabricate browsing/download history")
            let copiedParent = store.state.folders.first { $0.id == copy.folderID }!
            let copiedNested = store.state.folders.first { $0.parentID == copy.folderID }!
            let copiedEmpty = store.state.folders.first { $0.parentID == copiedNested.id }!
            #expect(copiedParent.name == "Research" && copiedNested.name == "Articles" && copiedEmpty.name == "Empty", "Nested and empty folder names survive without an invented suffix")
            #expect(copiedNested.isExpanded == original.folders.first { $0.id == nested }!.isExpanded, "Collapsed descendant contents and disclosure survive")
            let newTabs = copy.tabIDs.compactMap { id in store.state.tabs.first { $0.id == id } }
            let currentCopy = newTabs.first { $0.folderID == copy.folderID }!
            #expect(currentCopy.url == urls[first] && currentCopy.savedURL == urls[first], "Resolved original page destination becomes the copied saved destination")
            #expect(currentCopy.savedTitle == target.tabs.first { $0.id == first }!.savedTitle, "Saved title is distinct from current page title")
            #expect(newTabs.allSatisfy { $0.profileID == profile && $0.spaceID == space && $0.kind == .pinned && $0.createdAt == date && $0.archivedAt == nil }, "New saved records keep exact Profile/Space and fresh lifecycle metadata")
            let copiedGroup = store.state.splitLayouts.first { $0.id != group.id && Set($0.tabIDs).isSubset(of: Set(copy.tabIDs)) }!
            #expect(copiedGroup.orientation == group.orientation && copiedGroup.widthFactors == group.widthFactors, "Copied split preserves orientation and widths")
            #expect(copiedGroup.sidebarAnchorID == copiedGroup.tabIDs[group.tabIDs.firstIndex(of: group.sidebarAnchorID!)!], "Split anchor maps to the corresponding new child")
            #expect(copy.openTabIDs == copiedGroup.tabIDs && !copy.openTabIDs.contains(currentCopy.id), "Only copied split descendants request background page creation")
            let copiedInside = SidebarContainerLocation(spaceID: space, folderID: copy.folderID, section: .pinned)
            #expect(SidebarHierarchy.children(in: copiedInside, state: store.state) == [.folder(copiedNested.id), .tab(currentCopy.id)], "Mixed folder/tab sibling order survives recursion")
            let siblingRows = SidebarHierarchy.children(in: root, state: store.state)
            #expect(siblingRows.firstIndex(of: .folder(copy.folderID)) == siblingRows.firstIndex(of: .folder(parent))!.advanced(by: 1), "Parc inserts the new root adjacent to its original")
            let loaded = try BrowserStore(directory: directory).state
            #expect(loaded.tabs == store.state.tabs && loaded.folders == store.state.folders
                && loaded.sidebarItemOrder == store.state.sidebarItemOrder
                && Dictionary(uniqueKeysWithValues: loaded.splitLayouts.map { ($0.id, $0) }) == Dictionary(uniqueKeysWithValues: store.state.splitLayouts.map { ($0.id, $0) }), "Entire tree and order survive durable model reload; active-group cache ordering is independent")
            observation.cancel()
        }
    }

    @MainActor
    private static func withFolderToDuplicate(
        _ body: (BrowserStore, FolderDuplicateTarget, [UUID: String]) throws -> Void
    ) throws {
        try BrowserStoreTests.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Research")
            let nested = store.createFolder(name: "Articles", parentID: parent)
            let first = store.open("https://example.org/saved", kind: .pinned)
            let splitA = store.open("https://example.org/a")
            let splitB = store.open("https://example.org/b")
            store.moveTab(first, toSpace: space, folderID: parent)
            try BrowserStoreTests.savedSplit(store, [splitA, splitB], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(splitA)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            let snap = SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!
            _ = try store.moveSidebarItem(.folder(nested), to: inside, before: .tab(first), expected: snap)
            store.toggleFolder(nested)
            store.updateTab(first, title: "Live title", url: "https://example.org/current")
            let original = store.state
            let target = FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: profile, state: original)!
            let urls = Dictionary(uniqueKeysWithValues: target.tabs.map { ($0.id, $0.id == first ? "https://example.org/live-at-command" : $0.savedURL) })
            try body(store, target, urls)
        }
    }

    @Test @MainActor static func aFolderCopyCannotReuseAStaleCapability() throws {
        try withFolderToDuplicate { store, target, urls in
            let copy = try store.duplicateFolder(target, destinations: urls)
            _ = try #require(copy)
            let stable = store.state
            #expect(try store.duplicateFolder(target, destinations: urls) == nil, "An old folder capability cannot duplicate after hierarchy changes")
            #expect(store.state == stable, "Stale command has no partial effects")
        }
    }

    enum CopyDestinationDamage: CaseIterable { case missing, extra, typedDocument }

    @Test(arguments: CopyDestinationDamage.allCases)
    @MainActor static func aFolderCopyRefusesInvalidDestinations(_ damage: CopyDestinationDamage) throws {
        try withFolderToDuplicate { store, target, urls in
            var destinations = urls
            switch damage {
            case .missing: destinations.removeAll()
            case .extra: destinations[UUID()] = "https://foreign.example"
            case .typedDocument:
                let first = try #require(target.tabs.first { $0.savedURL == "https://example.org/saved" })
                destinations[first.id] = InternalPage.easel(UUID()).urlString
            }
            let stable = store.state
            #expect(try store.duplicateFolder(target, destinations: destinations) == nil)
            #expect(store.state == stable)
        }
    }

    @Test @MainActor static func aFolderCopyCannotDuplicateAPageAwaitingRetirement() throws {
        try withFolderToDuplicate { store, target, urls in
            let stable = store.state
            let first = try #require(target.tabs.first { $0.savedURL == "https://example.org/saved" }).id
            var retirementReply: ((Bool) -> Void)?
            store.requestPageRetirement = { _, _, completion in retirementReply = completion }
            store.closeTabs([first]) { _ in }
            #expect(try store.retiringTabIDs.contains(first) && (try store.duplicateFolder(target, destinations: urls)) == nil, "A source waiting for genuine retirement consent cannot be duplicated")
            retirementReply?(false)
            #expect(store.state == stable && store.retiringTabIDs.isEmpty, "Refused retirement preserves originals and releases the duplicate guard")
        }
    }

    @Test @MainActor static func aFolderCopyRequiresTheFoldersOwnProfile() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let parent = store.createFolder(name: "Research")
            let space = store.activeSpaceID
            #expect(FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: UUID(), state: store.state) == nil, "Foreign Profile cannot acquire folder command")
        }
    }

    enum CopyHierarchyDamage: CaseIterable { case cycle, splitCrossingContainers }

    @Test(arguments: CopyHierarchyDamage.allCases)
    @MainActor static func aMalformedHierarchyCannotProduceAFolderCopyTarget(_ damage: CopyHierarchyDamage) throws {
        try withFolderToDuplicate { store, target, _ in
            var corrupt = store.state
            let parent = target.folderID
            switch damage {
            case .cycle:
                let index = try #require(corrupt.folders.firstIndex { $0.id == parent })
                let descendant = try #require(corrupt.folders.first { $0.parentID == parent })
                corrupt.folders[index].parentID = descendant.id
            case .splitCrossingContainers:
                let first = try #require(target.tabs.first { $0.savedURL == "https://example.org/saved" })
                corrupt.splitLayouts[0].tabIDs.append(first.id)
            }
            #expect(FolderDuplicateTarget(folderID: parent, spaceID: store.activeSpaceID,
                profileID: store.activeSpace.profileID, state: corrupt) == nil)
        }
    }

    @Test @MainActor static func aFailedFolderCopySaveLeavesTheOriginalStateAndDoesNotPublish() throws {
        try withFolderToDuplicate { store, target, urls in
            let stable = store.state
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            let file = store.directory.appendingPathComponent("session.json"), backup = store.directory.appendingPathComponent("backup.json")
            try FileManager.default.moveItem(at: file, to: backup)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.duplicateFolder(target, destinations: urls) } catch { failed = true }
            #expect(failed && store.state == stable && publications == 0, "Disk refusal leaves all original/new IDs and publication untouched")
            try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
            observation.cancel()
        }
    }

    @Test @MainActor static func copyingAnEmptyFolderDoesNotCreateAPlaceholderPage() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let empty = store.createFolder(name: "Empty")
            let emptyTarget = FolderDuplicateTarget(folderID: empty, spaceID: space, profileID: profile, state: store.state)!
            let emptyCopy = try store.duplicateFolder(emptyTarget, destinations: [:])!
            #expect(emptyCopy.tabIDs.isEmpty && emptyCopy.openTabIDs.isEmpty, "Empty folder copy is real without creating a placeholder page")
        }
    }

    private struct SidebarRows {
        let active = SidebarItemReference.tab(UUID())
        let neighbor = SidebarItemReference.tab(UUID())
        let folder = SidebarItemReference.folder(UUID())
        let split = SidebarItemReference.split(UUID())
        var order: [SidebarItemReference] { [active, neighbor, folder, split] }
    }

    @Test static func accessibilityShowsTheActiveRowWhenNoOtherRowIsChosen() {
        let rows = SidebarRows()
        let selection = SidebarItemSelection()
        #expect(selection.shown(active: rows.active) == [rows.active], "With nothing chosen the current item is the shown selection")
    }

    @Test static func accessibilityAssignmentShowsASingleRequestedRowAlone() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        let hoisted1 = selection.assign([rows.neighbor], order: rows.order, active: rows.active)
        #expect(hoisted1, "One requested row is accepted")
        #expect(selection.items.isEmpty && selection.singleItem == rows.neighbor && selection.focus == rows.neighbor && selection.anchor == rows.neighbor, "One requested row becomes the single selection without forming a multi-set")
        #expect(selection.shown(active: rows.active) == [rows.neighbor], "A single selection is shown alone, without the current item")
    }

    @Test static func accessibilityMultiSelectionKeepsTheActiveItemInDisplayOrder() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor], order: rows.order, active: rows.active)
        let hoisted2 = selection.assign([rows.neighbor, rows.split], order: rows.order, active: rows.active)
        #expect(hoisted2, "Two requested rows are accepted")
        #expect(selection.items == [rows.active, rows.neighbor, rows.split] && selection.singleItem == nil && selection.focus == rows.split && selection.anchor == rows.split, "A requested multi-set keeps the current item, in display order, focused on the newcomer")
        #expect(selection.shown(active: rows.active) == [rows.active, rows.neighbor, rows.split], "A multi-set is shown exactly")
    }

    @Test static func accessibilityMultiSelectionCanGrowAndShrinkWithoutDroppingTheActiveRow() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor, rows.split], order: rows.order, active: rows.active)
        #expect(selection.assign([rows.active, rows.neighbor, rows.folder, rows.split], order: rows.order, active: rows.active) && selection.items == [rows.active, rows.neighbor, rows.folder, rows.split] && selection.focus == rows.folder, "Adding one row grows the multi-set and focuses the added row")
        #expect(selection.assign([rows.neighbor, rows.folder, rows.split], order: rows.order, active: rows.active) && selection.items == [rows.active, rows.neighbor, rows.folder, rows.split], "Leaving the current item out of a multi-set keeps it, as Command-click does")
        #expect(selection.assign([rows.neighbor, rows.folder], order: rows.order, active: rows.active) && selection.items == [rows.active, rows.neighbor, rows.folder], "Dropping another row shrinks the multi-set")
    }

    @Test static func accessibilityRejectsAnEntirelyUnknownSelectionWithoutChangingIt() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor, rows.split], order: rows.order, active: rows.active)
        let kept = selection
        #expect(!selection.assign([.tab(UUID())], order: rows.order, active: rows.active) && selection == kept, "Rows outside the displayed order are refused and change nothing")
    }

    @Test static func accessibilityDeselectingTheOnlyActiveRowKeepsKeyboardFocus() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        #expect(selection.assign([rows.active], order: rows.order, active: rows.active) && selection.items.isEmpty && selection.singleItem == rows.active
                   && selection.shown(active: rows.active) == [rows.active], "Choosing only the current item returns to it")
        #expect(selection.assign([], order: rows.order, active: rows.active) && selection.singleItem == rows.active && selection.focus == rows.active, "Deselecting the current item while it is all that's chosen keeps keyboard focus")
    }

    @Test static func anEmptyAccessibilitySelectionClearsAMultiSet() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        #expect(selection.assign([rows.neighbor, rows.folder], order: rows.order, active: rows.active) && selection.assign([], order: rows.order, active: rows.active)
                   && selection == SidebarItemSelection(), "An empty request clears a multi-set")
    }

    @Test static func accessibilitySelectionIgnoresUnknownRowsAndAnOffSidebarActivePage() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        #expect(selection.assign([rows.folder, .tab(UUID())], order: rows.order, active: rows.active) && selection.singleItem == rows.folder && selection.items.isEmpty, "Unknown rows in a request are ignored")
        #expect(selection.assign([rows.neighbor, rows.folder], order: rows.order, active: .tab(UUID())) && selection.items == [rows.neighbor, rows.folder], "A current page outside the sidebar never joins a multi-set")
    }

    @Test static func shiftClickRangesFromTheAccessibilityAnchorInEitherDirection() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.folder], order: rows.order, active: rows.active)
        selection.select(rows.split, order: rows.order, active: rows.active, extending: true, toggling: false)
        #expect(selection.items == [rows.active, rows.folder, rows.split], "Shift-click ranges from an accessibility single selection's anchor")
        selection.clear()
        selection.assign([rows.split], order: rows.order, active: rows.active)
        selection.select(rows.folder, order: rows.order, active: rows.active, extending: true, toggling: false)
        #expect(selection.items == [rows.active, rows.folder, rows.split], "Extending upward from an accessibility single selection keeps its anchor")
    }

    @Test static func commandClickAndAccessibilityCanUpdateTheSameMultiSet() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor], order: rows.order, active: rows.active)
        selection.select(rows.split, order: rows.order, active: rows.active, extending: false, toggling: true)
        #expect(selection.items == [rows.active, rows.split], "Command-click after a single selection builds the usual multi-set from the current item")
        #expect(selection.assign([rows.split], order: rows.order, active: rows.active) && selection.items.isEmpty && selection.singleItem == rows.split, "Taking the current item out of a two-row set leaves the other row as the single selection")
        selection.select(rows.split, order: rows.order, active: rows.active, extending: false, toggling: true)
        #expect(selection.items == [rows.active, rows.split], "Command-click on that row starts again from the current item")
        selection.assign([rows.active, rows.split, rows.neighbor], order: rows.order, active: rows.active)
        #expect(selection.items == [rows.active, rows.neighbor, rows.split] && selection.focus == rows.neighbor, "Accessibility adds to a Command-click multi-set")
        selection.select(rows.folder, order: rows.order, active: rows.active, extending: false, toggling: true)
        #expect(selection.items == [rows.active, rows.neighbor, rows.folder, rows.split], "Command-click adds to an accessibility multi-set")
        selection.select(rows.neighbor, order: rows.order, active: rows.active, extending: true, toggling: false)
        #expect(selection.items == [rows.active, rows.neighbor, rows.folder], "Shift-click ranges from the last Command-clicked anchor")
    }

    @Test static func keyboardNavigationReplacesTheAccessibilitySelection() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.split], order: rows.order, active: rows.active)
        selection.select(rows.folder, order: rows.order, active: rows.active, extending: true, toggling: false)
        #expect(selection.items == [rows.active, rows.folder, rows.split], "Extending upward from an accessibility single selection keeps its anchor")
        selection.select(rows.neighbor, order: rows.order, active: rows.active, extending: false, toggling: false)
        #expect(selection.items.isEmpty && selection.singleItem == rows.neighbor && selection.shown(active: rows.active) == [rows.neighbor], "A plain keyboard move replaces an accessibility selection")
    }

    @Test static func reconcilingAccessibilitySelectionDropsCollapsedRows() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor, rows.folder], order: rows.order, active: rows.active)
        selection.reconcile(order: [rows.active, rows.split])
        #expect(selection.items.isEmpty && selection.shown(active: rows.active) == [rows.active], "Rows collapsed away from an accessibility multi-set leave it like any other")
    }

    @Test static func reconcilingAnAccessibilityMultiSetTracksTheActiveRowOnlyWhenVisible() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.assign([rows.neighbor, rows.folder], order: rows.order, active: .tab(UUID()))
        selection.reconcile(order: rows.order, active: rows.active)
        #expect(selection.items == [rows.active, rows.neighbor, rows.folder], "A multi-set picks up the current item once its row appears")
        selection.reconcile(order: [rows.active, rows.neighbor, rows.split], active: rows.active)
        #expect(selection.items == [rows.active, rows.neighbor], "Trimming keeps the current item and the rows still shown")
        selection.assign([rows.neighbor, rows.folder], order: rows.order, active: .tab(UUID()))
        selection.reconcile(order: [rows.neighbor, rows.folder, rows.split], active: rows.active)
        #expect(selection.items == [rows.neighbor, rows.folder], "A current item without a row is never added")
    }

    @Test static func reconcilingAccessibilitySelectionNeverInventsAMultiSet() {
        let rows = SidebarRows()
        var selection = SidebarItemSelection()
        selection.reconcile(order: rows.order, active: rows.active)
        #expect(selection.items.isEmpty, "Reconciling never invents a multi-set")
    }

    @Test static func selectAllKeepsOnlyDisplayedRowsAndUsesTheirOrder() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.folder(UUID()), c = SidebarItemReference.split(UUID())
        var selection = SidebarItemSelection()
        selection.selectAll(order: [a, b, c, a], active: c)
        #expect(selection.items == [a, b, c], "Select All includes displayed original items once, in display order")
        #expect(selection.focus == c && selection.anchor == a, "Select All retains visible active focus and a stable first-row anchor")
        selection.selectAll(order: [b, c], active: a)
        #expect(selection.items == [b, c] && !selection.items.contains(a), "Select All cannot include hidden/foreign active rows")
    }

    @Test static func selectAllUsesSingletonSelectionAndClearsItForAnEmptySidebar() {
        let a = SidebarItemReference.tab(UUID()), c = SidebarItemReference.split(UUID())
        var selection = SidebarItemSelection()
        selection.selectAll(order: [a], active: c)
        #expect(selection.items.isEmpty && selection.singleItem == a, "Select All of an ordinary singleton uses the ordinary selection path")
        selection.selectAll(order: [], active: a)
        #expect(selection.items.isEmpty && selection.singleItem == nil && selection.focus == nil, "Empty Select All expires previous selection/focus")
    }

    @Test static func copyTargetsPreferValidSelectedRowsOverTheActiveRow() {
        let a = SidebarItemReference.tab(UUID()), b = SidebarItemReference.folder(UUID()), c = SidebarItemReference.split(UUID())
        var copying = SidebarItemSelection()
        #expect(copying.copyTargets(order: [a, b, c], active: c) == [c], "With nothing else chosen, Copy takes the current row")
        #expect(copying.copyTargets(order: [a, b], active: c) == nil, "A current row outside the sidebar, like a Favorite, has nothing to copy")
        copying.select(b, order: [a, b, c], active: nil, extending: false, toggling: false)
        #expect(copying.items.isEmpty && copying.copyTargets(order: [a, b, c], active: c) == [b], "One selected row copies that row")
        #expect(copying.copyTargets(order: [a, c], active: c) == nil, "A selected row that left the sidebar copies nothing")
        copying.select(c, order: [a, b, c], active: a, extending: false, toggling: true)
        #expect(copying.copyTargets(order: [a, b, c], active: a) == [a, c], "A multi-selection still copies every selected row")
    }

    @Test @MainActor static func copiedLinksExpandSelectedSidebarItems() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Folder")
            let a = store.open("https://example.com/a(b)", kind: .today)
            let b = store.open("https://example.com/a(b)", kind: .pinned)
            let c = store.open("https://example.com/c", kind: .today)
            store.updateTab(a, title: "A [label]\nnext")
            store.moveTab(a, toSpace: space, folderID: folder)
            store.moveTab(b, toSpace: space, folderID: folder)
            store.toggleFolder(folder)
            let original = store.state
            let links = FolderLinks.links(in: original, items: [.folder(folder), .tab(a), .tab(c)], spaceID: space, profileID: profile)!
            #expect(links.map(\.tabID) == [a, b, c], "Plural copy includes collapsed folder originals once and preserves distinct same-URL tabs")
            #expect(FolderLinks.text(for: links, format: .plain) == links.map(\.url).joined(separator: "\n"), "Plain plural copy exports one original URL per line")
            #expect(FolderLinks.text(for: links, format: .markdown)?.hasPrefix("[A \\[label\\] next](<https://example.com/a(b)>)") == true, "Plural Markdown uses the sidebar title and safe folder serialization")
            #expect(FolderLinks.links(in: original, items: [.folder(UUID()), .tab(c)], spaceID: space, profileID: profile) == nil, "A stale selected item refuses the whole copy proposal")
            #expect(FolderLinks.links(in: original, items: [.tab(c)], spaceID: space, profileID: UUID()) == nil, "Foreign profile cannot export the original Space")
            #expect(store.state == original, "Preparing copy never mutates original page/model selection")
            store.selectTab(a); store.selectTab(b, extendingSplit: true)
            let split = store.activeSplitLayout!
            let splitLinks = FolderLinks.links(in: store.state, items: [.split(split.id), .tab(c)], spaceID: space, profileID: profile)!
            #expect(splitLinks.map(\.tabID) == [a, b, c], "Plural copy expands the original split children in their existing order")
            #expect(FolderLinks.links(in: store.state, items: [.tab(c)], spaceID: space, profileID: profile)?.map(\.tabID) == [c], "One selected tab copies its own address")
            #expect(FolderLinks.links(in: store.state, items: [.split(split.id)], spaceID: space, profileID: profile)?.map(\.tabID) == [a, b], "One selected split copies all of its pages in pane order")
            var mixed = store.state
            let favorite = mixed.tabs.firstIndex { $0.id == b }!
            mixed.tabs[favorite].kind = .favorite; mixed.tabs[favorite].folderID = nil; mixed.tabs[favorite].spaceID = UUID()
            #expect(FolderLinks.links(in: mixed, items: [.split(split.id)], spaceID: space, profileID: profile)?.map(\.tabID) == [a, b]
                       && FolderLinks.links(in: mixed, tabIDs: split.tabIDs, spaceID: space, profileID: profile).map(\.tabID) == [a, b], "A split row's Favorite from another Space is copied alike from the sidebar and the split menu")
            #expect(FolderLinks.links(in: original, items: [.folder(folder)], spaceID: space, profileID: profile)?.map(\.tabID) == [a, b], "One selected folder copies its contents")
            let documents = [InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString, InternalPage.easel(UUID()).urlString, "parc://settings/", "about:blank"]
                .map { store.openResolvedURL(URL(string: $0)!) }
            #expect(FolderLinks.links(in: store.state, items: documents.map { .tab($0) } + [.tab(c)], spaceID: space, profileID: profile)?.map(\.tabID) == [documents[0], c], "Notes copy their file's address, while Easels, Parc pages and blank tabs have no address to copy")
            let rich = [FolderLinks.Link(tabID: UUID(), title: "A [label]\nnext", url: "https://example.com/a?x=1&y=2"),
                        FolderLinks.Link(tabID: UUID(), title: " ", url: "https://example.com/\"c\"")]
            #expect(FolderLinks.html(for: rich) == "<meta charset=\"utf-8\"><a href=\"https://example.com/a?x=1&amp;y=2\">A [label] next</a><br>\n"
                       + "<a href=\"https://example.com/&quot;c&quot;\">https://example.com/&quot;c&quot;</a>", "Rich copy links each page title to its address, escaped, falling back to the address")
            #expect(FolderLinks.text(for: rich, format: .markdown)?.hasSuffix("\n[https://example.com/\"c\"](<https://example.com/\"c\">)") == true, "Markdown falls back to the address for a blank title too")
            #expect(FolderLinks.html(for: []) == nil, "Nothing to copy has no rich flavor")
            let renamed = store.open("https://example.com/renamed", kind: .pinned)
            let named = store.createFolder(name: "Named")
            store.moveTab(renamed, toSpace: space, folderID: named)
            store.updateTab(renamed, title: "Page Title")
            try store.saveSidebarTitle(store.state.tab(renamed)!, title: "  My <Name> & Co  ")
            let renamedLinks = FolderLinks.links(in: store.state, items: [.tab(renamed)], spaceID: space, profileID: profile)!
            #expect(FolderLinks.text(for: renamedLinks, format: .markdown) == "[My \\<Name> & Co](<https://example.com/renamed>)", "Markdown copies a renamed tab under the name the sidebar shows")
            #expect(FolderLinks.html(for: renamedLinks) == "<meta charset=\"utf-8\"><a href=\"https://example.com/renamed\">My &lt;Name&gt; &amp; Co</a>", "Rich copy links a renamed tab's sidebar name to its address")
            #expect(FolderLinks.text(for: renamedLinks, format: .plain) == "https://example.com/renamed", "Plain copies of a renamed tab stay a bare address")
            #expect(FolderLinks.links(in: store.state, tabIDs: [renamed], spaceID: space, profileID: profile) == renamedLinks
                       && FolderLinks.links(in: store.state, target: FolderLinkTarget(folderID: named, spaceID: space, profileID: profile)) == renamedLinks, "The split menu and a folder's Copy All Links use the same sidebar name")
            try store.saveSidebarTitle(store.state.tab(renamed)!, title: "")
            let unnamed = FolderLinks.links(in: store.state, items: [.tab(renamed)], spaceID: space, profileID: profile)!
            #expect(FolderLinks.text(for: unnamed, format: .markdown) == "[example.com](<https://example.com/renamed>)", "Clearing the sidebar name falls back to the title saved when the tab was pinned")
        }
    }

    @Test @MainActor static func copiedLinksUseSavedPinnedTitle() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory), space = store.activeSpaceID, profile = store.activeSpace.profileID
            let id = store.open("https://example.com/pinned", kind: .today)
            store.updateTab(id, title: "Saved <Title>")
            store.setKind(id, .pinned)
            let folder = store.createFolder(name: "Saved")
            store.moveTab(id, toSpace: space, folderID: folder)
            store.updateTab(id, title: "Live Title")
            let tab = store.state.tab(id)!
            #expect(tab.kind == .pinned && tab.customTitle == nil && tab.title == "Live Title"
                       && SidebarTabTitle.display(tab) == "Saved <Title>", "A pinned tab's sidebar row keeps the title saved when it was pinned")
            let links = FolderLinks.links(in: store.state, items: [.tab(id)], spaceID: space, profileID: profile)!
            #expect(links.map(\.title) == [SidebarTabTitle.display(tab)], "Copied links take the title the sidebar row shows")
            #expect(FolderLinks.text(for: links, format: .markdown) == "[Saved \\<Title>](<https://example.com/pinned>)", "Markdown copies a pinned tab under its saved title, not the live one")
            #expect(FolderLinks.html(for: links) == "<meta charset=\"utf-8\"><a href=\"https://example.com/pinned\">Saved &lt;Title&gt;</a>", "Rich copy links a pinned tab's saved title to its address")
            #expect(FolderLinks.text(for: links, format: .plain) == "https://example.com/pinned", "Plain copies stay a bare address")
            #expect(FolderLinks.links(in: store.state, tabIDs: [id], spaceID: space, profileID: profile) == links
                       && FolderLinks.links(in: store.state, target: FolderLinkTarget(folderID: folder, spaceID: space, profileID: profile)) == links, "The split menu and a folder's Copy All Links use the same saved title")
        }
    }

    @Test(arguments: [
            ("Vec<T>", #"Vec\<T>"#),
            ("<b>bold</b> & <https://example.com>", #"\<b>bold\</b> & \<https://example.com>"#),
            ("snake_case_name.py", "snake_case_name.py"),
            ("_private and __dunder__", #"\_private and \_\_dunder\_\_"#),
            ("**Bold** and *it* or a*b*c", #"\*\*Bold\*\* and \*it\* or a\*b\*c"#),
            ("5 * 3 = 15 and x ~ y and a _ b", "5 * 3 = 15 and x ~ y and a _ b"),
            ("~/Downloads and ~~gone~~", #"\~/Downloads and \~\~gone\~\~"#),
            ("`code` here", #"\`code\` here"#),
            ("# Heading #1", "# Heading #1"),
            ("AT&T &amp; Tom & Jerry &#169; &#x1F600; &; &copy", #"AT&T \&amp; Tom & Jerry \&#169; \&#x1F600; &; &copy"#),
            (#"C:\Users\me and a\*b and trailing\"#, #"C:\Users\me and a\\\*b and trailing\\"#),
            ("[link](url) ![img]", #"\[link\](url) !\[img\]"#),
            ("Line\r\nbreak\nhere", "Line  break here"),
            ("naïve_test 日本_語 😀_x", #"naïve_test 日本_語 😀\_x"#),
            ("a\u{00A0}*\u{00A0}b", "a\u{00A0}*\u{00A0}b"),
            ("", ""),
    ])
    static func markdownLabelsEscapeOnlySpecialText(_ title: String, _ label: String) {
        #expect(FolderLinks.markdownLabel(title) == label)
    }

    @Test static func copiedMarkdownLabelsUseTheAddressForBlankTitles() {
        let links = [FolderLinks.Link(tabID: UUID(), title: "Vec<T> & `Option<_>`", url: "https://example.com/a_b"),
                     FolderLinks.Link(tabID: UUID(), title: "", url: "https://example.com/_next/a_b?x=1&y=2")]
        #expect(FolderLinks.text(for: links, format: .markdown) == #"[Vec\<T> & \`Option\<\_>\`](<https://example.com/a_b>)"# + "\n"
                   + #"[https://example.com/\_next/a_b?x=1&y=2](<https://example.com/_next/a_b?x=1&y=2>)"#, "Markdown copies escape every label, including the address standing in for a blank title, and keep destinations as they were")
    }

    @MainActor
    private static func withFolderAndItsNeighbors(
        _ body: (BrowserStore, FolderRemovalTarget, UUID, UUID, UUID) throws -> Void
    ) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let left = store.open("https://left.example", kind: .pinned)
            let folder = store.createFolder(name: "Delete")
            let current = store.open("https://current.example", kind: .pinned)
            store.moveTab(current, toSpace: space, folderID: folder)
            let right = store.open("https://right.example", kind: .pinned)
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            _ = try store.moveSidebarItem(.folder(folder), to: root, before: .tab(right),
                expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!)
            store.selectTab(current)
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            try body(store, target, left, current, right)
        }
    }

    @Test @MainActor static func folderDeletionFallsBackToTheNearestAvailableOriginalItem() throws {
        try withFolderAndItsNeighbors { store, target, left, current, right in
            @MainActor func resolve(_ selected: [UUID], _ focus: UUID?, unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
                FolderRemovalSelection.resolve(target: target, state: store.state, selected: selected,
                    focused: focus, available: { !unavailable.contains($0) })
            }
            let previous = resolve([current], current)!
            #expect(previous.tabIDs == [left] && previous.focusedTabID == left, "Folder close prefers the original previous item over the newer next item")
            let following = resolve([current], current, unavailable: [left])!
            #expect(following.tabIDs == [right], "Next original item is used when the previous page is owned elsewhere")
            let empty = resolve([current], current, unavailable: [left, right])!
            #expect(empty.tabIDs.isEmpty && empty.focusedTabID == nil, "No available original item yields a genuine empty selection")
        }
    }

    @Test @MainActor static func folderDeletionPreservesOnlyAvailableOriginalSelections() throws {
        try withFolderAndItsNeighbors { store, target, _, current, right in
            @MainActor func resolve(_ selected: [UUID], _ focus: UUID?, unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
                FolderRemovalSelection.resolve(target: target, state: store.state, selected: selected,
                    focused: focus, available: { !unavailable.contains($0) })
            }
            let background = resolve([right], right)!
            #expect(background.tabIDs == [right] && background.focusedTabID == right, "Deleting a background folder retains the original active page")
            #expect(resolve([], nil)?.tabIDs.isEmpty == true, "An unselected original window stays unselected")
            #expect(resolve([current, right], right)?.tabIDs == [right], "An original surviving pane is kept without selecting an unrelated neighbor")
            #expect(resolve([current, right], current)?.focusedTabID == right, "Retired focus falls to the original surviving pane")
            #expect(resolve([current, right], right, unavailable: [right]) == nil, "A surviving page transferred elsewhere refuses the captured decision")
            #expect(resolve([current], right) == nil && resolve([current, current], current) == nil, "Foreign focus and duplicate selection IDs refuse")
        }
    }

    @Test @MainActor static func collapsingAFolderDoesNotChangeItsDeletionFallback() throws {
        try withFolderAndItsNeighbors { store, target, left, current, _ in
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = try #require(target.folderIDs.first)
            var collapsed = store.state
            collapsed.folders[collapsed.folders.firstIndex { $0.id == folder }!].isExpanded = false
            let collapsedTarget = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: collapsed)!
            #expect(FolderRemovalSelection.resolve(target: collapsedTarget, state: collapsed,
                selected: [current], focused: current, available: { _ in true })?.tabIDs == [left], "Original close anchor survives collapsed folder disclosure")
        }
    }

    @Test @MainActor static func refusingFolderDeletionKeepsTheFolderAndTheOriginalSelection() throws {
        try withFolderAndItsNeighbors { store, target, left, current, _ in
            let folder = try #require(target.folderIDs.first)
            let previous = try #require(FolderRemovalSelection.resolve(target: target, state: store.state,
                selected: [current], focused: current, available: { _ in true }))
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validator, completion in gate = validator; done = completion }
            store.deleteFolder(target, selection: previous, shouldCommit: { false }) { _ in }
            #expect(gate?() == false, "Original-window refusal stops selection and deletion together")
            done?(false)
            #expect(store.state.selectedTabIDs == [current] && store.folders.contains { $0.id == folder }, "Refused consent preserves original current item and folder")
            #expect(previous.tabIDs == [left])
        }
    }

    @Test @MainActor static func confirmedFolderDeletionPersistsTheCapturedReplacementSelection() throws {
        try withFolderAndItsNeighbors { store, target, left, current, _ in
            let folder = try #require(target.folderIDs.first)
            let space = store.activeSpaceID
            @MainActor func resolve(_ selected: [UUID], _ focus: UUID?, unavailable: Set<UUID> = []) -> FolderRemovalSelection? {
                FolderRemovalSelection.resolve(target: target, state: store.state, selected: selected,
                    focused: focus, available: { !unavailable.contains($0) })
            }
            let previous = resolve([current], current)!
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validator, completion in gate = validator; done = completion }
            var result: Result<Bool, Error>?
            store.deleteFolder(target, selection: previous, shouldCommit: { true }) { result = $0 }
            #expect(store.state.selectedTabIDs == [current], "Pending consent does not select the replacement early")
            #expect(gate?() == true, "Confirmed immutable decision passes native retirement")
            done?(true)
            #expect((try? result?.get()) == true && store.state.selectedTabIDs == [left], "One commit removes the folder and selects its captured replacement")
            #expect(store.state.selectionBySpace[space.uuidString] == [left], "Same-Space restart selection commits with folder deletion")
            let loaded = try BrowserStore(directory: store.directory)
            #expect(loaded.state.selectedTabIDs == [left] && !loaded.folders.contains { $0.id == folder }, "Disk reload sees deletion and replacement together")
        }
    }

    @Test @MainActor static func folderDeletionTreatsTheAdjacentSplitAsOneFallbackItem() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let a = store.open("https://a.example")
            let b = store.open("https://b.example")
            try BrowserStoreTests.savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nil, section: .pinned))
            store.selectTab(a); _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.4, 0.6])
            let split = store.activeSplitLayout!
            let folder = store.createFolder(name: "Delete")
            let current = store.open("https://current.example", kind: .pinned)
            store.moveTab(current, toSpace: space, folderID: folder)
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            let choice = FolderRemovalSelection.resolve(target: target, state: store.state,
                selected: [current], focused: current, available: { _ in true })!
            #expect(choice.tabIDs == split.tabIDs, "An adjacent split is selected as its original complete item")
            #expect(FolderRemovalSelection.resolve(target: target, state: store.state,
                selected: [current], focused: current, available: { $0 != b })?.tabIDs.isEmpty == true, "One unavailable split child excludes the entire group")
            var changed = store.state
            changed.tabs[changed.tabs.firstIndex { $0.id == a }!].profileID = UUID()
            #expect(FolderRemovalSelection.resolve(target: target, state: changed,
                selected: [current], focused: current, available: { _ in true }) == nil, "A replacement changing profile invalidates the original hierarchy")
        }
    }

    @Test @MainActor static func anUnknownReplacementCannotCommitFolderDeletion() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Delete")
            let current = store.open("https://current.example", kind: .pinned)
            store.moveTab(current, toSpace: space, folderID: folder)
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            let selection = FolderRemovalSelection(spaceID: space, profileID: profile, original: [current],
                originalFocus: current, tabIDs: [UUID()], focusedTabID: nil)
            var result: Result<Bool, Error>?
            store.deleteFolder(target, selection: selection, shouldCommit: { true }) { result = $0 }
            #expect((try? result?.get()) == false && store.folders.contains { $0.id == folder }, "Unknown replacement cannot commit deletion")
        }
    }

    @Test @MainActor static func folderDeletion() throws {
        try BrowserStoreTests.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let sibling = store.createFolder(name: "Keep")
            let parent = store.createFolder(name: "Delete")
            let nested = store.createFolder(name: "Nested", parentID: parent)
            let empty = store.createFolder(name: "Empty", parentID: nested)
            let outside = store.open("https://keep.example", kind: .pinned)
            let first = store.open("https://one.example", kind: .pinned)
            let a = store.open("https://a.example")
            let b = store.open("https://b.example")
            store.moveTab(first, toSpace: space, folderID: parent)
            try BrowserStoreTests.savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(a)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
            let split = store.activeSplitLayout!
            store.toggleFolder(nested)
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            _ = try store.moveSidebarItem(.folder(nested), to: inside, before: .tab(first),
                expected: SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!)
            let before = store.state
            let rootBefore = SidebarHierarchy.children(in: root, state: before)
            let target = FolderRemovalTarget(folderID: parent, spaceID: space, profileID: profile, state: before)!
            #expect(target.folderIDs == [parent, nested, empty] && Set(target.tabs.map(\.id)) == [first, a, b], "Deletion binds collapsed and empty descendants in original mixed order")
            #expect(FolderRemovalTarget(folderID: parent, spaceID: space, profileID: UUID(), state: before) == nil, "Foreign profile cannot prepare deletion")
            var malformed = before
            malformed.folders[malformed.folders.firstIndex { $0.id == parent }!].parentID = empty
            #expect(FolderRemovalTarget(folderID: parent, spaceID: space, profileID: profile, state: malformed) == nil, "Hierarchy cycles refuse before consent")
            var crossSplit = before
            crossSplit.splitLayouts[0].tabIDs[1] = outside
            #expect(FolderRemovalTarget(folderID: parent, spaceID: space, profileID: profile, state: crossSplit) == nil, "A cross-subtree split cannot borrow an outside page")
            var requested = Set<UUID>(), validate: (() -> Bool)?, finish: ((Bool) -> Void)?
            store.requestPageRetirement = { ids, gate, done in requested = ids; validate = gate; finish = done }
            var results: [Result<Bool, Error>] = []
            store.deleteFolder(target, shouldCommit: { false }) { results.append($0) }
            #expect(requested == [first, a, b] && store.state == before, "Every original descendant page joins retirement before metadata changes")
            #expect(validate?() == false, "Originating-window refusal cancels the whole operation")
            finish?(false)
            #expect((try results.last?.get()) == false && store.state == before, "Refusal preserves folder tree, tabs, selection and order")
            store.deleteFolder(target, shouldCommit: { true }) { results.append($0) }
            finish?(false)
            #expect(try store.state == before && (try results.last?.get()) == false, "Native beforeunload refusal does not archive any sibling")
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            store.deleteFolder(target, shouldCommit: { true }) { results.append($0) }
            #expect(validate?() == true && validate?() == false, "Consent authorization is one-shot")
            #expect(store.state == before, "Approved pages must actually finish retiring before saved deletion")
            let done = finish!
            done(true)
            #expect((try results.last?.get()) == true && publications == 1, "Complete deletion publishes once after durable save")
            let after = store.state, resultCount = results.count
            done(true)
            #expect(store.state == after && results.count == resultCount, "Repeated native completion cannot duplicate archives or commits")
            #expect(!store.state.folders.contains { [parent, nested, empty].contains($0.id) } && store.state.folders.contains { $0.id == sibling }, "Only the original subtree folder records are deleted")
            #expect(target.tabs.allSatisfy { original in store.state.tabs.contains { $0.id == original.id && $0.archivedAt == date && $0.folderID == nil && $0.profileID == profile && $0.kind == original.kind && $0.savedURL == original.savedURL } }, "Original saved identities and destinations become archived tabs without fabricated folder archives")
            #expect(store.state.tabs.first { $0.id == outside } == before.tabs.first { $0.id == outside }, "Outside saved tab is byte-for-byte untouched")
            #expect(SidebarHierarchy.children(in: root, state: store.state) == rootBefore.filter { $0 != .folder(parent) }, "Mixed sibling order survives removal without reparenting children")
            #expect(store.state.splitLayouts.isEmpty && store.state.selectedTabIDs.isEmpty, "Retired original split cannot remain visibly selected")
            let archived = store.archivedItems(profileID: profile)
            #expect(archived.count == 2 && archived.contains { $0.tabs.map(\.id) == split.tabIDs && $0.provenance?.split == split }, "Complete split children stay one restorable archive item with original geometry")
            #expect(archived.allSatisfy { $0.provenance?.reason == .manual && $0.provenance?.spaceID == space }, "Archive uses the genuine original Space and manual source")
            #expect(store.state.history == before.history && store.state.downloads == before.downloads, "Folder deletion leaves history/download records intact")
            let loaded = try BrowserStore(directory: directory)
            #expect(loaded.state.tabs == store.state.tabs && loaded.state.folders == store.state.folders && loaded.state.sidebarItemOrder == store.state.sidebarItemOrder, "Durable reload contains the complete archive and hierarchy result")
            _ = store.restoreArchivedTab(a, profileID: profile, destination: .previousSpace(fallbackSpaceID: space))
            #expect(store.state.selectedTabIDs == split.tabIDs && store.activeSplitLayout?.orientation == .vertical && store.activeSplitLayout?.widthFactors == [0.3, 0.7], "Restoring the archived split preserves original page IDs/order and geometry")
            #expect(store.state.folders.first { $0.id == parent }?.parentID == nil
                && store.state.folders.first { $0.id == nested }?.parentID == parent
                && !store.state.folders.contains { $0.id == empty }, "Restoring the split rebuilds only the deleted folders on its path")
            #expect(split.tabIDs.allSatisfy { id in store.state.tabs.first { $0.id == id }?.folderID == nested }
                && SidebarHierarchy.children(in: .init(spaceID: space, folderID: nested, section: .pinned), state: store.state) == [.split(split.id)], "The restored split sits inside its rebuilt folder")
            #expect(SidebarHierarchy.children(in: root, state: store.state) == rootBefore, "The rebuilt folder returns to its original Pinned position")
            _ = observation
        }
    }

    @Test @MainActor static func changingAFolderDuringNativeConsentPreventsDeletion() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Pending")
            let tabID = store.open("https://pending.example", kind: .pinned)
            store.moveTab(tabID, toSpace: space, folderID: folder)
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validate, completion in gate = validate; done = completion }
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            var result: Result<Bool, Error>?
            store.deleteFolder(target, shouldCommit: { true }) { result = $0 }
            store.renameFolder(folder, name: "Changed")
            #expect(gate?() == false, "Renamed or structurally changed target invalidates original confirmation")
            done?(false)
            #expect((try result?.get()) == false && store.state.tabs.first { $0.id == tabID }?.archivedAt == nil, "Stale cancellation retains original page and saved tab")
        }
    }

    @Test @MainActor static func aReentrantWindowValidatorCannotDeleteAnEditedFolder() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Pending")
            let tabID = store.open("https://pending.example", kind: .pinned)
            store.moveTab(tabID, toSpace: space, folderID: folder)
            var gate: (() -> Bool)?, done: ((Bool) -> Void)?
            store.requestPageRetirement = { _, validate, completion in gate = validate; done = completion }
            let target = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            store.deleteFolder(target, shouldCommit: { store.renameFolder(folder, name: "Reentered"); return true }) { _ in }
            #expect(gate?() == false, "Reentrant validator cannot authorize a changed subtree")
            done?(false)
        }
    }

    @Test @MainActor static func deletingAnEmptyFolderStillRequiresWindowConsent() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            var result: Result<Bool, Error>?
            let empty = store.createFolder(name: "Empty")
            let emptyTarget = FolderRemovalTarget(folderID: empty, spaceID: space, profileID: profile, state: store.state)!
            store.deleteFolder(emptyTarget, shouldCommit: { false }) { result = $0 }
            #expect(store.state.folders.contains { $0.id == empty }, "Empty-folder removal still honors original-window cancellation")
            store.deleteFolder(emptyTarget, shouldCommit: { true }) { result = $0 }
            #expect((try result?.get()) == true && !store.state.folders.contains { $0.id == empty }, "Confirmed empty folder uses the same durable transaction")
        }
    }

    @Test @MainActor static func aFailedSaveCannotPublishAPartialFolderDeletion() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let folder = store.createFolder(name: "Pending")
            let tabID = store.open("https://pending.example", kind: .pinned)
            store.moveTab(tabID, toSpace: space, folderID: folder)
            var result: Result<Bool, Error>?
            let failureTarget = FolderRemovalTarget(folderID: folder, spaceID: space, profileID: profile, state: store.state)!
            let original = store.state
            try store.save()
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json"))
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("session.json"), withIntermediateDirectories: false)
            store.deleteFolder(failureTarget, shouldCommit: { true }) { result = $0 }
            if case .failure = result {} else { throw BrowserStoreTests.Failure(description: "Save failure must report an error") }
            #expect(store.state == original && store.persistenceError != nil, "Failed durable save cannot publish a partial deletion")
        }
    }

    @Test @MainActor static func folderDeletionUndo() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let outer = store.createFolder(name: "Outer")
            let beforeSibling = store.createFolder(name: "Before", parentID: outer)
            let root = store.createFolder(name: "Deleted", parentID: outer)
            let afterSibling = store.createFolder(name: "After", parentID: outer)
            let nested = store.createFolder(name: "Nested", parentID: root)
            let empty = store.createFolder(name: "Empty", parentID: nested)
            let a = store.open("https://a.test"), b = store.open("https://b.test")
            try BrowserStoreTests.savedSplit(store, [a, b], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(a)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.25, 0.75])
            let split = store.activeSplitLayout!, originals = store.state
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: originals)!
            let selection = FolderRemovalSelection.resolve(target: target, state: originals,
                selected: [a, b], focused: b, available: { _ in true })!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, selection: selection, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!
            #expect(undo.focusedTabID == b && undo.groups == [split], "Undo binds original focused pane and split provenance")
            #expect(undo.folders.map(\.id).contains(empty) && store.canUndoFolderDeletion(undo), "Nested empty folder is part of ordinary undo, without folder archive entities")
            let newSibling = store.createFolder(name: "New", parentID: outer)
            store.renameFolder(beforeSibling, name: "Keep current edit")
            let outside = store.open("https://outside.test", kind: .today)
            let outsideRecord = store.state.tabs.first { $0.id == outside }!
            let beforeUndo = store.state
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            #expect(try store.undoFolderDeletion(undo, shouldCommit: { true }), "Undo restores exact original group")
            #expect(publications == 1, "Undo publishes one durable targeted transaction")
            #expect(store.state.tabs.first { $0.id == a } == originals.tabs.first { $0.id == a }
                && store.state.tabs.first { $0.id == b } == originals.tabs.first { $0.id == b }, "Original tab identities/content return from unchanged archive afterimages")
            #expect(store.state.splitLayouts.contains(split), "Original split ID, pane order and geometry return")
            #expect(store.state.folders.filter { target.folderIDs.contains($0.id) } == originals.folders.filter { target.folderIDs.contains($0.id) }, "Nested names, parents and expansion return intact")
            #expect(store.state.tabs.first { $0.id == outside } == outsideRecord
                && store.state.folders.first { $0.id == beforeSibling }?.name == "Keep current edit", "Unrelated additions and edits survive Undo")
            let container = SidebarContainerLocation(spaceID: space, folderID: outer, section: .pinned)
            #expect(SidebarHierarchy.children(in: container, state: store.state) == [.folder(beforeSibling), .folder(root), .folder(afterSibling), .folder(newSibling)], "Original sibling anchors restore location without rolling back new siblings")
            #expect(store.state.selectedTabIDs == beforeUndo.selectedTabIDs, "Store Undo does not select pages in other physical windows")
            #expect(try !store.canUndoFolderDeletion(undo) && !(try store.undoFolderDeletion(undo, shouldCommit: { true })), "Consumed afterimage cannot duplicate original identities")
            let loaded = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            #expect(loaded.state.tabs == store.state.tabs && loaded.state.folders == store.state.folders
                && loaded.state.splitLayouts == store.state.splitLayouts, "Restored originals persist together")
            _ = observation
        }
    }

    @Test @MainActor static func aCancelledFolderDeletionDoesNotRegisterUndo() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Cancelled")
            let target = try #require(FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state))
            var record: FolderDeletionUndo?, result: Result<Bool, Error>?
            store.deleteFolder(target, shouldCommit: { false }, didCommit: { record = $0 }) { result = $0 }
            #expect(try record == nil && (try result?.get()) == false, "Cancelled delete cannot register Undo")
        }
    }

    @Test @MainActor static func refusingFolderUndoLeavesItRetryableWithoutChangingTheSession() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Retry")
            let a = store.open("https://retry.test", kind: .pinned)
            store.moveTab(a, toSpace: space, folderID: root)
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state)!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!, archived = store.state
            #expect(try !store.undoFolderDeletion(undo, shouldCommit: { false }), "Original-window refusal leaves Undo retryable")
            #expect(store.state == archived, "Refused Undo changes no saved state")
        }
    }

    @Test @MainActor static func folderRedoTargetsCurrentOriginalPagesButRefusesNewDescendants() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Retry")
            let a = store.open("https://retry.test", kind: .pinned)
            store.moveTab(a, toSpace: space, folderID: root)
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state)!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = try #require(record)
            #expect(try store.undoFolderDeletion(undo, shouldCommit: { true }), "Undo restores exact original group")
            store.updateTab(a, title: "New actual title")
            #expect(undo.redoTarget(in: store.state) != nil, "Redo closes current original members after normal title/navigation updates")
            let extra = store.open("https://extra.test", kind: .pinned)
            store.moveTab(extra, toSpace: space, folderID: root)
            #expect(undo.redoTarget(in: store.state) == nil, "Redo never closes newly added descendants")
        }
    }

    @Test @MainActor static func aFailedFolderUndoLeavesTheArchiveAndRetryCapability() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Retry")
            let a = store.open("https://retry.test", kind: .pinned)
            store.moveTab(a, toSpace: space, folderID: root)
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state)!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = record!, archived = store.state
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json"))
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("session.json"), withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.undoFolderDeletion(undo, shouldCommit: { true }) } catch { failed = true }
            #expect(failed && store.state == archived && store.canUndoFolderDeletion(undo), "Failed durable Undo keeps exact archived state and retry capability")
            try FileManager.default.removeItem(at: directory.appendingPathComponent("session.json")); try store.save()
        }
    }

    @Test @MainActor static func restoringAnArchivedTabIndependentlyInvalidatesItsFolderUndo() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let root = store.createFolder(name: "Retry")
            let a = store.open("https://retry.test", kind: .pinned)
            store.moveTab(a, toSpace: space, folderID: root)
            let target = FolderRemovalTarget(folderID: root, spaceID: space, profileID: profile, state: store.state)!
            var record: FolderDeletionUndo?
            store.deleteFolder(target, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            let undo = try #require(record)
            _ = store.restoreArchivedTab(a, profileID: profile, destination: .previousSpace(fallbackSpaceID: space))
            #expect(!store.canUndoFolderDeletion(undo), "Independent archive restoration invalidates old group")
            #expect(try !store.undoFolderDeletion(undo, shouldCommit: { true }), "Stale Undo cannot resurrect a folder around an independently restored tab")
        }
    }

    @Test @MainActor static func undoRestoresAnEmptyFoldersOriginalIdentity() throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            var record: FolderDeletionUndo?
            let empty = store.createFolder(name: "Empty")
            let emptyTarget = FolderRemovalTarget(folderID: empty, spaceID: space, profileID: profile, state: store.state)!
            store.deleteFolder(emptyTarget, shouldCommit: { true }, didCommit: { record = $0 }) { _ in }
            #expect(try store.undoFolderDeletion(record!, shouldCommit: { true }), "Empty ordinary folder Undo is supported")
            #expect(store.state.folders.contains { $0.id == empty }, "Empty folder retains original identity")
        }
    }

    @Test(arguments: ["all", "filtered", "missing", "reassigned", "original-moved", "foreign-profile", "no-compatible-space", "recent"])
    @MainActor static func archivePutBackResolvesTheRequestedDestination(scenario: String) throws {
        try BrowserStoreTests.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let originalSpace = store.activeSpaceID, profile = store.activeSpace.profileID
            let a = store.open("https://archive-a.example"), b = store.open("https://archive-b.example")
            store.setSplit([a, b]); _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.35, 0.65])
            let originalSplit = store.activeSplitLayout!
            store.closeTabs([a, b])
            let currentSpace = store.createSpace(name: "Current window")
            let filteredSpace = store.createSpace(name: "Selected filter")
            let otherProfile = store.createProfile(name: "Other profile")
            store.selectSpace(currentSpace)
            if scenario == "reassigned" { store.assignProfile(otherProfile, toSpace: filteredSpace) }
            if scenario == "original-moved" { store.assignProfile(otherProfile, toSpace: originalSpace) }
            let destination: ArchiveRestoreDestination
            let expected: UUID?
            let requestedProfile: UUID
            switch scenario {
            case "filtered":
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: filteredSpace)
                expected = filteredSpace; requestedProfile = profile
            case "missing":
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: UUID())
                expected = currentSpace; requestedProfile = profile
            case "reassigned":
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: filteredSpace)
                expected = currentSpace; requestedProfile = profile
            case "foreign-profile":
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: nil)
                expected = nil; requestedProfile = otherProfile
            case "no-compatible-space":
                destination = .putBack(currentSpaceID: UUID(), requestedSpaceID: UUID())
                expected = nil; requestedProfile = profile
            case "recent":
                destination = .previousSpace(fallbackSpaceID: currentSpace)
                expected = originalSpace; requestedProfile = profile
            default:
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: nil)
                expected = currentSpace; requestedProfile = profile
            }
            let before = store.state
            var publications: [BrowserState] = []
            let observation = store.statePublisher.dropFirst().sink { publications.append($0) }
            let restored = store.restoreArchivedTab(a, profileID: requestedProfile, destination: destination)
            if let expected {
                #expect(restored == originalSplit.tabIDs && store.activeSpaceID == expected, "Put Back \(scenario) selects the original group in its resolved destination")
                #expect(!publications.isEmpty && publications.allSatisfy { snapshot in
                    snapshot.tabs.filter { [a, b].contains($0.id) }.allSatisfy { $0.archivedAt == nil && $0.spaceID == expected }
                }, "Put Back publishes the complete original group without partially restored siblings")
                let tabs = store.state.tabs.filter { [a, b].contains($0.id) }
                #expect(tabs.count == 2 && tabs.allSatisfy { $0.spaceID == expected && $0.profileID == profile && $0.archivedAt == nil && $0.archiveProvenance == nil }, "Put Back retains original identities/profile and clears only archive metadata")
                var expectedSplit = originalSplit; expectedSplit.spaceID = expected
                let restoredLayout = store.activeSplitLayout
                var restoredShape = restoredLayout; restoredShape?.widthFactors = expectedSplit.widthFactors
                #expect(restoredShape == expectedSplit && zip(restoredLayout?.widthFactors ?? [], expectedSplit.widthFactors).allSatisfy { abs($0 - $1) < 1e-12 }, "Put Back preserves original split order, orientation, ratios and identity")
                #expect(!store.state.recentlyClosedIDs.contains(a) && !store.state.recentlyClosedIDs.contains(b), "Restored group leaves the recent-closed stack")
                try store.save()
                let loaded = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
                #expect(loaded.state.tabs == store.state.tabs && loaded.state.splitLayouts == store.state.splitLayouts, "Put Back destination persists with the original group")
            } else {
                #expect(restored.isEmpty && store.state == before && publications.isEmpty, "Invalid Put Back \(scenario) preserves every archived record and selection")
            }
            _ = observation
        }
    }
}
