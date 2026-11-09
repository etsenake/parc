import AppKit

///
/// window is key. During Replay a key browser keeps its own Close Tab.
@MainActor
enum OnboardingCloseCommand {
    static func owns(setup: NSWindow?, key: NSWindow?) -> Bool {
        guard let setup, let key else { return false }
        return key === setup || key.sheetParent === setup
    }

    /// A sheet on setup keeps Close Setup in the menu without closing setup.
    static func isAvailable(setup: NSWindow?) -> Bool {
        guard let setup else { return false }
        return setup.attachedSheet == nil
    }
}
