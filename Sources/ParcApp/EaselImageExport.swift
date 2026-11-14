import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
protocol EaselImageExporting: AnyObject {
    var canExportEaselImage: Bool { get }
    func exportEaselImage()
}

@MainActor
enum EaselImageExport {
    static let menuTitle = "Export as Image"

    static func shareMenu(export: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        let action = Action(export)
        let item = NSMenuItem(title: menuTitle, action: #selector(Action.choose(_:)), keyEquivalent: "")
        item.target = action; item.representedObject = action
        item.showImage(SidebarIconCatalog.featherImage(0xE9CA, size: 14))
        menu.addItem(item)
        return menu
    }

    static func run(canvas: EaselCanvasView, title: String?, in window: NSWindow, valid: @escaping () -> Bool) {
        _ = canvas.collectExportPages { [weak canvas, weak window] pages in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let window, let canvas, canvas.window === window else { return }
                    guard valid() else { return showFailure(in: window) }
                    let scale = pixelDensity()
                    guard let image = canvas.exportImage(backingScale: scale, pages: pages) else { return showFailure(in: window) }
                    let panel = savePanel(title: title)
                    guard panel.runModal() == .OK else { return }
                    guard let url = panel.url else { return showFailure(in: window) }
                    do { try write(image, scale: scale, to: url) } catch { showFailure(in: window) }
                }
            }
        }
    }
    @MainActor private final class Failure {
        weak var window: NSWindow?
        let dialog = failureDialog()
        init(_ window: NSWindow) { self.window = window }
    }
    private static var failures: [Failure] = []
    private static func showFailure(in window: NSWindow) {
        RunLoop.main.perform(inModes: [.common, .modalPanel]) { [weak window] in
            MainActor.assumeIsolated {
                failures.removeAll { $0.window == nil }
                guard let window, !failures.contains(where: { $0.window === window }) else { return }
                let failure = Failure(window)
                failures.append(failure)
                let ended = { [weak failure] in failures.removeAll { $0 === failure } }
                if !failure.dialog.begin(for: window, queued: true, completion: { _ in ended() }) { ended() }
            }
        }
    }

    static func pixelDensity() -> CGFloat {
        let probe = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { _ in true }
        return CGFloat(probe.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? 64) / 64
    }

    static func savePanel(title: String?) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.title = "Export Easel"
        panel.allowedContentTypes = [.png, .jpeg]
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        panel.nameFieldStringValue = name.isEmpty ? "Untitled Easel" : name
        return panel
    }

    static func write(_ image: CGImage, scale: CGFloat, to url: URL) throws {
        let type: UTType = UTType(filenameExtension: url.pathExtension)?.conforms(to: .png) == true ? .png : .jpeg
        let files = FileManager.default
        let staging = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? files.removeItem(at: staging) }
        let encoded = staging.appendingPathComponent(url.lastPathComponent)
        guard let destination = CGImageDestinationCreateWithURL(encoded as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url]) }
        if files.fileExists(atPath: url.path) { _ = try files.replaceItemAt(url, withItemAt: encoded) }
        else { try files.moveItem(at: encoded, to: url) }
    }

    static func failureDialog() -> ParcDialog {
        ParcDialog(.init(title: [("Exporting Easel", false)],
                        message: [("Encountered problem exporting easel. Please try again later.", false)],
                        icon: ParcBrandMark.image(.borderless), confirm: "OK"))
    }

    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func choose(_ sender: Any?) { run() }
    }
}
