import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitPaneMenuInsertionSessionTests {
    @MainActor private struct Fixture {
        let directory: URL
        let store: BrowserStore
        let session: SplitPaneInsertionSession
        let owner = Owner()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let before: BrowserState

        final class Owner { var valid = true }

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-pane-menu-" + UUID().uuidString)
            store = try BrowserStore(directory: directory)
            let id = store.open("https://original.invalid")
            let request = try #require(SplitPaneInsertion(paneID: id, operation: .addAfter, state: store.state))
            let owner = owner
            before = store.state
            session = SplitPaneInsertionSession(request: request, candidateIDs: [id]) { owner.valid }
            session.placeholder.frame = host.bounds
            host.addSubview(session.placeholder)
            session.placeholder.layoutSubtreeIfNeeded()
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func aValidDraftOwnsOnePresentation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.session.isValid)
        #expect(fixture.session.placeholder.superview === fixture.host)
    }

    @Test func theTemporaryPaneHasAnAccessibilityLabel() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.session.placeholder.accessibilityLabel() == "New split pane")
    }

    @Test func thePlaceholderDrawsNoInventedLabelOrControl() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.session.placeholder.subviews.isEmpty)
    }

    struct FillCase: Sendable, CustomTestStringConvertible {
        let name: NSAppearance.Name
        let alpha: Double
        var testDescription: String { name == .aqua ? "light appearance" : "dark appearance" }

        static let all = [Self(name: .aqua, alpha: 0.666), Self(name: .darkAqua, alpha: 0.1)]
    }

    @Test(arguments: FillCase.all)
    func theFillResolvesWhiteAtTheAppearancesAlpha(_ sample: FillCase) throws {
        let name = sample.name
        let alpha = sample.alpha
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let pending = fixture.session.placeholder
        pending.appearance = NSAppearance(named: name)
        pending.updateLayer()
        let fill = try #require(pending.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
        #expect(fill.redComponent == 1 && fill.greenComponent == 1 && fill.blueComponent == 1)
        #expect(abs(fill.alphaComponent - alpha) < 0.0001)
    }

    @Test func thePlaceholderOwnsTheHighlightBorderLayer() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let pending = fixture.session.placeholder
        #expect(pending.layer?.sublayers?.contains(pending.splitHighlight.layer) == true)
    }

    @Test func presentingNeverCreatesASavedPage() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.store.state == fixture.before)
    }

    @Test func invalidatingTheOwnerRevokesTheTemporaryPane() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.owner.valid = false
        #expect(!fixture.session.isValid)
    }

    @Test func cancellationRemovesThePlaceholder() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.session.cancel()
        #expect(fixture.session.cancelled)
        #expect(fixture.session.placeholder.superview == nil)
    }

    @Test func aReturningOwnerCannotReviveACancelledPresentation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.owner.valid = false
        fixture.session.cancel()
        fixture.owner.valid = true
        #expect(!fixture.session.isValid)
    }

    @Test func repeatedCancellationNeverChangesTheContentRecords() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.session.cancel()
        fixture.session.cancel()
        #expect(fixture.store.state == fixture.before)
    }
}
