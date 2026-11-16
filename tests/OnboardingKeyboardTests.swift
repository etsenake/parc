import AppKit

@MainActor private final class ProbeWindow: NSWindow {
    var testParent: NSWindow?
    var testSheet: NSWindow?
    override var sheetParent: NSWindow? { testParent }
    override var attachedSheet: NSWindow? { testSheet }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}

@main
struct OnboardingKeyboardTests {
    @MainActor static var assertions = 0
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
        assertions += 1
        guard condition() else { fatalError("Line \(line): \(message)") }
    }

    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        closeSetupOwner()
        themeEditorLoop()
        print("PASS: onboarding Close Setup owner and theme editor Tab loop (\(assertions) assertions)")
    }

    @MainActor static func closeSetupOwner() {
        let setup = ProbeWindow(), browser = ProbeWindow(), sheet = ProbeWindow(), other = ProbeWindow()
        sheet.testParent = setup
        expect(OnboardingCloseCommand.owns(setup: setup, key: setup), "Key setup owns Close Setup")
        expect(OnboardingCloseCommand.owns(setup: setup, key: sheet), "A sheet on setup keeps Close Setup")
        expect(!OnboardingCloseCommand.owns(setup: setup, key: browser), "A key browser keeps Close Tab during Replay")
        other.testParent = browser
        expect(!OnboardingCloseCommand.owns(setup: setup, key: other), "A browser's sheet is not setup's")
        expect(!OnboardingCloseCommand.owns(setup: setup, key: nil), "No key window, no Close Setup")
        expect(!OnboardingCloseCommand.owns(setup: nil, key: setup), "No setup window, no Close Setup")
        expect(OnboardingCloseCommand.isAvailable(setup: setup), "Close Setup is available without a sheet")
        setup.testSheet = sheet
        expect(!OnboardingCloseCommand.isAvailable(setup: setup), "An attached sheet blocks Close Setup")
        expect(!OnboardingCloseCommand.isAvailable(setup: nil), "No setup window is unavailable")
    }

    @MainActor static func themeEditorLoop() {
        let sidebar = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let sidebarLinks = Self.links(in: sidebar)
        let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
        let following = NSView()
        let first = editor.firstKeyView
        editor.chainKeyViews(to: following)
        var visited: [NSView] = []
        var current: NSView? = first
        while let view = current, view !== following, visited.count < 100 {
            visited.append(view); current = view.nextKeyView
        }
        expect(current === following, "The editor's last control leads to the following setup control")
        expect(visited.count == 19, "Every editor control is in the loop (\(visited.count))")
        expect(Set(visited.map(ObjectIdentifier.init)).count == visited.count, "No control repeats")
        expect(visited.allSatisfy { $0.isDescendant(of: editor) }, "The loop stays inside the editor")
        expect(visited.allSatisfy { $0 is NSControl || $0.acceptsFirstResponder }, "Every loop member is a control")
        expect(!visited.contains { $0 === editor }, "The editor container is not a Tab stop")
        expect(Self.links(in: sidebar) == sidebarLinks, "An editor the setup never chains keeps its own loop")
    }

    @MainActor static func links(in view: NSView) -> [ObjectIdentifier?] {
        ([view] + view.subviews.flatMap { [$0] + $0.subviews }).map { $0.nextKeyView.map(ObjectIdentifier.init) }
    }
}
