import AppKit

@MainActor protocol ApplicationActivityReporting: NSWindow {
    var reportsApplicationActive: Bool { get }
}

extension NSWindow {
    package var applicationIsActive: Bool { (self as? ApplicationActivityReporting)?.reportsApplicationActive ?? NSApp.isActive }
}
