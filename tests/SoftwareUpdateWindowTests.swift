import AppKit

@main @MainActor
struct SoftwareUpdateWindowTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(value(), message)
    }

    static func main() {
        let info: [String: Any] = ["CFBundleName": "Parc", "CFBundleShortVersionString": "1.8.2", "CFBundleVersion": "22"]
        let (content, primary, secondary) = SoftwareUpdateWindow.content(style: .upToDate, info: info,
                                                                         icon: NSImage(size: NSSize(width: 1024, height: 1024)))
        let size = content.fittingSize
        print("up to date content: \(size.width) × \(size.height)")
        check(size.width == 270, "Up to date is a 270-point column")
        check(size.height == 341, "Up to date is 341 points tall")
        content.frame = NSRect(origin: .zero, size: size)
        content.layoutSubtreeIfNeeded()
        check(primary.frame.size == NSSize(width: 170, height: 48), "Close is a 170 × 48 button")
        check(primary.frame.minY == 38 && primary.frame.midX == 135, "Close sits 38 above the bottom, centred")
        check(primary.title == "Close" && secondary == nil, "Up to date offers only Close")
        let labels = content.subviews[0].subviews.compactMap { $0 as? NSTextField }.map(\.stringValue)
        check(labels == ["Parc", "1.8.2 (22)", "Your browser is up to date"], "Name, version and the up-to-date copy")
        let icon = content.subviews[0].subviews.first { $0 is NSImageView }!
        check(icon.frame.size == NSSize(width: 82, height: 82) && size.height - icon.frame.maxY == 54,
              "The 82-point icon view is 54 below the top")
        let version = content.subviews[0].subviews.compactMap { $0 as? NSTextField }[1]
        check(version.frame.height == 13, "The version label is its 11-point font's line height")

        let (update, install, later) = SoftwareUpdateWindow.content(
            style: .update(prompt: "You have v1.8.2.\nWould you like to download\nv1.9.0 (23) now?", action: "Download",
                           title: nil, notes: nil),
            info: info, icon: NSImage(size: NSSize(width: 1024, height: 1024)))
        print("update found content: \(update.fittingSize.width) × \(update.fittingSize.height)")
        check(update.fittingSize == NSSize(width: 692, height: 418), "Update found is 692 × 418")
        check(install.title == "Download" && later?.title == "Remind me Later", "Update found offers Download and Remind me Later")
        print("SoftwareUpdateWindowTests: \(checks) checks passed")
    }
}
