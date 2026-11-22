import AppKit

@MainActor
enum OnboardingCloseCommand {
    static func owns(setup: NSWindow?, key: NSWindow?) -> Bool {
        guard let setup, let key else { return false }
        return key === setup || key.sheetParent === setup
    }

    static func isAvailable(setup: NSWindow?) -> Bool {
        guard let setup else { return false }
        return setup.attachedSheet == nil
    }
}
