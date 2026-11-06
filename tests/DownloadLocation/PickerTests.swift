import AppKit

// The real DownloadLocationPicker plus the Settings Downloads card built by the
// exact layout lines sliced from SettingsWindow.swift (check-picker.py).
// Synthetic profile values only: no Chromium, profile, panel or user file.
@main
@MainActor
struct DownloadLocationPickerTests {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func expect(_ value: Bool, _ message: String) throws {
        assertions += 1
        if !value { throw Failure(message: message) }
    }

    static let downloadsIcon = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/DownloadsFolder.icns")
        ?? NSWorkspace.shared.icon(for: .folder)
    static let folderIcon = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericFolderIcon.icns")
        ?? NSWorkspace.shared.icon(for: .folder)
    static func makePicker() -> DownloadLocationPicker {
        let picker = DownloadLocationPicker()
        picker.iconProvider = { $0.lastPathComponent == "Downloads" ? downloadsIcon : folderIcon }
        return picker
    }

    static func main() throws {
        _ = NSApplication.shared
        let downloads = URL(fileURLWithPath: "/Users/parc-sample/Downloads", isDirectory: true)
        let custom = URL(fileURLWithPath: "/Volumes/Archive/Incoming Files", isDirectory: true)
        let picker = makePicker()
        var chosen: [DownloadLocationPicker.Choice] = []
        picker.onChoose = { chosen.append($0) }

        try expect(picker.frame.width == 180 && DownloadLocationPicker.width == 180, "the picker is 180 pt wide")
        try expect(!picker.pullsDown, "the default macOS picker is a pop-up, not a pull-down")
        try expect(picker.accessibilityLabel() == "Download Location", "The hidden Picker label stays the accessible name")
        try expect(picker.itemTitles == ["Unavailable"] && !picker.isEnabled,
                   "Without a snapshot the picker shows no guessed folder and cannot act")

        picker.update(.init(directory: downloads, prompt: false), enabled: true)
        try expect(picker.itemTitles == ["Downloads", "Other…", "", "Ask every time"], "the rows in the order")
        try expect(picker.item(at: 2)?.isSeparatorItem == true, "the Divider sits between Other… and Ask every time")
        try expect(picker.itemArray.filter { !$0.isSeparatorItem }.map(\.tag) == [0, 1, 2], "Rows carry the Tag cases")
        try expect(picker.selectedTag() == 0 && picker.titleOfSelectedItem == "Downloads", "No prompt selects the folder row")
        try expect(picker.selectedItem?.state == .on, "The shown row carries the menu checkmark")
        try expect(picker.item(at: 0)?.image?.size == NSSize(width: 16, height: 16), "Parc draws the folder icon at 16×16")
        try expect(picker.item(at: 1)?.image == nil && picker.item(at: 3)?.image == nil, "Only the folder row has an icon")
        if #available(macOS 27, *) {
            try expect(picker.item(at: 0)?.preferredImageVisibility == .visible,
                       "The folder row asks to show its icon .titleAndIcon label does")
        }
        try expect(picker.item(at: 0)?.toolTip == downloads.path && picker.toolTip == downloads.path,
                   "The full effective path stays reachable on hover")
        try expect(picker.isEnabled, "An unmanaged profile can change its location")

        //
        picker.selectItem(withTag: 0); _ = picker.sendAction(picker.action, to: picker.target)
        try expect(chosen.isEmpty, "Re-choosing the folder row sends nothing")
        picker.selectItem(withTag: 2); _ = picker.sendAction(picker.action, to: picker.target)
        try expect(chosen == [.prompt], "Ask every time asks for the prompt")
        picker.selectItem(withTag: 1); _ = picker.sendAction(picker.action, to: picker.target)
        try expect(chosen == [.prompt, .other], "Other… asks for the folder panel")
        picker.revert()
        try expect(picker.selectedTag() == 0, "A choice that could not start reverts to the effective row")

        picker.update(.init(directory: downloads, prompt: true), enabled: true)
        try expect(picker.selectedTag() == 2 && picker.titleOfSelectedItem == "Ask every time",
                   "An effective prompt selects Ask every time")
        try expect(picker.toolTip == nil, "Ask every time shows no folder path")
        picker.selectItem(withTag: 2); _ = picker.sendAction(picker.action, to: picker.target)
        try expect(chosen == [.prompt, .other], "Re-choosing Ask every time sends nothing")
        picker.selectItem(withTag: 0); _ = picker.sendAction(picker.action, to: picker.target)
        try expect(chosen == [.prompt, .other, .folder], "The folder row turns asking off")

        picker.update(.init(directory: custom, prompt: false), enabled: true)
        try expect(picker.titleOfSelectedItem == "Incoming Files", "A custom folder shows its own last path component")
        try expect(picker.item(at: 0)?.toolTip == custom.path, "The custom folder's full path is on hover")

        //
        // effective value returns whichever way the panel ended.
        picker.update(.init(directory: downloads, prompt: true), enabled: true, panelOpen: true)
        try expect(picker.numberOfItems == 0 && picker.panelOpen, "The picker is empty while its folder panel runs")
        picker.revert()
        try expect(picker.numberOfItems == 0, "Nothing is reselected while the panel runs")
        picker.update(.init(directory: downloads, prompt: true), enabled: true)
        try expect(picker.selectedTag() == 2, "Cancel restores the effective value")
        picker.update(.init(directory: custom, prompt: false), enabled: true)
        try expect(picker.selectedTag() == 0 && picker.titleOfSelectedItem == "Incoming Files",
                   "A chosen folder with asking forced off shows the folder row")

        picker.update(.init(directory: custom, prompt: false), enabled: false)
        try expect(!picker.isEnabled && picker.titleOfSelectedItem == "Incoming Files",
                   "A managed value is shown but cannot be changed")
        chosen.removeAll()
        picker.selectItem(withTag: 2); _ = picker.sendAction(picker.action, to: picker.target)
        try expect(chosen == [.prompt], "The component reports; SettingsWindow refuses managed changes")

        //
        let titled = makePicker()
        let group = DownloadsCardHarness(picker: titled).build(in: LayoutView(frame: NSRect(x: 0, y: 0, width: 680, height: 692)))
        let title = titled.rowTitle as? NSTextField
        try expect(title?.stringValue == "Download location" && title?.superview === group,
                   "The card's Download location title is the picker's row title")
        try expect(title?.alphaValue == 0.25, "Without a snapshot the row title dims with the picker")
        titled.update(.init(directory: downloads, prompt: false), enabled: true)
        try expect(title?.alphaValue == 1, "An enabled row shows its title at full opacity")
        titled.update(.init(directory: downloads, prompt: false), enabled: false)
        try expect(title?.alphaValue == 0.25, "A managed row dims its title to the 25%")

        if let output = CommandLine.arguments.dropFirst().first {
            try render(to: URL(fileURLWithPath: output, isDirectory: true), downloads: downloads, custom: custom)
        }
        print("Download location picker: \(assertions) assertions passed")
    }

    // MARK: Acceptance images

    final class Backdrop: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
    }

    /// A drawing of the picker's actual NSMenu (titles, images, separator,
    /// checkmark). AppKit's open menu is a separate on-screen window that
    /// cannot be captured offscreen without screen-recording access.
    final class MenuModel: NSView {
        let items: [NSMenuItem]
        let font = NSFont.menuFont(ofSize: 0)
        init(items: [NSMenuItem], width: CGFloat) {
            self.items = items
            let height = items.reduce(CGFloat(10)) { $0 + ($1.isSeparatorItem ? 11 : 22) }
            super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        }
        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
            NSColor.controlBackgroundColor.setFill(); panel.fill()
            NSColor.separatorColor.setStroke(); panel.lineWidth = 1; panel.stroke()
            var y: CGFloat = 5
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            for item in items {
                if item.isSeparatorItem {
                    NSColor.separatorColor.setFill(); NSRect(x: 10, y: y + 5, width: bounds.width - 20, height: 1).fill()
                    y += 11; continue
                }
                if item.state == .on { ("✓" as NSString).draw(at: NSPoint(x: 9, y: y + 3), withAttributes: attributes) }
                var x: CGFloat = 26
                if let image = item.image {
                    image.draw(in: NSRect(x: x, y: y + 3, width: 16, height: 16), from: .zero, operation: .sourceOver,
                               fraction: 1, respectFlipped: true, hints: nil)
                    x += 21
                }
                (item.title as NSString).draw(at: NSPoint(x: x, y: y + 3), withAttributes: attributes)
                y += 22
            }
        }
    }

    static func write(_ view: NSView, _ url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(message: "No bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "No PNG") }
        try png.write(to: url)
    }

    static func card(_ value: DownloadLocationPicker.Value?, enabled: Bool, help: String, appearance: NSAppearance.Name,
                     menu: Bool = false, retry: Bool = false) -> NSView {
        let picker = makePicker()
        let harness = DownloadsCardHarness(picker: picker)
        harness.downloadHelp.font = .systemFont(ofSize: 11); harness.downloadHelp.textColor = .secondaryLabelColor
        harness.downloadHelp.maximumNumberOfLines = 2; harness.downloadHelp.lineBreakMode = .byWordWrapping
        harness.downloadHelp.cell?.truncatesLastVisibleLine = true
        harness.downloadHelp.stringValue = help
        harness.downloadRetry.bezelStyle = .rounded; harness.downloadRetry.isHidden = !retry
        let content = LayoutView(frame: NSRect(x: 0, y: 0, width: 680, height: 692))
        let group = harness.build(in: content)
        picker.update(value, enabled: enabled)
        let height = group.frame.height + 40 + (menu ? 120 : 0)
        let backdrop = Backdrop(frame: NSRect(x: 0, y: 0, width: group.frame.width + 40, height: height))
        group.removeFromSuperview()
        group.setFrameOrigin(NSPoint(x: 20, y: menu ? 80 : 20))
        backdrop.addSubview(group)
        if menu {
            // macOS opens a pop-up menu with the shown row over the button.
            let model = MenuModel(items: picker.itemArray, width: picker.frame.width + 24)
            let selected = picker.indexOfSelectedItem
            let offset = picker.itemArray.prefix(selected).reduce(CGFloat(5)) { $0 + ($1.isSeparatorItem ? 11 : 22) }
            let origin = group.convert(picker.frame.origin, to: backdrop)
            model.setFrameOrigin(NSPoint(x: origin.x - 24, y: origin.y + 3 - offset))
            backdrop.addSubview(model)
        }
        backdrop.appearance = NSAppearance(named: appearance)
        return backdrop
    }

    static func render(to directory: URL, downloads: URL, custom: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let help = "Applies to all Spaces using the “Personal” profile."
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            try write(card(.init(directory: downloads, prompt: false), enabled: true, help: help, appearance: appearance),
                      directory.appendingPathComponent("location-closed-folder-\(name).png"))
            try write(card(.init(directory: downloads, prompt: true), enabled: true, help: help, appearance: appearance),
                      directory.appendingPathComponent("location-closed-prompt-\(name).png"))
            try write(card(.init(directory: custom, prompt: false), enabled: false,
                           help: "Some download settings for “Personal” are managed by your organization.", appearance: appearance),
                      directory.appendingPathComponent("location-closed-managed-\(name).png"))
            try write(card(.init(directory: downloads, prompt: false), enabled: true, help: help, appearance: appearance, menu: true),
                      directory.appendingPathComponent("location-open-\(name).png"))
            try write(card(.init(directory: downloads, prompt: true), enabled: true, help: help, appearance: appearance, menu: true),
                      directory.appendingPathComponent("location-open-prompt-\(name).png"))
            try write(card(nil, enabled: false, help: "Download settings couldn’t be loaded.", appearance: appearance, retry: true),
                      directory.appendingPathComponent("location-closed-failed-\(name).png"))
        }
    }
}
