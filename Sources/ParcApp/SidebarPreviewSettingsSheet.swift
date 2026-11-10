import AppKit

/// General's original Settings window owns this immediate-preference sheet.
/// Done dismisses it; it does not commit or roll back a second preference copy.
@MainActor
final class SidebarPreviewSettingsSheet: NSWindowController {
    private let defaults: UserDefaults
    private weak var parent: NSWindow?
    private var presented = false
    private var retired = false
    private var observers: [NSObjectProtocol] = []
    private var choices: [SidebarPreviewPreference: NSButton] = [:]
    private let done = NSButton(title: "Done", target: nil, action: nil)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Keep the observed 24pt inset and row spacing; omitted live providers
        // reduce the height without leaving dead controls or empty rows.
        let size = NSSize(width: 422, height: 272)
        let sheet = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        sheet.title = "Previews Settings"
        sheet.titleVisibility = .hidden
        sheet.titlebarAppearsTransparent = true
        sheet.isReleasedWhenClosed = false
        sheet.tabbingMode = .disallowed
        super.init(window: sheet)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        sheet.contentView = content
        let heading = NSTextField(labelWithString: "Show Parc Previews:")
        heading.font = .systemFont(ofSize: 13, weight: .bold)
        heading.frame = NSRect(x: 24, y: size.height - 42, width: 374, height: 18)
        content.addSubview(heading)
        let help = NSTextField(wrappingLabelWithString:
            "Save a click! Hover over a Parc Folder or a tab to preview its contents, recent pages, or a picture of the page.")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        help.frame = NSRect(x: 24, y: size.height - 90, width: 374, height: 40)
        content.addSubview(help)
        for (index, preference) in SidebarPreviewPreference.allCases.enumerated() {
            let button = NSButton(checkboxWithTitle: preference.settingsTitle,
                                  target: self, action: #selector(preferenceChanged(_:)))
            button.font = .systemFont(ofSize: 12)
            button.identifier = NSUserInterfaceItemIdentifier(preference.rawValue)
            button.frame = NSRect(x: 22, y: size.height - 126 - CGFloat(index * 28), width: 378, height: 24)
            button.setAccessibilityLabel(preference.settingsTitle)
            content.addSubview(button)
            choices[preference] = button
        }
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.target = self
        done.action = #selector(finish)
        done.frame = NSRect(x: 306, y: 20, width: 92, height: 38)
        content.addSubview(done)
        sheet.defaultButtonCell = done.cell as? NSButtonCell
        choices[.folders]?.nextKeyView = choices[.recentPages]
        choices[.recentPages]?.nextKeyView = choices[.tabPictures]
        choices[.tabPictures]?.nextKeyView = done
        done.nextKeyView = choices[.folders]
        sheet.initialFirstResponder = choices[.folders]
        for name in [SidebarPreviewPreference.didChangeNotification, UserDefaults.didChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: defaults, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @discardableResult
    func present(for owner: NSWindow, completion: @escaping () -> Void) -> Bool {
        guard !presented, !retired, owner.isVisible, owner.attachedSheet == nil, let sheet = window else { return false }
        parent = owner
        presented = true
        owner.beginSheet(sheet) { [weak self, weak sheet] _ in
            self?.retire()
            sheet?.orderOut(nil)
            completion()
        }
        return true
    }

    func dismiss() {
        guard !retired else { return }
        let owner = parent
        let sheet = window
        retire()
        if let sheet, sheet.sheetParent === owner { owner?.endSheet(sheet, returnCode: .OK) }
        sheet?.orderOut(nil)
    }

    private func retire() {
        retired = true
        presented = false
        parent = nil
        choices.values.forEach { $0.isEnabled = false }
        done.isEnabled = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func refresh() {
        guard !retired else { return }
        for (preference, button) in choices {
            button.state = preference.isEnabled(in: defaults) ? .on : .off
        }
    }

    @objc private func preferenceChanged(_ sender: NSButton) {
        guard !retired, presented, let parent, let sheet = window,
              sheet.sheetParent === parent, parent.attachedSheet === sheet,
              let preference = choices.first(where: { $0.value === sender })?.key else { return }
        preference.setEnabled(sender.state == .on, in: defaults)
        refresh()
    }

    @objc private func finish() { dismiss() }
    override func cancelOperation(_ sender: Any?) { dismiss() }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
