import AppKit
import Testing
import ParcEngine
import ParcEngineDoubles
@testable import Parc
@testable import ParcCore
@testable import ParcEasels
@testable import ParcLibrary

private final class KeyCaptureWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}

@MainActor
private final class CaptureGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivals = 0

    func wait() async {
        arrivals += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private struct CaptureSendFailure: LocalizedError {
    var errorDescription: String? { "That Easel can’t take more images right now." }
}

private struct CaptureDesktopUnavailable: Error {}

@MainActor
private final class CaptureControllerFixture {
    struct EaselSend { let png: Data; let id: UUID?; let input: EaselImageInput }
    struct NoteSend { let png: Data; let target: CaptureNoteTarget; var snapshot: Data? = nil }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ParcCaptureController-" + UUID().uuidString)
    let engine = PageCaptureTestLease()
    let window = KeyCaptureWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                                  styleMask: [.borderless], backing: .buffered, defer: true)
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760))
    let container = NSView(frame: NSRect(x: 150, y: 80, width: 800, height: 600))
    let source = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let defaultsSuite = "parc.tests.capture-controller." + UUID().uuidString
    let png: Data
    let easel = CaptureEaselDestination(id: UUID(), title: "Trip ideas", lastActive: Date(timeIntervalSince1970: 1_700_000_000))
    let otherEasel = CaptureEaselDestination(id: UUID(), title: "Reading list", lastActive: Date(timeIntervalSince1970: 1_600_000_000))
    let noteURL: URL
    let store: BrowserStore
    let destination: CaptureLibraryDestination?

    var isValid = true
    var easelLoads = 0
    var easelGate: CaptureGate?
    var easelFailure: Error?
    var noteFailure: Error?
    var easelSends: [EaselSend] = []
    var noteSends: [NoteSend] = []
    var finishes: [Bool] = []
    private(set) var controller: PageCaptureController!

    init(library: Bool = true, notes: Bool = true) async throws {
        png = Self.pngBytes()
        noteURL = root.appendingPathComponent("Notes/Packing.md")
        store = try BrowserStore(directory: root.appendingPathComponent("Profile"))
        destination = library ? CaptureLibraryDestination.make(store: store, parent: nil,
            profileID: store.activeSpace.profileID, spaceID: store.activeSpaceID) : nil
        if let destination { await destination.library.reload() }
        engine.pngData = png
        engine.viewportSize = NSSize(width: 800, height: 600)
        engine.viewportFrame = source.bounds
        engine.sourceURL = "https://example.test/trip/plan"
        engine.pageTitle = "Trip plan"
        engine.pageThemeColor = .systemTeal
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.addSubview(container)
        container.addSubview(source)
        let note = CaptureNoteDestination(url: noteURL, title: "Packing", icon: nil,
                                          lastActive: Date(timeIntervalSince1970: 1_700_000_000), modifiedAt: Date(timeIntervalSince1970: 1_650_000_000))
        let overlay = PageCaptureOverlay(frame: .zero, now: { 0 }, reduceMotion: { true }, scheduleFrames: { _ in })
        overlay.alertSound = {}
        let lease = try #require(engine.lease as? PCNativePageCapture)
        controller = PageCaptureController(lease: lease, sourceView: source, containerView: container, host: host, parent: window,
            valid: { [weak self] in self?.isValid == true }, destination: destination,
            easelDestinations: { [weak self] in
                guard let self else { throw CocoaError(.userCancelled) }
                self.easelLoads += 1
                if let gate = self.easelGate { await gate.wait() }
                return [self.easel, self.otherEasel]
            }, addToEasel: { [weak self] input, id in
                guard let self else { return }
                if let failure = self.easelFailure { throw failure }
                self.easelSends.append(EaselSend(png: input.pngData, id: id, input: input))
            }, noteDestinations: notes ? { [weak self] in
                if let failure = self?.noteFailure { throw failure }
                return [note]
            } : nil, addToNote: notes ? { [weak self] input, target in
                self?.noteSends.append(NoteSend(png: input.pngData, target: target, snapshot: input.snapshotPDF))
            } : nil,
            presentation: overlay, framing: CaptureFramingEnvironment(defaults: UserDefaults(suiteName: defaultsSuite) ?? .standard,
                palette: PortraitCaptureRenderer.palette(bundle: .module, subdirectory: "CaptureFixtures/ThemeEditor"),
                desktop: { _ in throw CaptureDesktopUnavailable() }),
            finished: { [weak self] restoreFocus in self?.finishes.append(restoreFocus) })
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: root)
    }

    nonisolated static func pngBytes() -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 120,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let bytes = bitmap.bitmapData!
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let pixel = bytes + y * bitmap.bytesPerRow + x * 4
                pixel[0] = UInt8(x % 256); pixel[1] = UInt8(y % 256); pixel[2] = 0x80; pixel[3] = 0xff
            }
        }
        return bitmap.representation(using: .png, properties: [:])!
    }

    var palette: CapturePalette { controller.overlay.palette }
    var error: String? { palette.view.errorText }
    var capturedPNG: Data { get throws { try CapturedImage(pngData: png, backingScale: window.backingScaleFactor).pngData } }
    var captureMethods: [PageCaptureTestMethod] { engine.captureMethods.compactMap { PageCaptureTestMethod(rawValue: $0.intValue) } }

    func capture(_ mode: PageCaptureController.Mode = .viewport) async {
        controller.present(mode)
        await controller.destinationsLoad?.value
    }

    func row(_ action: CapturePaletteAction) -> CapturePaletteRow? {
        CapturePaletteMenu.rows(palette.context).first { $0.id == action.id }
    }

    func easelRow(_ id: UUID) -> CapturePaletteRow? {
        CapturePaletteMenu.submenu(.easels, context: palette.context).first {
            if case .document(let document) = $0.action, document.target == .easel(id) { return true }
            return false
        }
    }

    func noteRow(_ id: String) -> CapturePaletteRow? {
        CapturePaletteMenu.submenu(.notes, context: palette.context).first { $0.id == id }
    }

    func click(_ row: CapturePaletteRow?) throws {
        let row = try #require(row)
        try #require(row.isEnabled)
        palette.onAction?(row.action)
    }

    func press(_ action: CapturePaletteAction) {
        palette.onAction?(action)
    }

    var portrait: PortraitCaptureView? { palette.view.frameContent as? PortraitCaptureView }

    func saveToLibrary() async throws {
        try click(row(.library))
        let write = try #require(controller.libraryWrite)
        await write.value
    }
}

@Suite("Capture controller sending")
struct CaptureControllerSendTests {
    @MainActor @Test func aVisibleAreaCaptureSendsItsPNGToTheChosenEasel() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        #expect(fixture.captureMethods == [.viewport])
        #expect(fixture.palette.context.easels.map(\.id).contains(fixture.easel.id))

        try fixture.click(fixture.easelRow(fixture.easel.id))

        #expect(fixture.easelSends.count == 1)
        let send = try #require(fixture.easelSends.first)
        let expected = try fixture.capturedPNG
        #expect(send.id == fixture.easel.id)
        #expect(send.png == expected)
        #expect(send.input.pageTitle == "Trip plan")
        #expect(send.input.sourceURL?.absoluteString == "https://example.test/trip/plan")
        #expect(fixture.finishes == [false])
        #expect(fixture.engine.invalidations == 1)
    }

    @MainActor @Test func aFramedCaptureSendsTheFramedImageToTheEasel() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        try fixture.click(fixture.row(.frame))
        let portrait = try #require(fixture.portrait)
        portrait.onCapture?()
        #expect(fixture.portrait == nil)
        #expect(fixture.palette.context.framed)

        try fixture.click(fixture.easelRow(fixture.easel.id))

        let send = try #require(fixture.easelSends.first)
        #expect(fixture.easelSends.count == 1)
        #expect(send.id == fixture.easel.id)
        let original = try fixture.capturedPNG
        #expect(send.png != original)
        #expect(NSBitmapImageRep(data: send.png) != nil)
        #expect(send.input.captureLayout == nil)
        #expect(fixture.finishes == [false])
    }

    @MainActor @Test func aCaptureSavedToTheLibraryStillSendsToTheEasel() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        try await fixture.saveToLibrary()
        #expect(fixture.palette.context.librarySaved)
        #expect(fixture.destination?.library.items.count == 1)

        try fixture.click(fixture.easelRow(fixture.otherEasel.id))

        let expected = try fixture.capturedPNG
        #expect(fixture.easelSends.map(\.id) == [fixture.otherEasel.id])
        #expect(fixture.easelSends.first?.png == expected)
        #expect(fixture.finishes == [false])
    }

    @MainActor @Test func aLibrarySaveInFlightHoldsSaveAndRetakeButNotSending() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        try fixture.click(fixture.row(.library))
        let write = try #require(fixture.controller.libraryWrite)
        #expect(fixture.palette.context.libraryBusy)
        #expect(fixture.row(.library)?.isEnabled == false)
        #expect(fixture.row(.retake)?.isEnabled == false)
        #expect(fixture.easelRow(fixture.easel.id)?.isEnabled == true)

        fixture.press(.retake)
        fixture.press(.library)
        #expect(fixture.captureMethods == [.viewport])
        #expect(fixture.controller.libraryWrite == write)
        #expect(fixture.finishes.isEmpty)

        try fixture.click(fixture.easelRow(fixture.easel.id))

        #expect(fixture.easelSends.map(\.id) == [fixture.easel.id])
        #expect(fixture.finishes == [false])
        await write.value
    }

    @MainActor @Test func aLibrarySaveInFlightStillSendsToANote() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        try fixture.click(fixture.row(.library))
        let write = try #require(fixture.controller.libraryWrite)

        try fixture.click(fixture.noteRow(CaptureNoteTarget.note(fixture.noteURL).id))

        #expect(fixture.noteSends.map(\.target) == [.note(fixture.noteURL)])
        #expect(fixture.finishes == [false])
        await write.value
    }

    @MainActor @Test func aPageThatStopsBeingCurrentSaysTheCaptureExpiredAndStaysOpen() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        fixture.isValid = false

        try fixture.click(fixture.easelRow(fixture.easel.id))

        #expect(fixture.easelSends.isEmpty)
        #expect(fixture.error == CaptureSendRefusal.captureExpired.localizedDescription)
        #expect(fixture.finishes.isEmpty)
        #expect(fixture.engine.invalidations == 0)
        #expect(fixture.controller.overlay.superview === fixture.host)

        fixture.palette.onCancel?()
        #expect(fixture.finishes == [true])
        #expect(fixture.engine.invalidations == 1)
        #expect(fixture.controller.overlay.superview == nil)
    }

    @MainActor @Test func aLeaseThatTurnsInvalidSaysTheCaptureExpiredAndStaysOpen() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        fixture.engine.isValid = false

        try fixture.click(fixture.noteRow(CaptureNoteTarget.note(fixture.noteURL).id))

        #expect(fixture.noteSends.isEmpty)
        #expect(fixture.error == CaptureSendRefusal.captureExpired.localizedDescription)
        #expect(fixture.finishes.isEmpty)
        #expect(fixture.controller.overlay.superview === fixture.host)
    }

    @MainActor @Test func aWindowThatCannotBecomeKeySaysSoAndSendsNothing() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        fixture.window.key = false

        try fixture.click(fixture.easelRow(fixture.easel.id))

        #expect(fixture.easelSends.isEmpty)
        #expect(fixture.error == CaptureSendRefusal.windowNotActive.localizedDescription)
        #expect(fixture.finishes.isEmpty)
        #expect(fixture.controller.overlay.superview === fixture.host)

        fixture.window.key = true
        try fixture.click(fixture.easelRow(fixture.easel.id))
        #expect(fixture.easelSends.map(\.id) == [fixture.easel.id])
        #expect(fixture.finishes == [false])
    }

    @MainActor @Test func anEngineInvalidationClosesThePreview() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        #expect(fixture.engine.hasInvalidationHandler)

        fixture.engine.invalidateFromEngine()

        #expect(fixture.finishes == [false])
        #expect(!fixture.engine.hasInvalidationHandler)
        try fixture.click(fixture.easelRow(fixture.easel.id))
        #expect(fixture.easelSends.isEmpty)
        #expect(fixture.finishes == [false])
    }

    @MainActor @Test func aFailedEaselSendKeepsTheCaptureOpenWithTheErrorAndReloadsInTheBackground() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        #expect(fixture.easelLoads == 1)
        let gate = CaptureGate()
        fixture.easelGate = gate
        fixture.easelFailure = CaptureSendFailure()

        try fixture.click(fixture.easelRow(fixture.easel.id))

        #expect(fixture.finishes.isEmpty)
        #expect(fixture.error == "That Easel can’t take more images right now.")
        let reload = try #require(fixture.controller.destinationsLoad)
        #expect(fixture.controller.overlay.superview === fixture.host)

        fixture.easelFailure = nil
        try fixture.click(fixture.easelRow(fixture.easel.id))
        #expect(fixture.easelSends.map(\.id) == [fixture.easel.id])
        #expect(fixture.finishes == [false])

        gate.open()
        await reload.value
        #expect(fixture.easelLoads == 1)
        #expect(gate.arrivals == 0)
    }

    @MainActor @Test func aFailedEaselSendReloadsTheEaselListWithoutClearingTheError() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()
        let gate = CaptureGate()
        fixture.easelGate = gate
        fixture.easelFailure = CaptureSendFailure()

        try fixture.click(fixture.easelRow(fixture.easel.id))
        let reload = try #require(fixture.controller.destinationsLoad)
        gate.open()
        await reload.value

        #expect(fixture.easelLoads == 2)
        #expect(gate.arrivals == 1)
        #expect(fixture.palette.context.easels.map(\.id) == [fixture.easel.id, fixture.otherEasel.id])
        #expect(fixture.error == "That Easel can’t take more images right now.")
        #expect(fixture.finishes.isEmpty)
    }

    @MainActor @Test func sendingToANoteDeliversToThatNote() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()

        try fixture.click(fixture.noteRow(CaptureNoteTarget.note(fixture.noteURL).id))

        #expect(fixture.noteSends.count == 1)
        #expect(fixture.noteSends.first?.target == .note(fixture.noteURL))
        let expected = try fixture.capturedPNG
        #expect(fixture.noteSends.first?.png == expected)
        #expect(fixture.easelSends.isEmpty)
        #expect(fixture.finishes == [false])
    }

    @MainActor @Test func newNoteSendsToANewNote() async throws {
        let fixture = try await CaptureControllerFixture()
        await fixture.capture()

        try fixture.click(fixture.noteRow(CaptureNoteTarget.newNote.id))

        #expect(fixture.noteSends.map(\.target) == [.newNote])
        #expect(fixture.finishes == [false])
    }

    @MainActor @Test func aCaptureDeliveredLaterStillReachesTheEasel() async throws {
        let fixture = try await CaptureControllerFixture()
        fixture.engine.deliversImmediately = false
        fixture.controller.present(.fullPage)
        #expect(fixture.captureMethods == [.fullPage])
        #expect(fixture.engine.pendingCaptures == 1)
        #expect(fixture.controller.destinationsLoad == nil)

        #expect(fixture.engine.deliverNextCapture())
        await fixture.controller.destinationsLoad?.value

        try fixture.click(fixture.easelRow(fixture.easel.id))
        #expect(fixture.easelSends.map(\.id) == [fixture.easel.id])
        #expect(fixture.finishes == [false])
    }
}

@Suite("Capture controller sharp full pages")
struct CaptureControllerSnapshotTests {
    static let pdf = Data("%PDF-1.7 full page".utf8)

    @MainActor @Test func aFullPageCaptureSendsItsPageDocumentWithThePictureToEaselsAndNotes() async throws {
        let fixture = try await CaptureControllerFixture()
        fixture.engine.pdfData = Self.pdf
        await fixture.capture(.fullPage)
        try fixture.click(fixture.easelRow(fixture.easel.id))
        #expect(fixture.easelSends.first?.input.snapshotPDF == Self.pdf)
        #expect(fixture.easelSends.first?.png == (try fixture.capturedPNG))

        let again = try await CaptureControllerFixture()
        again.engine.pdfData = Self.pdf
        await again.capture(.fullPage)
        try again.click(again.noteRow(CaptureNoteTarget.note(again.noteURL).id))
        #expect(again.noteSends.first?.snapshot == Self.pdf)
    }

    @MainActor @Test func onlyFullPageCapturesCarryAPageDocument() async throws {
        let fixture = try await CaptureControllerFixture()
        fixture.engine.pdfData = Self.pdf
        await fixture.capture(.viewport)
        try fixture.click(fixture.easelRow(fixture.easel.id))
        #expect(fixture.easelSends.count == 1 && fixture.easelSends.first?.input.snapshotPDF == nil)
    }

    @MainActor @Test func aFramedFullPageCaptureDropsThePageDocument() async throws {
        let fixture = try await CaptureControllerFixture()
        fixture.engine.pdfData = Self.pdf
        await fixture.capture(.fullPage)
        try fixture.click(fixture.row(.frame))
        let portrait = try #require(fixture.portrait)
        portrait.onCapture?()
        try fixture.click(fixture.easelRow(fixture.easel.id))
        #expect(fixture.easelSends.count == 1 && fixture.easelSends.first?.input.snapshotPDF == nil)
    }
}
