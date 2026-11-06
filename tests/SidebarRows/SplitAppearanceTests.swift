import AppKit
import CoreText
extension NSColor { static var parcInk: NSColor { .labelColor } }

@MainActor final class KeyTestWindow: NSWindow {
    var key = false
    override var isKeyWindow: Bool { key }
    convenience init() { self.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: true); isReleasedWhenClosed = false }
}

@main @MainActor struct SplitAppearanceTests {
    static var count = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ reason: String) throws {
        count += 1; if try !condition() { throw NSError(domain: reason, code: count) }
    }
    static func main() throws {
        _ = NSApplication.shared
        try check(SidebarIconCatalog.resourceDirectory == Bundle.main.resourceURL?.appendingPathComponent("CustomInfoPicker", isDirectory: true)
                  && SidebarIconCatalog.font(.ionicons, size: 14).fontName == "ionicons", "The icon resources load from the bundle's CustomInfoPicker resources")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-appearance-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let first = store.openResolvedURL(URL(string: "https://one.invalid")!), second = store.openResolvedURL(URL(string: "https://two.invalid")!)
        store.setSplit([first,second]); let profile = store.activeSpace.profileID, space = store.activeSpaceID
        func target() -> SidebarSplitTitleEdit { .current(state: store.state, spaceID: space, profileID: profile, selectedTabIDs: [first,second])! }
        let original = target(), originalTabs = store.state.tabs
        let icon = SidebarGroupIcon.symbol("star")
        try check(icon.isValid && SidebarGroupIcon.emoji("👩🏽‍💻").isValid, "Native symbol and composed emoji are valid")
        try check(!SidebarGroupIcon.emoji("text").isValid && !SidebarGroupIcon.symbol("unknown").isValid, "Arbitrary unsupported input is refused")
        let change = try store.saveSplitAppearance(original, icon: icon)!
        try check(target().group.customIcon == icon && target().group.customTitle == nil, "Icon-only customization does not name group")
        try check(store.state.tabs == originalTabs && target().group.id == original.group.id, "No page or child title mutation")
        try check(target().group.tabIDs == original.group.tabIDs && target().group.widthFactors == original.group.widthFactors, "Pane identity and geometry preserved")
        let named = try store.saveSidebarSplitTitle(target(), title: "Research")!
        try check(try store.applySplitAppearance(change, undo: true), "Icon Undo valid across independent title edit")
        try check(target().group.customIcon == nil && target().group.customTitle == "Research", "Icon Undo preserves later title")
        try check(try store.applySplitAppearance(change, undo: false), "Icon Redo restores same original icon")
        try check(try store.applySplitTitleChange(named, undo: true), "Title Undo valid across independent icon edit")
        try check(target().group.customTitle == nil && target().group.customIcon == icon, "Title Undo preserves icon")
        try store.saveSidebarSplitTitle(target(), title: "Together")
        let reset = try store.saveSplitAppearance(target(), icon: nil, reset: true)!
        try check(reset.actionName == "Reset Name and Icon" && change.actionName == "Customize Tab", "Native Undo labels follow recovered operations")
        try check(target().group.customIcon == nil && target().group.customTitle == nil, "Reset removes both overrides")
        try check(try store.applySplitAppearance(reset, undo: true), "Reset Undo restores both fields atomically")
        try check(target().group.customIcon == icon && target().group.customTitle == "Together", "Reset inverse restores originals")
        try check(try store.applySplitAppearance(reset, undo: false), "Reset Redo is complete")
        try store.saveSidebarSplitTitle(target(), title: "Other")
        try check(!store.canApplySplitAppearance(reset, undo: true), "Reset inverse refuses concurrent name replacement")
        let stale = target(); _ = try store.saveSplitAppearance(stale, icon: .emoji("🌙"))
        do { _ = try store.saveSplitAppearance(stale, icon: .symbol("heart")); preconditionFailure("stale accepted") } catch SidebarSplitTitleEdit.EditError.unavailable { }
        try check(target().group.customIcon == .emoji("🌙"), "Stale editor cannot replace shared icon")
        let old = original.group
        try check(store.setWindowPresentation(spaceID: space, selectedTabIDs: old.tabIDs, splitLayout: old), "Original window geometry restores")
        try check(target().group.customIcon == .emoji("🌙") && target().group.customTitle == "Other", "Cached geometry cannot overwrite current shared appearance")
        try check(store.setSplitLayout(orientation: .vertical, widthFactors: [1,3]), "Divider operation accepted")
        try check(target().group.customIcon == .emoji("🌙"), "Divider reconstruction keeps icon")
        let reload = try BrowserStore(directory: directory)
        try check(reload.state.splitLayouts.first?.customIcon == .emoji("🌙"), "Icon is durable")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(target().group)) as! [String: Any]
        legacy.removeValue(forKey: "customIcon")
        let decoded = try JSONDecoder().decode(BrowserSplitLayout.self, from: JSONSerialization.data(withJSONObject: legacy))
        try check(decoded.customIcon == nil && decoded.id == target().group.id, "Older stored groups decode unchanged")
        let file = directory.appendingPathComponent("session.json"), bytes = try Data(contentsOf: directory.appendingPathComponent("session.json")), before = store.state
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do { _ = try store.saveSplitAppearance(target(), icon: nil, reset: true); preconditionFailure("failed disk accepted") } catch {}
        try check(store.state == before, "Failed save preserves both fields and originals")
        try FileManager.default.removeItem(at: file); try bytes.write(to: file)

        // Same-profile Favorite group may retain a different stored home Space.
        let active = BrowserSpace(id: UUID(), name: "Other Space", symbol: "circle", color: "AABBCC", profileID: profile)
        var state = store.state; state.spaces.append(active); state.activeSpaceID = active.id
        for i in state.tabs.indices { if [first,second].contains(state.tabs[i].id) { state.tabs[i].kind = .favorite; state.tabs[i].folderID = nil } }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; try encoder.encode(state).write(to: file)
        let favorite = try BrowserStore(directory: directory)
        let originalFavoriteTabs = favorite.state.tabs
        let ft = SidebarSplitTitleEdit.current(state: favorite.state, spaceID: active.id, profileID: profile, selectedTabIDs: [first,second])!
        try check(ft.isFavorite && ft.group.spaceID == space && ft.isVisible(in: active.id, state: favorite.state), "Favorite editor uses original home group from another active Space")
        try check(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: active.id, profileID: UUID(), selectedTabIDs: [first,second]) == nil, "Foreign Profile refuses")
        try favorite.saveSidebarSplitTitle(ft, title: "  Exact favorite title  ")
        let fgroup = favorite.state.splitLayouts.first!
        try check(fgroup.customTitle == "  Exact favorite title  " && fgroup.id == ft.group.id, "Favorite required-name dialog preserves literal text and group")
        try check(favorite.state.tabs == originalFavoriteTabs, "Favorite Rename never targets anchor child")
        let current = SidebarSplitTitleEdit(group: fgroup, profileID: profile, state: favorite.state)!
        do { _ = try favorite.saveSidebarSplitTitle(current, title: ""); preconditionFailure("empty Favorite accepted") } catch SidebarSplitTitleEdit.EditError.unavailable { }
        try check(favorite.state.splitLayouts.first == fgroup, "Empty Favorite name does not clear through dialog")
        let restored = try favorite.saveSplitAppearance(current, icon: nil, reset: true)!
        try check(favorite.state.splitLayouts.first?.customTitle == nil, "Explicit reset clears Favorite name")
        try check(try favorite.applySplitAppearance(restored, undo: true), "Favorite reset Undo targets original shared container")
        let move = SidebarWindowMove(items: [.split(fgroup.id)], sourceSpaceID: active.id, profileID: profile,
            to: .init(spaceID: active.id, folderID: nil, section: .pinned), before: nil, state: favorite.state)!
        let moved = move.applying(to: favorite.state)!
        try check(moved.splitLayouts.first?.customIcon == fgroup.customIcon && moved.splitLayouts.first?.customTitle == fgroup.customTitle, "Whole Favorite move preserves customization")
        var retired = favorite.state; retired.tabs[0].archivedAt = Date()
        try check(SidebarSplitTitleEdit(group: fgroup, profileID: profile, state: retired) == nil, "Archived child refuses whole editor")

        // Actual native picker publication and dismissal, no browser/profile UI.
        //
        var commits: [SidebarGroupIcon?] = [], finished = 0
        let picker = SidebarGroupIconPicker(selected: nil); _ = picker.view
        picker.isCurrent = { true }; picker.onCommit = { commits.append($0) }; picker.onFinish = { finished += 1 }
        let pickerView = picker.pickerView!
        try check(pickerView.frame.size == NSSize(width: 272, height: 272) && pickerView.page == .emoji, "Tab/Space picker is 272 × 272 and opens on Emoji without an icon")
        try check(pickerView.segmentedControl?.label(forSegment: 0) == "Emoji" && pickerView.segmentedControl?.label(forSegment: 1) == "Icon", "Recovered segment order")
        try check(pickerView.removeButton.isHidden && !pickerView.canRemoveIcon, "Remove only appears with an icon")
        picker.choose(.emoji("not emoji")); try check(commits.isEmpty && !picker.finished, "Invalid native input retains edit")
        picker.choose(.emoji("🌍"))
        try check(commits == [.emoji("🌍")] && !picker.finished && picker.selected == .emoji("🌍"), "A choice commits once and keeps the picker open")
        try check(pickerView.canRemoveIcon && !pickerView.removeButton.isHidden && pickerView.emojiPage?.selectedEmoji == "🌍", "Committed emoji is marked and Remove appears")
        picker.choose(.emoji("🌍")); try check(commits.count == 1, "The same icon is not republished")
        pickerView.iconGrid.selectIcon(at: 9)
        try check(commits.last! == .icon(.shapes) && pickerView.iconGrid.selectedIcon == .shapes && pickerView.emojiPage?.selectedEmoji == nil, "Grid index publishes its catalog icon")
        pickerView.iconGrid.selectIcon(at: 9); pickerView.iconGrid.selectIcon(at: 56)
        try check(commits.count == 2, "Selected or out-of-range cells publish nothing")
        _ = pickerView.removeButton.accessibilityPerformPress()
        try check(commits.count == 3 && commits[2] == nil && !picker.finished && picker.selected == nil, "Remove publishes nil and keeps the picker")
        picker.cancel(); picker.cancel()
        try check(finished == 1 && picker.finished, "Dismissal finishes once")
        let cancelled = SidebarGroupIconPicker(selected: icon); cancelled.isCurrent = { true }; cancelled.onCommit = { commits.append($0) }; cancelled.cancel(); cancelled.choose(nil)
        try check(commits.count == 3, "Dismissal is not icon removal")
        let expired = SidebarGroupIconPicker(selected: icon); expired.isCurrent = { false }; expired.onCommit = { commits.append($0) }; expired.choose(nil)
        try check(commits.count == 3 && expired.finished, "Expired original owner refuses publication")
        let failed = SidebarGroupIconPicker(selected: target().group.customIcon); failed.isCurrent = { true }; _ = failed.view
        var failures = 0; failed.onFailure = { _ in failures += 1 }
        let failedTarget = target(), failedState = store.state
        let persistedBytes = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        failed.onCommit = { value in _ = try store.saveSplitAppearance(failedTarget, icon: value); commits.append(value) }
        failed.choose(nil)
        try check(!failed.finished && store.state == failedState && commits.count == 3 && failures == 1, "Actual failed persistence keeps picker and state for retry")
        try check(failed.selected == failedTarget.group.customIcon && failed.pickerView?.canRemoveIcon == true, "Failure leaves the original selection shown")
        try FileManager.default.removeItem(at: file); try persistedBytes.write(to: file)
        failed.choose(nil)
        try check(!failed.finished && commits.count == 4 && commits.last! == nil && target().group.customIcon == nil, "Explicit icon removal retries same owner and commits")
        failed.cancel()

        // Space creation's TextAndIconPicker hides the picker on every choice.
        var spaceCommits: [SidebarGroupIcon?] = [], spaceFinished = 0
        let spacePicker = SidebarGroupIconPicker(selected: .emoji("🌙")); _ = spacePicker.view
        spacePicker.closesAfterChoice = true; spacePicker.isCurrent = { true }
        spacePicker.onCommit = { spaceCommits.append($0) }; spacePicker.onFinish = { spaceFinished += 1 }
        spacePicker.pickerView!.iconGrid.selectIcon(at: 0)
        try check(spaceCommits == [.icon(.star)] && spacePicker.finished && spaceFinished == 1, "Space creation choice commits then closes")
        let spaceRemove = SidebarGroupIconPicker(selected: .emoji("🌙")); _ = spaceRemove.view
        spaceRemove.closesAfterChoice = true; spaceRemove.isCurrent = { true }; spaceRemove.onCommit = { spaceCommits.append($0) }
        _ = spaceRemove.pickerView!.removeButton.accessibilityPerformPress()
        try check(spaceCommits.count == 2 && spaceCommits[1] == nil && spaceRemove.finished, "Space creation Remove also closes")

        // The owner lease accepts a key window the picker owns (the skin-tone popover).
        let browserWindow = KeyTestWindow(), pickerWindow = KeyTestWindow(), toneWindow = KeyTestWindow()
        let owned = SidebarGroupIconPicker(selected: nil)
        pickerWindow.contentView = owned.view
        pickerWindow.addChildWindow(toneWindow, ordered: .above)
        try check(owned.presentationWindow === pickerWindow && !SplitCustomizationFocus.isHeld(window: browserWindow, presentation: owned.presentationWindow), "No key window: lease not held")
        pickerWindow.key = true
        try check(SplitCustomizationFocus.isHeld(window: browserWindow, presentation: owned.presentationWindow), "Key picker popover holds the lease")
        pickerWindow.key = false; toneWindow.key = true
        try check(owned.presentationWindow === toneWindow && SplitCustomizationFocus.isHeld(window: browserWindow, presentation: owned.presentationWindow), "Key skin-tone child window holds the lease")
        let looseTone = KeyTestWindow(); looseTone.key = true; toneWindow.key = false
        try check(SidebarGroupIconPicker.ownedKeyWindow(of: pickerWindow, extra: looseTone) === looseTone && SidebarGroupIconPicker.ownedKeyWindow(of: pickerWindow, extra: nil) == nil, "The tone popover window counts even unparented")
        pickerWindow.removeChildWindow(toneWindow); pickerWindow.contentView = nil

        // Closing breaks popover → controller, so the picker and its pages deinit.
        weak var leakedPicker: SidebarGroupIconPicker?, leakedView: NSView?, leakedGrid: NSCollectionView?
        autoreleasepool {
            let transient = SidebarGroupIconPicker(selected: nil); _ = transient.view
            transient.isCurrent = { true }; transient.configurePopover()
            transient.pickerView?.emojiPage?.submit("pizza")
            leakedPicker = transient; leakedView = transient.view; leakedGrid = transient.pickerView?.emojiPage?.collectionView
            transient.cancel()
        }
        try check(leakedPicker == nil && leakedView == nil && leakedGrid == nil, "A closed picker releases its controller, view and emoji grid")

        //
        try check(SidebarIconType.allCases.count == 61 && SidebarIconType.allCases.first == .star && SidebarIconType.allCases.last == .search, "All 61 SidebarIconType cases in order")
        try check(SidebarIconType.tabAndSpacePicker.count == 56 && SidebarIconType.tabAndSpacePicker.last == .train, "Tab/Space catalog stops at train")
        try check(SidebarIconType.folderPicker.count == 24 && SidebarIconType.folderPicker[8] == .chatBubbleEllipses && SidebarIconType.folderPicker.last == .skull, "Folder catalog order")
        try check(SidebarIconType(rawValue: "colorPallete") == .colorPallete && SidebarIconType.fileTrayFull.rawValue == "fileTrayFull", "Raw values are the case names")
        let ionicons = SidebarIconCatalog.font(.ionicons, size: 14)
        try check(ionicons.fontName == "ionicons" && SidebarIconCatalog.font(.icomoon, size: 14).fontName == "icomoon", "Copied Parc icon fonts load")
        let fontURL = CTFontCopyAttribute(ionicons as CTFont, kCTFontURLAttribute) as? URL
        try check(fontURL?.standardizedFileURL == SidebarIconCatalog.resourceDirectory?.appendingPathComponent("ionicons.ttf").standardizedFileURL, "Icon font comes from the bundled file, not a name lookup")
        for type in SidebarIconType.allCases {
            if let code = SidebarIconCatalog.glyph(type) {
                var units = Array(String(Character(Unicode.Scalar(code)!)).utf16), glyphs = [CGGlyph](repeating: 0, count: units.count)
                try check(CTFontGetGlyphsForCharacters(ionicons as CTFont, &units, &glyphs, units.count), "\(type) glyph exists in ionicons")
                try check(SidebarIconCatalog.image(for: type, size: 14).isTemplate, "\(type) renders as a template glyph")
            } else {
                try check([.linear, .figma].contains(type) && SidebarIconCatalog.image(for: type, size: 16).size == NSSize(width: 16, height: 16), "\(type) is a copied image asset")
            }
        }
        try check(SidebarIconCatalog.glyph(.star) == 0xF53B && SidebarIconCatalog.glyph(.bag) == 0xF166 && SidebarIconCatalog.glyph(.ellipse) == 0xF29E, "Recovered glyph mapping")
        let encodedIcon = try JSONEncoder().encode(SidebarGroupIcon.icon(.chatBubbleEllipses))
        try check(try JSONDecoder().decode(SidebarGroupIcon.self, from: encodedIcon) == .icon(.chatBubbleEllipses), "Catalog icons round-trip")
        var unknown = try JSONSerialization.jsonObject(with: JSONEncoder().encode(target().group)) as! [String: Any]
        unknown["customIcon"] = ["icon": ["_0": "notAnArcIcon"]]
        let tolerant = try JSONDecoder().decode(BrowserSplitLayout.self, from: JSONSerialization.data(withJSONObject: unknown))
        try check(tolerant.customIcon == nil && tolerant.id == target().group.id, "An unknown stored icon decodes as absent")
        try check(SidebarIconPickerMetrics.size(.folderPicker) == NSSize(width: 272, height: 144), "Folder picker host is 272 × 144")

        let iconPicker = SidebarGroupIconPicker(selected: .icon(.star)); _ = iconPicker.view
        let grid = iconPicker.pickerView!.iconGrid
        try check(iconPicker.pickerView!.page == .icon && grid.items.count == 56 && grid.fittingSize == NSSize(width: 247, height: 216), "Icon selection opens Icon on a 8 × 7 grid")
        try check(grid.itemFrame(at: 9) == NSRect(x: 31, y: 31, width: 30, height: 30), "Cells are 30 points, one apart")
        try check(iconPicker.pickerView!.gridFrame.minX == 12.5, "Grid centers in the 264-point page")
        let star = grid.items[0], heart = grid.items[2]
        star.appearance = NSAppearance(named: .aqua); heart.appearance = NSAppearance(named: .aqua)
        try check(star.isSelectedIcon && star.accessibilityLabel() == "star" && star.isAccessibilitySelected(), "Selected item and raw-name label")
        try check(star.backgroundColor == SidebarIconCatalog.brandGray.withAlphaComponent(0.25) && heart.backgroundColor == .clear, "Selected light background is BrandGray at 0.25")
        heart.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!); try check(heart.backgroundColor == SidebarIconCatalog.brandGray.withAlphaComponent(0.1), "Hover background is 0.1")
        heart.appearance = NSAppearance(named: .darkAqua); try check(heart.glyphColor == .white, "Dark glyphs are white")
        heart.setPressed(true); try check(heart.glyphView.layer?.opacity == 0.75, "Pressing dims the glyph content")
        heart.setPressed(false); try check(heart.glyphView.layer?.opacity == 1, "Release restores the glyph content")
        let symbolPicker = SidebarGroupIconPicker(selected: .symbol("star")); _ = symbolPicker.view
        try check(symbolPicker.pickerView!.page == .icon && symbolPicker.pickerView!.iconGrid.selectedIcon == nil, "A stored symbol opens Icon unselected")
        let folder = SidebarGroupIconPicker(selected: nil, iconSet: .folderPicker); _ = folder.view
        try check(folder.pickerView!.page == .icon && folder.pickerView!.heading?.stringValue == "Icon" && folder.pickerView!.emojiPage == nil && folder.pickerView!.iconGrid.items.count == 24, "Folder picker is icons only")

        //
        let emoji = SidebarEmojiModel.shared
        try check(emoji.emojis.count > 1800 && emoji.emojis.first?.emoji == "😀", "Bundled emoji list loads in category order")
        let starts = emoji.categoryStarts.compactMap { $0 }
        try check(starts.count == 8 && starts == starts.sorted(), "Eight categories in case order")
        try check(emoji.emojis[starts[4]].category == 4 && emoji.emojis[starts[3]].category == 3 && emoji.emojis[starts[7]].emoji.unicodeScalars.first!.value >= 0x1F3C1, "Activities precede Travel; flags last")
        try check(emoji.filtered("grinning").emojis.first?.emoji == "😀" && emoji.filtered("GRIN face").emojis.contains { $0.emoji == "😀" }, "Case-insensitive regex filter with spaces as wildcards")
        try check(emoji.filtered("(").emojis.isEmpty && emoji.filtered("😀").emojis.contains { $0.emoji == "😀" }, "Unescaped invalid pattern matches only by emoji")
        try check(SidebarEmojiModel.applying("\u{1F3FD}", to: "👋") == "👋🏽" && SidebarEmojiModel.applying("\u{1F3FD}", to: "🧑‍💻") == "🧑🏽‍💻", "Modifier follows the first scalar")
        try check(SidebarEmojiModel.applying("\u{1F3FB}", to: "👋🏽") == "👋🏻" && SidebarEmojiModel.variants(of: "👋").count == 6, "A tone replaces the old one; base plus five")
        try check(emoji.index(containing: "👋🏽") == emoji.emojis.firstIndex { $0.emoji == "👋" }, "A toned choice marks its base cell")
        let page = SidebarEmojiPickerView(selectedEmoji: nil)
        try check(page.searchField.placeholderString == nil && page.categoryBar.arrangedSubviews.count == 8, "No placeholder before typing; eight category buttons")
        page.searchField.stringValue = "pizza"; page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        try check(page.searchField.placeholderString == nil && page.model.emojis.count == emoji.emojis.count, "Search waits for its debounce")
        page.applyQuery(); try check(page.model.emojis.contains { $0.emoji == "🍕" } && page.model.emojis.count < 20, "Debounced query filters the grid")
        page.searchField.stringValue = ""; page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification)); page.applyQuery()
        try check(page.searchField.placeholderString == "Search" && page.model.emojis.count == emoji.emojis.count, "Emptied search shows Search and every emoji")
        var picked: [String] = []; page.onEmojiSelected = { picked.append($0) }
        let pizza = emoji.emojis.firstIndex { $0.emoji == "🍕" }!
        page.collectionView(page.collectionView, didSelectItemsAt: [IndexPath(item: pizza, section: 0)])
        try check(picked == ["🍕"] && page.selectedEmoji == "🍕" && page.skinTonePopover == nil, "A toneless emoji selects at once")
        let size = page.collectionView(page.collectionView, layout: page.collectionView.collectionViewLayout!, sizeForItemAt: IndexPath(item: 0, section: 0))
        try check(size == NSSize(width: 28, height: 28), "Emoji cells are 28 points")

        let row = SidebarSplitTitleView(title: "Original", count: 2)
        // What the row shows: its icon image view, or the rounded count icon's label.
        let iconView = row.subviews.compactMap { $0 as? NSImageView }.first!
        let countIcon = row.subviews.first { !($0 is NSTextField) && !($0 is NSImageView) && $0.layer?.cornerRadius == 4 }!
        func shownCount() -> String? { countIcon.isHidden ? nil : countIcon.subviews.compactMap { $0 as? NSTextField }.first?.stringValue }
        func shownImage() -> NSImage? { iconView.isHidden ? nil : iconView.image }
        func pixels(_ image: NSImage?) -> Data? {
            guard let image, let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.bitmapData.map { Data(bytes: $0, count: bitmap.bytesPerRow * bitmap.pixelsHigh) }
        }
        row.setIcon(.symbol("star"))
        try check(shownImage()?.isTemplate == true && pixels(shownImage()) == pixels(NSImage(systemSymbolName: "star", accessibilityDescription: nil))
                  && shownCount() == nil, "Native custom-info row displays genuine symbol")
        row.setIcon(.emoji("🧭"))
        let compass = pixels(SidebarGroupIcon.emoji("🧭").image(size: 16))
        try check(compass != nil && pixels(shownImage()) == compass && compass != pixels(SidebarGroupIcon.emoji("🍕").image(size: 16))
                  && shownCount() == nil
                  && shownImage()?.size == NSSize(width: 16, height: 16) && shownImage()?.isTemplate == false
                  && !row.subviews.contains { ($0 as? NSTextField)?.stringValue == "🧭" }, "Emoji drawn as an untinted 16-point image")
        row.setIcon(nil); try check(shownCount() == "2" && shownImage() == nil, "Explicit icon reset restores original count in reused native row")
        // SplitViewCellCustomInfoView geometry and colors (SP30).
        row.frame = NSRect(x: 0, y: 0, width: 212, height: 36); row.titleTrailing = 164; row.layoutSubtreeIfNeeded()
        let title = row.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Original" }!
        // The custom info stack places its title by its alignment rect, so the
        // label extends its 2-point text inset past the 36-point title inset
        // and the trailing edge.
        try check(title.frame.minX == SidebarSplitCellLayout.infoTitleInset - SidebarRowAppearance.titleTextPadding
                  && SidebarSplitCellLayout.infoTitleInset == 36 && title.frame.maxX == 164 + SidebarRowAppearance.titleTextPadding
                  && title.font?.pointSize == 14
                  && title.font?.fontDescriptor.symbolicTraits.contains(.bold) == false, "Custom title drawn from 36, 14-point regular, before Close")
        try check(row.subviews.compactMap { $0 as? SidebarTitleField }.first?.frame == title.frame, "Renaming edits in the title's frame")
        let box = row.subviews.first { !($0 is NSTextField) && !($0 is NSImageView) && $0.layer?.cornerRadius == 4 }!
        try check(box.frame == NSRect(x: 10, y: 10, width: 16, height: 16), "Count icon 16 points centered in the 24-point slot 6 points in")
        let countLabel = box.subviews.compactMap { $0 as? NSTextField }.first!
        try check(countLabel.font?.pointSize == 10 && countLabel.font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "Count label bold 10")
        row.applyColors(title: .systemPurple, secondary: .systemOrange, countText: .white, countBackground: .black, dark: true)
        try check(countLabel.textColor == .white && box.layer?.backgroundColor?.alpha == 0.8, "Count maxContrast on cutout at 0.8")
        row.titleTrailing = nil; row.layoutSubtreeIfNeeded()
        try check(title.frame.maxX == 202 + SidebarRowAppearance.titleTextPadding, "Without Close the title's text ends 10 inside")
        let unnamed = SidebarSplitTitleView(title: SidebarSplitCellLayout.defaultTitle(count: 3), count: 3, named: false)
        try check(unnamed.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "3 Tabs" }
                  && unnamed.accessibilityLabel() == "Split View, 3 tabs" && unnamed.toolTip == nil && unnamed.parcTooltip == nil,
                  "Icon-only split shows the default title; AX names the split; no tooltip")
        try check(row.parcTooltip == TooltipConfiguration("Original", behavior: .onMouseIdle(delay: 0.01)) && row.toolTip == nil,
                  "A named split's title is its Parc tooltip, after 0.01 s")
        row.setIcon(.icon(.star)); row.layoutSubtreeIfNeeded()
        try check(pixels(shownImage()) == pixels(SidebarGroupIcon.icon(.star).image(size: 16)) && shownCount() == nil
                  && shownImage()?.isTemplate == true && shownImage()?.size == NSSize(width: 16, height: 16), "Catalog icon is a 16-point template glyph")
        try check(row.iconContainerFrame == NSRect(x: SidebarSplitCellLayout.infoLeadingInset, y: 6, width: 24, height: 24), "The 24-point slot anchors the picker")

        // The actual native Undo owner carries both operation types without
        // replacing later pane geometry or independently edited name fields.
        let undo = FolderUndoManager(); var available = true, errors = 0
        let nativeChange = try store.saveSplitAppearance(target(), icon: .symbol("heart"))!
        try check(undo.appendSplitAppearance(nativeChange, store: store, available: { available }, onError: { _ in errors += 1 }), "Committed icon registers actual native Undo")
        try check(undo.undoMenuItemTitle == "Undo Customize Tab", "Native icon Undo menu label")
        available = false; try check(!undo.canUndo, "Window interruption disables original Undo")
        available = true; undo.undo()
        try check(target().group.customIcon == nil && undo.redoMenuItemTitle == "Redo Customize Tab", "Native Undo removes only original icon")
        undo.redo(); try check(target().group.customIcon == .symbol("heart"), "Native Redo restores original icon")
        let nativeReset = try store.saveSplitAppearance(target(), icon: nil, reset: true)!
        try check(undo.appendSplitAppearance(nativeReset, store: store, available: { available }, onError: { _ in errors += 1 }), "Committed reset joins same native chronology")
        try check(undo.undoMenuItemTitle == "Undo Reset Name and Icon", "Native reset menu label")
        undo.undo(); try check(target().group.customIcon == .symbol("heart") && target().group.customTitle == "Other", "Native reset inverse restores both original fields")
        undo.undo(); try check(target().group.customIcon == nil && target().group.customTitle == "Other", "Earlier icon inverse follows reset without flattening title")
        undo.redo(); undo.redo()
        try check(target().group.customIcon == nil && target().group.customTitle == nil && errors == 0, "Native redo completes same reset chronology")
        print("\(count) Split appearance assertions passed")
    }
}
