import AppKit

@main @MainActor struct PinnedHeaderTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }

    static func main() throws {
        typealias L = SidebarPinnedHeaderLayout
        let digit: (Int, Bool) -> CGFloat = { value, chips in CGFloat(String(value).count + (chips ? 1 : 0)) * 6 }
        check(L.height == SidebarChromeLayout.pinnedSectionHeaderHeight && SidebarChromeLayout.TablistSlot.pinnedSectionHeader.row == .accessory(height: 26),
              "the header is a small 26-point accessory row")
        check(SidebarChromeLayout.tablistSlots(pinnedItems: 1, todayItems: 0, isPrivate: false, sectionHeader: true)
              == [.pinnedSectionHeader, .pinnedItem, .newTab], "a Space with pinned items leads with the header")
        check(SidebarChromeLayout.tablistSlots(pinnedItems: 0, todayItems: 1, isPrivate: false, sectionHeader: true)
              == [.pinnedSectionHeader, .sectionDivider, .newTab, .todayItem], "a folded Pinned keeps the header above the divider")
        check(SidebarChromeLayout.tablistSlots(pinnedItems: 0, todayItems: 0, isPrivate: true, sectionHeader: true) == [.privateHeading, .newTab],
              "private windows never get a Pinned header")
        let chevron = L.chevronFrame(width: 212)
        check(chevron.midX == 212 - SidebarRowAppearance.closeTrailingInset - SidebarRowAppearance.closeSize / 2 && chevron.midY == 13,
              "the chevron sits in the rows' close-button column, centred")

        let wide = L.summary(width: 212, labelWidth: 36, icons: 4, count: 6, showsIcons: true, countWidth: digit)
        check(wide.chips.count == 4 && wide.hidden == 2 && wide.pill == nil, "a roomy header shows four icons and the rest as a count")
        check(wide.chips.first?.minX == L.labelInset + 36 + L.summarySpacing, "the stack starts a fixed gap after the label")
        check(zip(wide.chips, wide.chips.dropFirst()).allSatisfy { $1.minX - $0.minX == L.chipPitch && $1.minX < $0.maxX },
              "icons overlap at an even pitch")
        check(wide.chips.allSatisfy { $0.midY == 13 && $0.width == L.chipSide }, "icons are centred on the label line")
        check(wide.countX == wide.chips[3].maxX + L.countSpacing, "the count follows the last icon")
        check(wide.countX! + digit(2, true) <= chevron.minX - L.chevronClearance, "the summary never runs into the chevron")

        let narrow = L.summary(width: 148, labelWidth: 36, icons: 4, count: 120, showsIcons: true, countWidth: digit)
        let narrowEnd = (narrow.countX ?? narrow.chips.last?.maxX ?? 0) + (narrow.hidden > 0 ? digit(narrow.hidden, true) : 0)
        check(!narrow.chips.isEmpty && narrow.chips.count < 4 && narrowEnd <= L.chevronFrame(width: 148).minX - L.chevronClearance,
              "a narrow sidebar drops icons into the count instead of colliding")
        check(narrow.hidden == 120 - narrow.chips.count, "dropped icons are counted")
        let few = L.summary(width: 212, labelWidth: 36, icons: 3, count: 3, showsIcons: true, countWidth: digit)
        check(few.chips.count == 3 && few.hidden == 0 && few.countX == nil, "three pinned tabs show three icons and no count")
        let capped = L.summary(width: 600, labelWidth: 36, icons: 4, count: 40, showsIcons: true, countWidth: digit)
        check(capped.chips.count == 4, "even a very wide sidebar shows no more than the icons it was given")
        let pill = L.summary(width: 212, labelWidth: 36, icons: 4, count: 6, showsIcons: false, countWidth: digit)
        check(pill.chips.isEmpty && pill.pill != nil && pill.pill!.width >= pill.pill!.height, "icons off: a count pill and no icons")
        check(pill.pill!.width == max(L.pillHeight, digit(6, false) + L.pillPadding * 2), "the pill is measured for the bare count it draws")
        check(pill.pill?.minX == L.labelInset + 36 + L.summarySpacing && pill.pill?.midY == 13, "the pill sits where the icons would")
        check(L.summary(width: 212, labelWidth: 36, icons: 4, count: 6, showsIcons: true, countWidth: digit).pill == nil, "icons on: no pill")
        check(L.summary(width: 212, labelWidth: 36, icons: 0, count: 2, showsIcons: true, countWidth: digit).pill != nil,
              "with no icon to show, the pill keeps the count visible")
        check(L.summary(width: 212, labelWidth: 36, icons: 0, count: 0, showsIcons: true, countWidth: digit) == .init(chips: [], hidden: 0, countX: nil, pill: nil),
              "nothing pinned, nothing summarised")
        check(L.summary(width: 70, labelWidth: 36, icons: 4, count: 6, showsIcons: true, countWidth: digit).chips.isEmpty,
              "a sliver of room shows only the label")
        check(L.countText(3, chips: true) == "+3" && L.countText(3, chips: false) == "3", "icons say +N, the pill says N")
        check(L.accessibilityLabel(collapsed: true, count: 1) == "Pinned, 1 tab" && L.accessibilityLabel(collapsed: true, count: 6) == "Pinned, 6 tabs"
              && L.accessibilityLabel(collapsed: false, count: 6) == "Pinned", "VoiceOver hears the count only while folded")
        check(L.actionTitle(collapsed: false) == "Collapse Pinned" && L.actionTitle(collapsed: true) == "Expand Pinned",
              "the command reads as the action it will take")
        check(L.iconsActionTitle(shows: true) == "Hide Collapsed Pinned Icons" && L.iconsActionTitle(shows: false) == "Show Collapsed Pinned Icons",
              "the icon command reads as the action it will take")
        check(L.chevronAngle(collapsed: false) == 0 && L.chevronAngle(collapsed: true) == -.pi / 2, "the chevron turns a quarter when folding")
        let open = L.chevronPoints(in: chevron, angle: L.chevronAngle(collapsed: false))
        check(open.count == 3 && open[1].y > open[0].y && abs(open[0].y - open[2].y) < 0.001 && abs(open[1].x - chevron.midX) < 0.001,
              "the open chevron points down in the header's flipped coordinates")
        let shut = L.chevronPoints(in: chevron, angle: L.chevronAngle(collapsed: true))
        check(shut[1].x > shut[0].x && abs(shut[0].x - shut[2].x) < 0.001 && abs(shut[1].y - chevron.midY) < 0.001,
              "the folded chevron points to the trailing edge")
        check(L.chevronDuration == 0.2, "the chevron turns over 0.2 seconds")

        let header = SidebarPinnedHeaderView(frame: NSRect(x: 0, y: 0, width: 212, height: 26))
        var toggles = 0
        check(header.accessibilityRole() == .disclosureTriangle && header.isAccessibilityElement(), "the header is a disclosure control")
        check(!header.isAccessibilitySelectorAllowed(#selector(NSView.accessibilityPerformPress)), "no press without an owner")
        header.toggle = { toggles += 1 }
        check(header.accessibilityPerformPress() && toggles == 1, "VoiceOver's press folds or unfolds")
        check(header.isAccessibilitySelectorAllowed(#selector(NSView.accessibilityPerformPress)), "press is offered once wired")
        check((header.accessibilityValue() as? Int) == 1 && header.accessibilityLabel() == "Pinned", "an open section reads as expanded")
        let first = UUID(), second = UUID(), hidden = UUID()
        header.update(.init(collapsed: true, showsIcons: true, count: 6, icons: [first, second]), fallbacks: [:], animated: false)
        check((header.accessibilityValue() as? Int) == 0 && header.accessibilityLabel() == "Pinned, 6 tabs", "a folded section reads as collapsed with its count")
        check(header.shows(first) && !header.shows(hidden), "the header knows which tabs it shows")
        header.setFavicon(NSImage(size: NSSize(width: 16, height: 16)), for: hidden, url: "https://hidden.invalid")
        check(header.needsFavicon(for: hidden, url: "https://hidden.invalid"), "a favicon for a tab it doesn't show is dropped")
        let icon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in NSColor.systemRed.setFill(); rect.fill(); return true }
        header.setFavicon(icon, for: first, url: "https://first.invalid")
        check(!header.needsFavicon(for: first, url: "https://first.invalid"), "a loaded favicon isn't fetched again")
        check(header.needsFavicon(for: first, url: "https://first.invalid/moved"), "a navigated tab refetches its favicon")
        header.forgetFavicon(for: first)
        check(header.needsFavicon(for: first, url: "https://first.invalid"), "a changed favicon is fetched again")
        header.setFavicon(icon, for: first, url: "https://first.invalid")
        header.update(.init(collapsed: true, showsIcons: true, count: 6, icons: [second]), fallbacks: [:], animated: false)
        check(header.needsFavicon(for: first, url: "https://first.invalid"), "favicons for tabs that left the stack are released")

        header.update(.init(collapsed: true, showsIcons: true, count: 6, icons: [first, second]), fallbacks: [:], animated: false)
        header.applyStyle(dark: false, accent: nil)
        header.layoutSubtreeIfNeeded()
        let summary = header.summary!
        let bitmap = header.bitmapImageRepForCachingDisplay(in: header.bounds)!
        header.cacheDisplay(in: header.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / header.bounds.width
        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? 0
        }
        let chip0 = summary.chips[0], chip1 = summary.chips[1]
        check(alpha(chip0.minX + 1.5, chip0.midY) > 0.8, "the first icon's tile is painted")
        check(alpha(chip1.minX - L.chipRing / 2, chip0.midY) < 0.05, "the next icon cuts a clean ring out of the one beneath")
        check(alpha(chip1.midX, chip1.midY) > 0.8, "the overlapping icon is whole")
        check(alpha(summary.countX! + 20, 2) < 0.05, "the header is clear outside its content")
        header.update(.init(collapsed: true, showsIcons: false, count: 6, icons: []), fallbacks: [:], animated: false)
        check(header.summary?.chips.isEmpty == true && header.summary?.pill != nil, "turning icons off swaps the stack for the pill")

        let defaults = UserDefaults(suiteName: "parc.pinned.tests." + UUID().uuidString)!
        let preferences = PinnedSectionPreferences(defaults: defaults)
        check(preferences.state.showsCollapsedIcons && !preferences.loadError, "icons show by default")
        try preferences.setShowsCollapsedIcons(false)
        check(!PinnedSectionPreferences(defaults: defaults).state.showsCollapsedIcons, "turning icons off is remembered")
        defaults.set("garbage", forKey: "parc.pinnedSection.v1")
        let broken = PinnedSectionPreferences(defaults: defaults)
        check(broken.loadError && broken.state.showsCollapsedIcons, "an unreadable preference falls back to icons without overwriting")
        var refused = false
        do { try broken.setShowsCollapsedIcons(false) } catch { refused = true }
        check(refused && defaults.string(forKey: "parc.pinnedSection.v1") == "garbage", "an unreadable preference is never clobbered")
        let card = SidebarPinnedHeaderView(frame: NSRect(x: 0, y: 0, width: 212, height: 26))
        card.update(.init(placeholder: true), fallbacks: [:], animated: false)
        check(card.accessibilityRole() == .staticText && card.accessibilityLabel() == "Pinned" && card.accessibilityValue() == nil
              && (card.accessibilityHelp() ?? "").isEmpty && card.toolTip == nil,
              "an empty Library card's header is a plain Pinned label")
        check(card.hitTest(NSPoint(x: 20, y: 13)) == nil && !card.accessibilityPerformPress() && card.summary == nil,
              "the empty card's label leaves clicks to the card and folds nothing")
        print("Pinned header checks passed: \(count)")
    }
}
