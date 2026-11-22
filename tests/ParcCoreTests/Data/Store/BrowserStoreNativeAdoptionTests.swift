import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeAdoptionTests {
    @Test @MainActor static func engineProfilePathsAreDirectChildrenOfTheVersionedRoot() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
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
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let profile = store.activeSpace.profileID
            let path = legacy
                ? directory.appendingPathComponent("Profiles").appendingPathComponent(profile.uuidString).path
                : store.independentEngineProfilePath(for: profile) + "/Private"
            #expect(store.profileID(forEnginePath: path) == nil)
        }
    }

    @Test @MainActor static func adoptingAnUnknownNativePageDoesNotMutateTheSession() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
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
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let originalSpace = store.activeSpaceID
            let originalProfile = store.activeSpace.profileID
            let selected = store.open("https://example.org/source")
            let path = store.independentEngineProfilePath(for: originalProfile)
            let destination = URL(string: "chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html?x=1#tab")!
            guard let adopted = store.adoptNativePage(url: destination, title: "Extension options", profilePath: path,
                                                      preferredSpaceID: originalSpace, select: false) else {
                throw BrowserStoreTestsSupport.Failure(description: "A known profile could not adopt its extension page")
            }
            let page = try BrowserStoreTestsSupport.tab(adopted, in: store)
            #expect(page.url == destination.absoluteString && page.savedURL == destination.absoluteString, "Native adoption must retain an actual engine URL without search resolution")
            #expect(page.title == "Extension options" && page.profileID == originalProfile && page.spaceID == originalSpace, "Native page metadata must belong to its actual profile and compatible Space")
            #expect(store.selectedTabID == selected, "Background adoption must not steal selection")
        }
    }

    @Test @MainActor static func aBlankPopupKeepsItsOpenerProfileEvenFromAnotherSpace() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
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
                throw BrowserStoreTestsSupport.Failure(description: "The original profile could not adopt its popup after Space selection changed")
            }
            #expect(try BrowserStoreTestsSupport.tab(popup, in: store).profileID == originalProfile && store.activeSpaceID == originalSpace, "An opener's profile must not be replaced by the currently selected different profile")
            #expect(try store.selectedTabID == popup && (try BrowserStoreTestsSupport.tab(popup, in: store)).url == "about:blank", "A not-yet-navigated popup must retain its existing blank page record")
        }
    }

    @Test @MainActor static func adoptedNativePageMetadataSurvivesRestart() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let originalSpace = store.activeSpaceID
            let originalProfile = store.activeSpace.profileID
            let path = store.independentEngineProfilePath(for: originalProfile)
            let destination = URL(string: "chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html?x=1#tab")!
            guard let adopted = store.adoptNativePage(url: destination, title: "Extension options", profilePath: path,
                                                      preferredSpaceID: originalSpace, select: false) else {
                throw BrowserStoreTestsSupport.Failure(description: "A known profile could not adopt its extension page")
            }
            let page = try BrowserStoreTestsSupport.tab(adopted, in: store)
            try store.save()
            let restored = try BrowserStore(directory: directory)
            #expect(try BrowserStoreTestsSupport.tab(adopted, in: restored) == page, "Adopted page metadata must survive session persistence")
        }
    }
}
