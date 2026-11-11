import AppKit
import ScreenCaptureKit

@MainActor
enum PortraitDesktopSnapshot {
    enum Failure: LocalizedError {
        case permission, unavailable
        var errorDescription: String? {
            switch self {
            case .permission: return "Allow Parc in System Settings → Privacy & Security → Screen Recording to use the desktop wallpaper."
            case .unavailable: return "The wallpaper for this display is unavailable. Choose a color or website background."
            }
        }
    }

    struct Candidate {
        let id: CGWindowID
        let processID: pid_t
        let bounds: CGRect
        let bundle: String
        let title: String
        let layer: Int

        func isWallpaper(for display: CGRect) -> Bool {
            guard layer <= Int(CGWindowLevelForKey(.desktopWindow)), bounds.width > 0, bounds.height > 0,
                  abs(bounds.minX - display.minX) < 1, abs(bounds.minY - display.minY) < 1,
                  abs(bounds.width - display.width) < 1, abs(bounds.height - display.height) < 1 else { return false }
            switch bundle {
            case "com.apple.dock": return !title.isEmpty && title != "Dock"
            case "com.apple.WindowManager": return title == "Wallpaper"
            case "com.apple.wallpaper": return true
            default: return false
            }
        }
    }

    static func capture(screen: NSScreen?) async throws -> NSImage {
        guard CGPreflightScreenCaptureAccess() else { throw Failure.permission }
        guard let screen, let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw Failure.unavailable
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        let bounds = CGDisplayBounds(displayID)
        let records = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let candidates = records.compactMap { record -> Candidate? in
            guard let id = record[kCGWindowNumber as String] as? NSNumber,
                  let pid = record[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = record[kCGWindowLayer as String] as? NSNumber,
                  let rectangle = record[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: rectangle as CFDictionary),
                  let application = NSRunningApplication(processIdentifier: pid.int32Value),
                  let bundle = application.bundleIdentifier else { return nil }
            return Candidate(id: id.uint32Value, processID: pid.int32Value, bounds: rect, bundle: bundle,
                             title: record[kCGWindowName as String] as? String ?? "", layer: layer.intValue)
        }.filter { $0.isWallpaper(for: bounds) }
        guard let candidate = candidates.first else { throw Failure.unavailable }
        try Task.checkCancellation()
        let image: CGImage
        if #available(macOS 14.0, *) {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard CGPreflightScreenCaptureAccess(),
                  let window = content.windows.first(where: { $0.windowID == candidate.id &&
                      $0.owningApplication?.processID == candidate.processID && $0.frame == candidate.bounds }) else {
                throw Failure.unavailable
            }
            let configuration = SCStreamConfiguration()
            configuration.width = Int((bounds.width * screen.backingScaleFactor).rounded())
            configuration.height = Int((bounds.height * screen.backingScaleFactor).rounded())
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.colorSpaceName = screen.colorSpace?.cgColorSpace?.name ?? CGColorSpace.sRGB
            image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                              configuration: configuration)
        } else {
            guard let result = legacyImage(candidate) else { throw Failure.unavailable }
            image = result
        }
        try Task.checkCancellation()
        guard CGDisplayIsActive(displayID) != 0, CGDisplayBounds(displayID) == bounds,
              image.width > 0, image.height > 0 else { throw Failure.unavailable }
        return NSImage(cgImage: image, size: bounds.size)
    }

    @available(macOS, introduced: 10.15, obsoleted: 14.0)
    private static func legacyImage(_ candidate: Candidate) -> CGImage? {
        CGWindowListCreateImage(candidate.bounds, .optionIncludingWindow, candidate.id, .boundsIgnoreFraming)
    }
}
