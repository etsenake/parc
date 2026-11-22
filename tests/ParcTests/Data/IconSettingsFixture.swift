import AppKit
import Testing
@testable import Parc
@testable import ParcSettings

@MainActor
final class IconSettingsWindow: NSWindow {
    var simulatedKey = true
    override var isKeyWindow: Bool { simulatedKey }
}

@MainActor
final class IconSettingsFixture {
    static let variantIDs = ["Original", "Sorbet", "AfterHours", "RainGlass", "Recess", "Twilight", "Opal",
                             "TracingPaper", "Grapefruit", "Terminal"]

    let directory: URL
    let icons: AppIconController
    let view: IconSettingsView
    let window: IconSettingsWindow
    let rows: [IconChoiceRow]
    private final class State {
        var applications = 0
        var applicationActive = true
        var pendingRefreshes: [@MainActor () -> Void] = []
    }

    private let state: State
    var applications: Int { state.applications }
    var applicationActive: Bool {
        get { state.applicationActive }
        set { state.applicationActive = newValue }
    }

    var original: IconChoiceRow { rows[0] }
    var sorbet: IconChoiceRow { rows[1] }
    var afterHours: IconChoiceRow { rows[2] }

    init() throws {
        let state = State()
        self.state = state
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let artwork = directory.appendingPathComponent("AppIcons", isDirectory: true)
        try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
        let catalog = ["default": "Original", "variants": Self.variantIDs] as [String: Any]
        try JSONSerialization.data(withJSONObject: catalog).write(to: artwork.appendingPathComponent("catalog.json"))
        let png = try Self.solidPNG()
        for id in Self.variantIDs { try png.write(to: artwork.appendingPathComponent(id + ".png")) }
        icons = AppIconController(resources: directory)
        view = IconSettingsView(icons: icons) { state.pendingRefreshes.append($0) }
        window = IconSettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 920),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let backdrop = NSView(frame: view.frame)
        window.contentView = backdrop
        backdrop.addSubview(view)
        view.layoutSubtreeIfNeeded()
        rows = Self.rows(in: view)
        icons.configure(preferenceURL: directory.appendingPathComponent("choice.json")) { _ in
            state.applications += 1
            return nil
        }
        for row in rows { row.applicationIsActive = { state.applicationActive } }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func close() {
        window.contentView = nil
        window.close()
    }

    func mouse(_ type: NSEvent.EventType, on row: NSView, inside: Bool = true) -> NSEvent {
        let point = inside ? NSPoint(x: 160, y: 40) : NSPoint(x: -10, y: -10)
        return NSEvent.mouseEvent(with: type, location: row.convert(point, to: nil), modifierFlags: [],
                                  timestamp: 0, windowNumber: row.window!.windowNumber, context: nil,
                                  eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    func key(_ type: NSEvent.EventType, _ code: UInt16, repeated: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                         isARepeat: repeated, keyCode: code)!
    }

    func click(_ row: IconChoiceRow) {
        row.mouseDown(with: mouse(.leftMouseDown, on: row))
        row.mouseUp(with: mouse(.leftMouseUp, on: row))
    }

    func press(_ row: IconChoiceRow, code: UInt16) {
        row.keyDown(with: key(.keyDown, code))
        row.keyUp(with: key(.keyUp, code))
    }

    func refreshPendingSelection() {
        let work = state.pendingRefreshes
        state.pendingRefreshes.removeAll()
        work.forEach { $0() }
    }

    private static func rows(in view: NSView) -> [IconChoiceRow] {
        view.subviews.flatMap { ($0 as? IconChoiceRow).map { [$0] } ?? rows(in: $0) }
    }

    private static func solidPNG() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
                                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
