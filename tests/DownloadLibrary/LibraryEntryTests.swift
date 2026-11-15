import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class ManualClock {
    private(set) var now: TimeInterval = 0
    private var pending: [(at: TimeInterval, order: Int, body: @MainActor () -> Void)] = []
    private var order = 0
    var count: Int { pending.count }
    func schedule(_ delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        order += 1; pending.append((now + delay, order, body))
    }
    func advance(_ interval: TimeInterval) {
        let target = now + interval
        while let next = pending.filter({ $0.at <= target + 1e-9 }).min(by: { ($0.at, $0.order) < ($1.at, $1.order) }) {
            pending.removeAll { $0.order == next.order }
            now = next.at; next.body()
        }
        now = target
    }
}

@main @MainActor struct LibraryEntryChecks {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { count += 1; precondition(value(), message) }
    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }
    static func near(_ a: NSRect, _ b: NSRect, _ tolerance: CGFloat = 0.01) -> Bool {
        near(a.minX, b.minX, tolerance) && near(a.minY, b.minY, tolerance) && near(a.width, b.width, tolerance) && near(a.height, b.height, tolerance)
    }
    static func event(_ type: NSEvent.EventType, _ point: NSPoint, in view: NSView, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: flags, timestamp: 0,
                           windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    static func settle(_ seconds: TimeInterval = 0.05) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    static var preferenceSuites: [String] = []
    static func freshPreferences() -> LibraryEntryPreferences {
        let suite = "parc.library-entry-checks.\(preferenceSuites.count)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        preferenceSuites.append(suite)
        return LibraryEntryPreferences(defaults: defaults)
    }
    struct CellMotion {
        let samples: [(time: TimeInterval, y: CGFloat, progress: CGFloat)]
        let start: TimeInterval
        func progress(at time: TimeInterval) -> CGFloat { samples.last { $0.time <= start + time }?.progress ?? 0 }
        var peak: CGFloat { samples.map(\.progress).max() ?? 0 }
        func rests(after time: TimeInterval) -> Bool {
            let late = samples.filter { $0.time >= start + time }
            return !late.isEmpty && late.allSatisfy { abs($0.progress - 1) < 0.02 }
        }
        var still: Bool { samples.allSatisfy { abs($0.y - samples[0].y) < 0.01 } }
        var trace: [(Double, Double)] { samples.map { (Double($0.time - start), Double($0.progress)) } }
    }
    static func cellMotion(_ entry: SidebarLibraryEntry, travel: CGFloat, for seconds: TimeInterval) -> CellMotion {
        func y() -> CGFloat { entry.badge.convert(entry.badge.bounds, to: entry).midY }
        let clock = CACurrentMediaTime()
        var raw: [(TimeInterval, CGFloat)] = [(0, y())]
        repeat {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.004))
            raw.append((CACurrentMediaTime() - clock, y()))
        } while CACurrentMediaTime() - clock < seconds
        let from = raw.last!.1 - travel
        let start = raw.first { abs($0.1 - raw[0].1) > 0.01 }?.0 ?? 0
        return CellMotion(samples: raw.map { ($0.0, $0.1, travel == 0 ? 1 : ($0.1 - from) / travel) }, start: start)
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        SystemOverrides.install()
        defer { for suite in preferenceSuites { UserDefaults.standard.removePersistentDomain(forName: suite) } }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../..").standardizedFileURL
        let resources = repository.appendingPathComponent("Resources/Library", isDirectory: true)
        expect(LibraryArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("Library", isDirectory: true)
               && LibraryArtwork.boxOfThings("box") != nil, "the artwork loads from the bundle's Library resources")

        let files = try FileManager.default.contentsOfDirectory(atPath: resources.path).filter { $0 != "README.md" }.sorted()
        let originalArtwork = Set(["box", "circle", "glow", "star", "triangle"].flatMap { ["\($0).pdf", "\($0).png", "\($0)@2x.png"] }
            + ["EmptyFavicon.svg", "EmptyFavicon.png", "EmptyFavicon@2x.png"])
        let documentArtwork = Set(["easel", "easel-dark", "note", "note-dark"].flatMap { ["\($0).png", "\($0)@2x.png"] })
        let railArtwork = Set(["screenshots", "downloads", "easels", "spaces", "archive"].map { "\($0).json" })
        expect(Set(files) == originalArtwork.union(documentArtwork).union(railArtwork), "Original entry, Easels & Notes and rail artwork inventory: \(files)")
        let recordedDigests = [
            "EmptyFavicon.png": "9f8c215d6a4cd681212f199b6ced7a474b96142da70b135a4742ad4e6058ea59",
            "EmptyFavicon.svg": "a8c3c907ce1edf91505144b35a5c72e9e221bf7ad26fc99e57f6049bf21a5b6d",
            "EmptyFavicon@2x.png": "975803fa39539559a47f403ebb2ea12dec3a5efd35cd7dc0eab86df517a547f2",
            "archive.json": "7a86a61e837ed660b05c1cda3293d95e86dc15adb54f48cc99d97f41dabfd0c3",
            "box.pdf": "2e346cef04224535cc627b12f24e73c3fc3b7f0c5ef561961c54b7e0938f1a32",
            "box.png": "8cf280b20c879d3ab59bfa2f6d67a8be6887bc1acb7da1bdffbe97b85df51608",
            "box@2x.png": "ce6a1b382dd108e7b217c796618510f1736784948bb4ecaa4b894e9604eef33a",
            "circle.pdf": "ff75dc7e559d7c2854968139f7f53aa002bdf7a16b6d940bb8a93618411ea2f7",
            "circle.png": "0de741cd1cef116ff56f62bb54adf75be3b1d1a347b07a91f2f91f31a415430f",
            "circle@2x.png": "9f68d2791c4b0219dbaf4dcfbbf24fbc155be5fc501b77e6d7e46560f7ddc7e7",
            "downloads.json": "68ba524419f02ec0345fa0c235c3f77967a831752cc9f03845bb1ead9676fdb2",
            "easel-dark.png": "442dfc837df6c362e85bd6fb0a8274e38be65f621fa05712a3425c5944d2bf33",
            "easel-dark@2x.png": "eab14c70fdfc2fc7a216f21ebaf5deab0d01ac186d3ad910cb9c7a9aef8f0391",
            "easel.png": "3fab1cfcb190d836c2e166b28ff803974d16aba67c3ad738d86f3c6942e09e6f",
            "easel@2x.png": "dca7f41cfc59ceeef0b86c91195dea9c298b328f53723ce3af23b87b79bd93a4",
            "easels.json": "3cac7075f636622882a1b902468509b5f242c17c0ef487c04f6c3df693488927",
            "glow.pdf": "a7b29010dbbb02daae2cd71b5edb1e852d949a892f609e0c3e2123945ca146f2",
            "glow.png": "df88cb4f80747ba859f04df0ba0c9fd6ef60de7461ecb6a03a0ef9554eacc67a",
            "glow@2x.png": "66af6fcc44de3b0d8c63dae972b698018b94c88faf298f68abbaced7bd72c2a4",
            "note-dark.png": "71547ee102f9d7076a394c1badd65707875ae2580739bb87e96dd8b545db83a1",
            "note-dark@2x.png": "b1cef5ce4aec49141d9ba46fbbb7936da1ba91a048206993e0144f6e905a4809",
            "note.png": "d9d9ece1bf83c2f2d618ee0a2421c95ac04cad5b2ce560e8723ff5b067f38603",
            "note@2x.png": "af8ad6f2d6fd2d4e6f570965f519ff1246310f58676be3223e1a8d30fac70a89",
            "screenshots.json": "ad085ab39b4d236064adc92ab5d050b2a3fdbfb05278f7115a8102b3960f85d7",
            "spaces.json": "44c81bbcb9df94bb0506a5c9d77ee5b53e124eeb80aacf6dba0205a71e1928bb",
            "star.pdf": "9d155e0d1bd5215436842dc3523350621c970a352c224ee4236a85c6ce222a59",
            "star.png": "8ec11168b78904b3fc15f1e7b730702a3283c74d606fb3d78e9f18bed3b78715",
            "star@2x.png": "c87a25aaa7097129bbed1b167a4225972ff4d7e54bf7caa5d0c1cb6fb384bb09",
            "triangle.pdf": "b9de9f417b49cf911cb40bda3fc0db903fe8f4d0cda282aba7fdb0f35ca2d893",
            "triangle.png": "db7689b3a019d6fa93aa2e0a450dc1ee2b4ad55230950a34357a44ef192d9ea3",
            "triangle@2x.png": "eefeff24657fc9edb6fe9a99be7c20d62e6e17cdcd25f0e22295524619dcfeef"
        ]
        expect(Set(recordedDigests.keys) == Set(files), "Every bundled artwork file has a recorded digest")
        for file in files {
            let digest = SHA256.hash(data: try Data(contentsOf: resources.appendingPathComponent(file))).map { String(format: "%02x", $0) }.joined()
            expect(recordedDigests[file] == digest, "\(file) is byte for byte the artwork Parc recorded")
        }
        let sizes: [String: NSSize] = ["glow": NSSize(width: 81, height: 27), "star": NSSize(width: 9, height: 9),
                                       "triangle": NSSize(width: 4, height: 3), "circle": NSSize(width: 2, height: 2),
                                       "box": NSSize(width: 12, height: 9)]
        for (name, size) in sizes {
            let image = LibraryArtwork.boxOfThings(name)!
            expect(image.size == size && image.isTemplate, "\(name) is a \(size) template")
            expect(image.representations.contains { $0 is NSPDFImageRep }
                   && image.representations.compactMap { $0 as? NSBitmapImageRep }.count == 2, "\(name) keeps its PDF and both bitmaps")
        }
        expect(LibraryArtwork.emptyFavicon?.size == NSSize(width: 14, height: 14), "EmptyFavicon is the 14-point asset")

        let light = TranslucentButtonColors.standard(dark: false), dark = TranslucentButtonColors.standard(dark: true)
        func rgba(_ color: NSColor) -> [CGFloat] { let c = color.usingColorSpace(.sRGB)!; return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent] }
        expect(rgba(light.hoveredBackground) == [0, 0, 0, 0.071] && rgba(light.pressedBackground) == [0, 0, 0, 0.090]
               && rgba(light.foreground) == [0, 0, 0, 0.565] && rgba(light.pressedForeground) == [0, 0, 0, 0.910]
               && rgba(light.disabledForeground) == [0, 0, 0, 0.220], "Aqua GrayA4/5/11/12/8")
        expect(rgba(dark.hoveredBackground) == [1, 1, 1, 0.077] && rgba(dark.pressedBackground) == [1, 1, 1, 0.103]
               && rgba(dark.foreground) == [1, 1, 1, 0.592] && rgba(dark.pressedForeground) == [1, 1, 1, 0.923]
               && rgba(dark.disabledForeground) == [1, 1, 1, 0.249], "Dark Aqua GrayA4/5/11/12/8")
        expect(light.background(hovered: false, pressed: false, enabled: true) == .clear
               && light.background(hovered: true, pressed: false, enabled: true) == light.hoveredBackground
               && light.background(hovered: true, pressed: true, enabled: true) == light.pressedBackground
               && light.background(hovered: true, pressed: true, enabled: false) == .clear, "Background: rest clear, hover A4, press A5, disabled clear")
        expect(light.foreground(pressed: false, enabled: true) == light.foreground && light.foreground(pressed: true, enabled: true) == light.pressedForeground
               && light.foreground(pressed: false, enabled: false) == light.disabledForeground, "Foreground: A11, pressed A12, disabled A8")

        let clock = ManualClock()
        let icon = BoxOfThingsIconState(); icon.after = clock.schedule
        icon.hover(true, reduceMotion: false)
        expect(icon.isHovered && icon.twinkle1 && !icon.twinkle2 && clock.count == 2, "Hover: pose and twinkle1 at once, two delayed toggles")
        clock.advance(0.149)
        expect(icon.twinkle1 && !icon.twinkle2, "Nothing before 0.15 s")
        clock.advance(0.001)
        expect(!icon.twinkle1 && icon.twinkle2, "At 0.15 s twinkle1 back, twinkle2 on")
        clock.advance(0.15)
        expect(!icon.twinkle1 && !icon.twinkle2 && clock.count == 0, "At 0.3 s twinkle2 back: the net state is unchanged")
        icon.hover(false, reduceMotion: false); clock.advance(0.3)
        expect(!icon.isHovered && !icon.twinkle1 && !icon.twinkle2, "Exit twinkles too and comes back to rest")
        icon.hover(true, reduceMotion: true)
        expect(!icon.isHovered && !icon.twinkle1 && clock.count == 0, "Reduce Motion: no pose, no twinkle, nothing scheduled")

        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 228, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let sidebar = FlippedView(frame: NSRect(x: 0, y: 0, width: 228, height: 400))
        window.contentView = sidebar
        let preferences = freshPreferences()
        let entry = SidebarLibraryEntry()
        entry.preferences = preferences
        entry.model.after = clock.schedule
        var lifecycleDelays: [TimeInterval] = []
        entry.lifecycle.after = { delay, body in lifecycleDelays.append(delay); clock.schedule(delay, body) }
        var now = Date(timeIntervalSinceReferenceDate: 1000)
        entry.now = { now }
        SystemOverrides.reduceMotion = false
        sidebar.addSubview(entry)
        let slot = SidebarChromeLayout.dockLeadingButton(height: sidebar.bounds.height)
        expect(slot == NSRect(x: 8, y: 359, width: 32, height: 32), "The leading dock button slot: x 8, centred in the 50-point dock")
        entry.place(button: slot)
        settle()
        expect(entry.convert(entry.buttonRect, to: sidebar) == slot, "The entry's button sits in the leading dock slot")
        expect(entry.frame.size == NSSize(width: 228, height: 360), "The drawing canvas: the sidebar's width, room above for four rows")
        expect(entry.hostRect == entry.buttonRect, "HomeButton host is 32 × 32 without a badge")
        func hit(_ point: NSPoint) -> NSView? { sidebar.hitTest(sidebar.convert(point, to: sidebar.superview)) }
        expect(hit(NSPoint(x: 24, y: 375)) === entry, "The button takes the pointer")
        expect(hit(NSPoint(x: 45, y: 375)) === sidebar && hit(NSPoint(x: 24, y: 340)) === sidebar,
               "The canvas outside the button passes the pointer to what lies below (the Space strip, the list)")
        expect(SidebarChromeLayout.dockStrip(width: 228, height: 400) == NSRect(x: 40, y: 350, width: 148, height: 50),
               "The Space strip runs 40…width − 40")
        expect(entry.iconHoverRect == NSRect(x: 8, y: 322.5, width: 32, height: 27), "The icon's hover region: its 81 × 27 ZStack within the button")

        expect(!entry.acceptsFirstResponder && !entry.canBecomeKeyView && !entry.host.acceptsFirstResponder && !entry.host.canBecomeKeyView,
               "No keyboard stop on the entry or its rendering")
        window.makeFirstResponder(entry)
        let entryRefused = window.firstResponder !== entry
        window.makeFirstResponder(entry.host)
        expect(entryRefused && window.firstResponder !== entry.host && entry.focusRingType != .exterior,
               "Focus is refused even when asked directly, no ring")

        var opened: [LibraryEntryPage?] = []
        entry.onOpen = { opened.append($0) }
        let home = entry.homeAccessibilityElement
        expect(!entry.isAccessibilityElement() && (entry.accessibilityChildren() ?? []).count == 1
               && (entry.accessibilityChildren()?.first as AnyObject?) === home, "AX: the canvas exposes only the Home button at rest")
        expect(NSAccessibility.unignoredChildren(from: [entry]).contains { ($0 as AnyObject) === home }, "An ignored canvas promotes its Home element")
        expect(home.accessibilityRole() == .button && home.accessibilityLabel() == "Home" && home.accessibilityValue() == nil,
               "AX: button, label Home, no value")
        let homeParent = home.accessibilityParent() as AnyObject?
        expect(homeParent != nil && homeParent !== entry
               && (homeParent === NSAccessibility.unignoredAncestor(of: entry) as AnyObject?),
               "Home's parent is the canvas's unignored ancestor, which lists it")
        expect(home.accessibilityFrame() == window.convertToScreen(entry.convert(entry.buttonRect, to: nil)), "AX frame is the 32-point button")
        expect(!entry.host.isAccessibilityElement() && entry.host.accessibilityChildren()?.isEmpty == true, "The SwiftUI rendering adds no element")
        expect(home.accessibilityPerformPress() && opened.count == 1 && opened[0] == nil, "AX press clicks with no target page")

        let centre = NSPoint(x: entry.buttonRect.midX, y: entry.buttonRect.midY)
        entry.pointerMoved(to: centre)
        expect(entry.state.hovered && entry.state.icon.isHovered && entry.state.icon.twinkle1, "Hovering the button hovers the style and the icon")
        clock.advance(0.3)
        entry.pointerMoved(to: NSPoint(x: centre.x, y: entry.buttonRect.minY + 1))
        expect(entry.state.hovered && !entry.state.icon.isHovered, "The button's top 2.5 points are outside the icon's hover region")
        entry.pointerMoved(to: centre); clock.advance(0.3)
        entry.mouseDown(with: event(.leftMouseDown, centre, in: entry))
        expect(entry.state.pressed && opened.count == 1, "Pressed on mouse-down, no action yet")
        entry.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: centre.x + 40, y: centre.y), in: entry))
        expect(!entry.state.pressed, "Dragging outside releases the pressed look")
        entry.mouseUp(with: event(.leftMouseUp, NSPoint(x: centre.x + 40, y: centre.y), in: entry))
        expect(opened.count == 1, "Mouse-up outside does nothing")
        entry.mouseDown(with: event(.leftMouseDown, centre, in: entry))
        entry.mouseUp(with: event(.leftMouseUp, centre, in: entry))
        expect(opened.count == 2 && !entry.state.pressed, "Mouse-up inside clicks once")
        entry.mouseDown(with: event(.leftMouseDown, centre, in: entry, flags: [.shift, .option]))
        entry.mouseUp(with: event(.leftMouseUp, centre, in: entry, flags: [.shift, .option]))
        expect(opened.count == 3 && opened[2] == nil, "Modifiers change nothing")

        let button = TooltipConfiguration("View Library", shortcut: .command("viewLibrary:"), anchorRect: entry.buttonRect)
        expect(entry.parcTooltip == button && entry.toolTip == nil, "View Library, anchored to the button, before any pointer")
        entry.pointerMoved(to: nil)
        expect(entry.parcTooltip == button, "Leaving keeps the configuration; no part takes the pointer there")
        entry.pointerMoved(to: centre)
        expect(entry.parcTooltip == button && entry.hitTest(entry.superview!.convert(centre, from: entry)) === entry,
               "Over the button, the button's tooltip; the canvas takes the pointer only there")
        expect(entry.hitTest(entry.superview!.convert(NSPoint(x: entry.buttonRect.maxX + 30, y: centre.y), from: entry)) == nil,
               "Beside the button the canvas takes no pointer, so no tooltip shows")
        entry.pointerMoved(to: nil)
        expect(!entry.state.hovered, "Leaving clears the hover")
        clock.advance(1)

        let menu = entry.menu(for: event(.rightMouseDown, centre, in: entry))!
        expect(menu.items.map(\.title) == ["Show media from:", "Documents", "Desktop", "Screenshots", "Saved Captures", "Downloads"],
               "The source menu titles in order, captures as Saved Captures")
        expect(!menu.items[0].isEnabled && menu.items[1...5].allSatisfy { $0.isEnabled && $0.state == .on },
               "All five sources badge by default")
        expect(entry.menu(for: event(.rightMouseDown, NSPoint(x: 2, y: 2), in: entry)) == nil, "No menu outside the button")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory), profile = store.state.profiles[0].id
        func publish(_ id: String, status: String = "downloading", received: Int = 40, date: Double = 10) -> BrowserDownload {
            store.recordDownload(["id": id, "profilePath": store.independentEngineProfilePath(for: profile), "name": id, "status": status,
                                  "startedAt": date, "receivedBytes": received, "totalBytes": 100, "available": true, "itemIdentity": "live-" + id])
            return store.state.downloads.first { $0.nativeID == id }!
        }
        func feed(_ items: [BrowserDownload], badging: Bool = true) {
            entry.updateFlyoutDownloads(items, profiles: [profile], privateWindow: false, badging: badging)
        }
        func dismissals(_ body: () -> Void) -> [TimeInterval] {
            let start = lifecycleDelays.count
            body()
            return Array(lifecycleDelays[start...])
        }
        let running = publish("report.pdf")
        let runningID = "download:" + running.id
        expect(entry.badge.isDescendant(of: entry.host), "The progress renderer sits in the entry's cell, not over the icon")
        let runningDismissals = dismissals { feed([running]) }
        expect(entry.lifecycle.visibleID == runningID && entry.badge.activity?.progress == 0.4 && !entry.badge.isHidden
               && entry.model.ringActive, "A new live download becomes the visible item; its cell draws the renderer at its real progress")
        expect(runningDismissals.isEmpty, "A running download is never dismissed: no timer runs")
        expect(entry.model.visibleBadge == runningID && entry.model.phase == .landing, "A visible badge item starts the show")
        expect(entry.model.cell == LibraryEntryCellPose(x: 10, y: 42, opacity: 1, scale: 0.8, rotation: 0) && entry.model.buttonYOffset == 6,
               "Landing: to b + 12, opacity 1, button 6 down, scale 0.8")
        expect(entry.hostRect == NSRect(x: 8, y: 310, width: 42, height: 42), "The host grows to 42 × 42 up and right while a badge shows")
        let badgeElement = entry.accessibilityChildren()?.last as? LibraryEntryElement
        expect(entry.accessibilityChildren()?.count == 2 && badgeElement?.accessibilityLabel() == "Download \u{2014} report.pdf"
               && badgeElement?.accessibilityRole() == .button && badgeElement?.accessibilityValue() == nil && home.accessibilityValue() == nil,
               "The visible badge cell: a button labelled Download — file, no progress value anywhere")
        let landing = cellMotion(entry, travel: entry.model.cell.y - (LibraryEntryModel.base - 8), for: 0.3)
        expect(abs(landing.progress(at: 0)) < 0.1 && landing.progress(at: 0.1) < 0.35 && landing.progress(at: 0.17) > 0.6
               && landing.rests(after: 0.23) && landing.peak < 1.02,
               "Landing draws the 0.2 s timing curve from the seed: \(landing.trace)")
        clock.advance(0.219)
        expect(entry.model.phase == .landing, "Nothing before 0.22 s")
        let landed = entry.model.cell.y
        clock.advance(0.001)
        expect(entry.model.phase == .shown && entry.model.cell.y == 30 && entry.model.buttonYOffset == 0,
               "At 0.22 s the cell settles to b and the button to rest")
        let settling = cellMotion(entry, travel: entry.model.cell.y - landed, for: 0.8)
        expect(settling.progress(at: 0.08) > 0.6 && settling.peak > 1.05 && settling.rests(after: 0.6),
               "The settle draws the 500/25/10 spring: \(settling.trace)")
        let cell = entry.badge.convert(entry.badge.bounds, to: entry)
        expect(entry.model.presentedSlot(in: entry.flyout.rows, reduceMotion: false) == 0
               && near(cell, NSRect(x: 34 - 16, y: 324 - 16, width: 32, height: 32), 0.5),
               "The 40 × 40 icon at 0.8 in the 40 × 56 cell, offset (−4, −30) then (10, 56 × 0 + 30) from the button's bottom-left: \(cell)")
        now = now.addingTimeInterval(299)
        _ = home.accessibilityPerformPress()
        expect(opened.last! == .downloads, "A download badge seen under 300 s ago opens Downloads")
        _ = home.accessibilityPerformPress()
        expect(opened.last! == .downloads, "A click alone reads nothing: only the Library opening does")
        entry.libraryDidOpen()
        _ = home.accessibilityPerformPress()
        expect(opened.last! == nil, "The Library opening by any route read it: the next click names no page")
        var progressed = running; progressed.receivedBytes = 70
        feed([progressed])
        expect(entry.model.phase == .shown && entry.badge.activity?.progress == 0.7
               && cellMotion(entry, travel: 0, for: 0.15).still,
               "Progress moves the same renderer and does not replay the show: the cell stays put")
        clock.advance(600)
        expect(entry.lifecycle.visibleID == runningID && entry.model.phase == .shown, "Still visible ten minutes on: never dismissed while it runs")
        let firstRenderer = entry.badge.subviews.first
        var finished = progressed; finished.status = .completed
        let finishedDismissals = dismissals { feed([finished]) }
        expect(entry.badge.activity?.completed == true && entry.badge.subviews.first === firstRenderer && entry.model.ringActive
               && entry.model.phase == .shown && entry.model.cell.scale == 0.8,
               "Completion plays DL27's transaction on the same renderer; the seeded 0.8 stays")
        expect(finishedDismissals == [30], "A completed download stays 30 s")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        expect(entry.badge.activity == nil && entry.badge.subviews.isEmpty && !entry.model.ringActive
               && entry.model.visibleItem?.downloadStatus == .completed && entry.model.visibleItem?.showsImage == true,
               "After 1.45 s the renderer retires; the cell shows the completed file's image (BadgingIcon .completed → IconImage)")
        feed([finished])
        expect(entry.badge.activity == nil && entry.badge.subviews.isEmpty, "Republishing the completed item never replays completion")
        clock.advance(29.99)
        expect(entry.model.visibleBadge == runningID, "Not before 30 s")
        let shownY = entry.model.cell.y
        clock.advance(0.01)
        expect(entry.model.visibleBadge == nil && entry.model.phase == .hiding
               && entry.model.cell == LibraryEntryCellPose(x: -4, y: 50, opacity: 0, scale: 0.2, rotation: -45),
               "At 30 s: hide to x − 14, b + 20, 0, 0.2, −45°")
        expect(entry.hostRect == entry.buttonRect && entry.accessibilityChildren()?.count == 1, "The host is back to 32 × 32; only Home remains")
        let leaving = cellMotion(entry, travel: entry.model.cell.y - shownY, for: 0.25)
        expect((0.3...0.7).contains(leaving.progress(at: 0.07)) && leaving.rests(after: 0.17) && leaving.peak < 1.02,
               "The hide draws the 0.14 s linear leave: \(leaving.trace)")
        clock.advance(0.16)
        expect(entry.model.phase == .hidden && entry.model.cell == LibraryEntryCellPose(), "Cleared after 0.16 s")
        feed([finished])
        expect(entry.model.visibleBadge == nil, "A dismissed download is not badged again")
        let other = publish("archive.zip", date: 20)
        now = now.addingTimeInterval(10)
        feed([finished, other])
        let otherID = "download:" + other.id
        expect(entry.model.visibleBadge == otherID && entry.badge.activity?.name == "archive.zip", "The next new download is the visible item")
        clock.advance(1)
        var failedOther = other; failedOther.status = .failed
        let failedDismissals = dismissals { feed([finished, failedOther]) }
        expect(entry.badge.activity == nil && entry.badge.subviews.isEmpty && !entry.model.ringActive && entry.model.visibleBadge == otherID
               && failedDismissals == [5] && entry.accessibilityChildren()?.count == 2,
               "Failure: no renderer, the empty cell stays visible (and in the AX tree), dismissed after 5 s")
        clock.advance(4.99)
        expect(entry.model.visibleBadge == otherID, "Not before 5 s")
        clock.advance(0.01)
        expect(entry.model.visibleBadge == nil && entry.model.phase == .hiding, "At 5 s the failed download's cell hides")
        clock.advance(1)
        now = now.addingTimeInterval(300)
        _ = home.accessibilityPerformPress()
        expect(opened.last! == nil, "At 300 s the badge no longer names a page")
        let doneLater = publish("later.dmg", status: "completed", date: 30)
        feed([finished, failedOther, doneLater])
        expect(entry.model.visibleBadge == nil, "Restored or completed work never shows a badge")
        var restored = publish("restored.iso", date: 35); restored.nativeIdentity = nil
        feed([finished, restored])
        expect(entry.model.visibleBadge == nil, "Metadata without a live incarnation never shows a badge")
        let paused = publish("paused.mov", date: 36)
        var pausedNow = paused; pausedNow.status = .paused
        let pausedDismissals = dismissals { feed([paused]); feed([pausedNow]) }
        expect(entry.model.visibleBadge == "download:" + paused.id && entry.badge.activity == nil && pausedDismissals.isEmpty,
               "Paused: an empty cell that stays")
        feed([paused])
        expect(entry.badge.activity?.name == "paused.mov" && entry.model.ringActive, "Resumed: the renderer draws again")
        var pending = paused; pending.status = .pending
        feed([pending])
        expect(entry.badge.activity == nil && entry.model.visibleBadge != nil, "Pending (not started): an empty cell")
        feed([], badging: false)
        expect(entry.model.visibleBadge == nil && entry.badge.activity == nil, "A window that stops badging clears the item and its renderer")
        clock.advance(1)

        let shown = publish("photo.png", date: 40)
        feed([shown])
        expect(entry.model.visibleBadge != nil, "Badging on")
        let toggle = entry.makeMenu().items[5]
        _ = (toggle.target as? MenuAction)?.invoke(); settle()
        expect(!preferences.isEnabled(.downloads) && !entry.showsDownloadBadges && entry.badge.activity == nil && entry.model.phase == .hiding,
               "Turning Downloads off clears the badge")
        expect(entry.makeMenu().items[5].state == .off, "The menu shows it off")
        feed([shown])
        expect(entry.badge.activity == nil && entry.model.visibleBadge == nil, "No badge while off")
        _ = (entry.makeMenu().items[5].target as? MenuAction)?.invoke(); settle()
        expect(preferences.isEnabled(.downloads), "And back on")
        feed([], badging: false)
        clock.advance(1)

        func savedCapture(_ title: String, at date: Date) -> SavedCapture {
            SavedCapture(id: UUID(), revision: UUID(), profileID: profile, spaceID: UUID(), spaceName: "Space", title: title,
                         sourceURL: "https://example.com/" + title, createdAt: date, kind: .viewport, pixelWidth: 10, pixelHeight: 10)
        }
        feed([])
        entry.updateFlyoutCaptures([savedCapture("Old capture", at: now.addingTimeInterval(-300))])
        expect(entry.model.visibleBadge == nil, "A capture 300 s old is not badged")
        let fresh = savedCapture("New capture", at: now.addingTimeInterval(-2))
        let captureDismissals = dismissals { entry.updateFlyoutCaptures([fresh]) }
        expect(entry.model.visibleBadge == "capture:" + fresh.id.uuidString && entry.model.cell.scale == 0.55
               && captureDismissals == [5] && entry.badge.activity == nil, "A new capture: visible at 0.55, dismissed after 5 s")
        expect((entry.accessibilityChildren()?.last as? LibraryEntryElement)?.accessibilityLabel() == "Capture \u{2014} New capture",
               "Its cell is a Capture — title button")
        _ = home.accessibilityPerformPress()
        expect(opened.last! == .captures, "A recent capture opens the Library's Media page")
        clock.advance(5)
        expect(entry.model.visibleBadge == nil, "Dismissed at 5 s")
        entry.updateFlyoutCaptures([])
        clock.advance(1)

        typealias R = LibraryEntryRoute
        expect(R.decide(target: nil, showing: nil, lastSelected: .captures) == .open(.captures), "No target: the last selected page")
        expect(R.decide(target: .downloads, showing: nil, lastSelected: .captures) == .open(.downloads), "A recent download opens Downloads")
        expect(R.decide(target: .downloads, showing: .downloads, lastSelected: .captures) == .close, "Showing the target: close")
        expect(R.decide(target: .downloads, showing: .archive, lastSelected: .captures) == .open(.downloads), "Another page: switch to the target")
        expect(R.decide(target: nil, showing: .archive, lastSelected: .archive) == .close, "Open with no target: close")
        expect(preferences.lastSelectedPage == .downloads, "Downloads before any page was shown")
        preferences.lastSelectedPage = .documents
        expect(preferences.lastSelectedPage == .documents, "The last page persists")
        expect(R.target(unread: nil, now: now) == nil
               && R.target(unread: LibraryEntryUnread(page: .downloads, since: now.addingTimeInterval(-299.9)), now: now) == .downloads
               && R.target(unread: LibraryEntryUnread(page: .captures, since: now.addingTimeInterval(-299.9)), now: now) == .captures
               && R.target(unread: LibraryEntryUnread(page: .downloads, since: now.addingTimeInterval(-300)), now: now) == nil, "The 300 s rule")
        expect(LibraryEntryLayout.totalHeight(count: 4) == 256 && LibraryEntryLayout.expandedCellWidth(containerWidth: 1200) == 984
               && LibraryEntryLayout.expandedCellWidth(containerWidth: 228) == 212, "Recovered flyout constants")

        let flyout = entry.flyout
        var actions: [String] = []
        entry.onItemAction = { action in
            switch action {
            case let .download(item, command): actions.append("\(item.name):\(command)")
            case let .file(file, command): actions.append("file:\(file.title):\(command)")
            case .showCapture(let item): actions.append("show:\(item.title)")
            case .copyCapture(let item): actions.append("copy:\(item.title)")
            case .openCaptureSource(let item): actions.append("source:\(item.title)")
            case .copyCaptureSource(let item): actions.append("copySource:\(item.title)")
            case let .share(item, share): actions.append("share:\(share):\(item.title)")
            case .deleteCapture(let item): actions.append("delete:\(item.title)")
            }
            return true
        }
        var expansions: [String] = []
        entry.onFlyoutExpansion = { expansions.append("\($0):\($1)") }
        let thumbnail = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in NSColor.systemTeal.setFill(); rect.fill(); return true }
        var imageRequests: [String] = []
        flyout.imageLoader = { item, completion in imageRequests.append(item.title); completion(thumbnail); return {} }
        func capture(_ title: String, at seconds: Double) -> SavedCapture {
            SavedCapture(id: UUID(), revision: UUID(), profileID: profile, spaceID: UUID(), spaceName: "Space", title: title,
                         sourceURL: "https://example.com/" + title, createdAt: Date(timeIntervalSince1970: seconds), kind: .viewport,
                         pixelWidth: 10, pixelHeight: 10)
        }
        let older = publish("older.zip", status: "completed", received: 100, date: 1_000)
        let shot = capture("Screenshot", at: 2_000)
        var paper = publish("paper.pdf", status: "completed", received: 100, date: 3_000)
        paper.canOpen = true; paper.canReveal = true; paper.canRemove = true; paper.canCopyFile = true
        var movie = publish("movie.mov", status: "downloading", received: 30, date: 4_000)
        movie.canCancel = true
        let failed = publish("failed.bin", status: "failed", date: 3_500)
        let oldest = publish("oldest.txt", status: "completed", received: 100, date: 500)
        var hidden = publish("private.dmg", date: 5_000); hidden.privateContextID = "private-context"
        entry.canExpand = false
        entry.updateFlyoutCaptures([shot])
        entry.updateFlyoutDownloads([older, paper, movie, failed, oldest, hidden], profiles: [profile], privateWindow: false)
        expect(flyout.rows.map(\.title) == ["movie.mov", "failed.bin", "paper.pdf", "Screenshot"],
               "The newest four downloads and captures, newest first; private downloads stay out of a normal window: \(flyout.rows.map(\.title))")
        expect(LibraryFlyoutItems.merge(downloads: [paper, paper], captures: []).count == 1, "Items are unique by file")
        let desktopFile = LibraryFlyoutFile(url: URL(fileURLWithPath: "/tmp/from-desktop.png"),
                                            dateCreated: Date(timeIntervalSince1970: 10_000), isScreenshot: false, source: .desktop)
        expect(LibraryFlyoutItems.merge(downloads: [paper], captures: [shot], files: [desktopFile]).map(\.title)
               == ["from-desktop.png", "paper.pdf", "Screenshot"],
               "Folder files join downloads and captures, newest first")
        var samePath = paper; samePath.path = "/tmp/from-desktop.png"
        expect(LibraryFlyoutItems.merge(downloads: [samePath], captures: [], files: [desktopFile]).count == 1,
               "A download and a folder file at the same path are unique")
        expect(imageRequests.sorted() == ["Screenshot", "paper.pdf"] && flyout.images.count == 2,
               "IconImage loads for the capture and the completed download only")
        let movieID = flyout.rows[0].id, failedID = flyout.rows[1].id, paperID = flyout.rows[2].id, shotID = flyout.rows[3].id
        expect(LibraryFlyoutText.subtitle(flyout.rows[2], now: Date(timeIntervalSince1970: 3_120))
               == LibraryFlyoutText.relative.localizedString(for: Date(timeIntervalSince1970: 3_000), relativeTo: Date(timeIntervalSince1970: 3_120))
               && LibraryFlyoutText.subtitle(flyout.rows[0], now: Date()) == DownloadRowSubtitle.text(for: movie),
               "Subtitles: a relative date when finished, the Library's download subtitle while running")

        expect(LibraryFlyoutLayout.hiddenOffset(reverseIndex: 0) == 20 && LibraryFlyoutLayout.hiddenOffset(reverseIndex: 3) == 56
               && LibraryFlyoutLayout.stagger(reverseIndex: 0) == 0 && abs(LibraryFlyoutLayout.stagger(reverseIndex: 2) - 0.025) < 1e-12
               && abs(LibraryFlyoutLayout.stagger(reverseIndex: 7) - 0.05) < 1e-12 && LibraryFlyoutLayout.animationDuration == 0.15
               && LibraryFlyoutLayout.animation(reverseIndex: 2)
                    == Animation.interactiveSpring(response: 0.15, dampingFraction: 0.86, blendDuration: 0.25).delay(0.025),
               "Collapsed rows wait 20/56 below; spring 0.15/0.86/0.25 staggered by min(i/4, 1) × 0.05")
        expect(!flyout.expanded && flyout.trackedRegions.isEmpty, "Nothing tracks while the window cannot expand")
        entry.canExpand = true
        expect(flyout.trackedRegions == [.button], "canExpand registers the button region only")
        let buttonCentre = NSPoint(x: entry.buttonRect.midX, y: entry.buttonRect.midY)
        expect(entry.visibleCellRect?.contains(buttonCentre) == true, "The visible badge cell overlaps the button's top-right")
        entry.pointerMoved(to: NSPoint(x: entry.buttonRect.minX + 4, y: entry.buttonRect.maxY - 2))
        clock.advance(0.149)
        expect(!flyout.buttonHovered && !flyout.expanded, "The button region needs 0.15 s of lingering")
        clock.advance(0.001)
        expect(flyout.buttonHovered && flyout.eligibleToExpand && flyout.expanded && flyout.animating && flyout.flyoutHovered
               && expansions == ["true:4"], "Lingering 0.15 s expands; the button lies inside the flyout region")
        expect(flyout.trackedRegions == [.button, .dock, .flyout], "Expanded, the flyout and dock regions register")
        expect(entry.hostRect == NSRect(x: 8, y: 352 - 256, width: 228, height: 256), "The host is min(width, 1000) × 256")
        let regions = entry.hoverRegions
        expect(regions[.dock] == NSRect(x: 40, y: 320, width: 188, height: 32) && regions[.flyout] == NSRect(x: 8, y: 96, width: 220, height: 256),
               "Dock region right of the button, flyout region from its corner")
        clock.advance(0.149)
        expect(flyout.animating, "isAnimating lasts animationDuration")
        clock.advance(0.001)
        expect(!flyout.animating, "…0.15 s")
        settle(0.8)
        let frames = flyout.rows.map { flyout.rowFrame($0.id) ?? .zero }
        expect(zip(frames, flyout.rows).allSatisfy { near($0, flyout.measuredRowFrames[$1.id] ?? .zero, 0.5) },
               "The layout puts expanded rows in their slots")
        expect(frames.allSatisfy { near($0.width, 212) && near($0.height, 56) && near($0.minX, 4) }
               && near(frames[0].maxY, 322) && near(frames[1].maxY, 266) && near(frames[2].maxY, 210) && near(frames[3].maxY, 154),
               "Rows 212 × 56 at x 4, the newest beside the button 30 points up: \(frames)")
        let cancelFrame = flyout.cancelFrame(movieID) ?? .zero
        expect(near(cancelFrame.width, 24) && near(cancelFrame.height, 24) && frames[0].contains(cancelFrame)
               && frames[0].maxX - cancelFrame.maxX < 20 && near(cancelFrame.midY, frames[0].midY) && flyout.cancelFrame(paperID) == nil,
               "The running download's 24-point cancel button sits at the trailing edge: \(cancelFrame)")
        func rings(in view: NSView) -> [DownloadActivityBadge] {
            view.subviews.flatMap { ($0 as? DownloadActivityBadge).map { [$0] } ?? rings(in: $0) }
        }
        let movieIcon = entry.badge.convert(entry.badge.bounds, to: entry)
        expect(entry.model.presentedSlot(in: flyout.rows, reduceMotion: false) == 0 && rings(in: entry.host).allSatisfy { $0 === entry.badge }
               && entry.badge.activity?.identity == DownloadLibraryIdentity(movie) && entry.badge.activity?.progress == 0.3
               && near(movieIcon, NSRect(x: frames[0].minX + 4, y: frames[0].midY - 20, width: 40, height: 40), 0.5),
               "The visible running row draws the visible cell's renderer in its thumbnail slot: \(movieIcon)")

        let paperCentre = NSPoint(x: frames[2].midX, y: frames[2].midY)
        entry.pointerMoved(to: paperCentre)
        expect(!flyout.buttonHovered && flyout.flyoutHovered && flyout.expanded && flyout.hoveredRow == paperID,
               "Leaving the button for a row keeps the flyout; the row is hovered")
        expect(sidebar.hitTest(sidebar.convert(paperCentre, from: entry)) === entry, "Rows take the pointer while expanded")
        expect(entry.parcTooltip == TooltipConfiguration("paper.pdf", anchorRect: frames[2]), "A cell's tooltip is its title, at the cell")
        entry.pointerMoved(to: NSPoint(x: cancelFrame.midX, y: cancelFrame.midY))
        expect(entry.parcTooltip == TooltipConfiguration("Cancel Download", anchorRect: cancelFrame) && flyout.hoveredRow == movieID,
               "The cancel button's tooltip, at the button")
        entry.pointerMoved(to: NSPoint(x: 120, y: 336))
        clock.advance(0.499)
        expect(flyout.expanded, "The dock region needs 0.5 s")
        clock.advance(0.001)
        expect(!flyout.expanded && !flyout.flyoutHovered && flyout.trackedRegions == [.button] && flyout.hoveredRow == nil
               && expansions == ["true:4", "false:4"], "Lingering on the dock collapses the flyout")
        expect(entry.badge.activity?.identity == DownloadLibraryIdentity(movie) && !entry.badge.subviews.isEmpty,
               "Collapsing keeps the visible row's renderer drawing")
        settle(0.5)
        let movieCorner = entry.badge.convert(entry.badge.bounds, to: entry)
        expect(near(movieCorner, NSRect(x: 34 - 16, y: 324 - 16, width: 32, height: 32), 0.5),
               "…which rides the row's spring back to the button's top-right at 0.8: \(movieCorner)")
        expect(sidebar.hitTest(sidebar.convert(paperCentre, from: entry)) === sidebar, "Hidden rows pass the pointer through")
        entry.pointerMoved(to: paperCentre); clock.advance(1)
        expect(!flyout.expanded, "Collapsed rows do not reopen it")
        entry.pointerMoved(to: buttonCentre); clock.advance(0.15)
        expect(flyout.expanded, "The button reopens it")
        entry.pointerMoved(to: nil); clock.advance(0.2)
        expect(!flyout.expanded && !flyout.buttonHovered, "Leaving collapses it")
        entry.libraryDidClose()
        entry.pointerMoved(to: buttonCentre); clock.advance(0.15)
        expect(flyout.buttonHovered && !flyout.eligibleToExpand && !flyout.expanded, "The 100 ms close guard")
        entry.pointerMoved(to: nil); clock.advance(0.2)
        now = now.addingTimeInterval(0.101)
        entry.pointerMoved(to: buttonCentre); clock.advance(0.15)
        expect(flyout.expanded, "After 100 ms the button expands again")
        entry.canExpand = false
        expect(!flyout.expanded && !flyout.buttonHovered && !flyout.flyoutHovered && !flyout.eligibleToExpand
               && flyout.trackedRegions.isEmpty, "Unregistered regions report unhovered")
        entry.pointerMoved(to: nil); clock.advance(0.2)
        entry.canExpand = true; clock.advance(0.2)
        expect(!flyout.expanded && !flyout.buttonHovered, "Closing the Library leaves the flyout collapsed")
        entry.pointerMoved(to: buttonCentre); clock.advance(0.15)
        expect(flyout.expanded, "Lingering on the button expands it again")
        clock.advance(0.2); settle(0.4)

        let openedBefore = opened.count
        expect(entry.tapRow(paperID) && actions.last == "paper.pdf:open", "A finished download opens")
        expect(entry.tapRow(movieID) && opened.count == openedBefore + 1 && opened.last! == .downloads,
               "A running download opens the Library's Downloads page (onDidSelectInProgressDownload)")
        expect(entry.tapRow(failedID) && opened.last! == .downloads, "So does any unfinished download")
        expect(entry.tapRow(shotID) && actions.last == "show:Screenshot", "A capture shows its Library page")
        expect(entry.cancel(movieID) && actions.last == "movie.mov:cancel" && !entry.cancel(paperID), "Cancel only a running download")
        let cancelCentre = NSPoint(x: cancelFrame.midX, y: cancelFrame.midY)
        entry.mouseDown(with: event(.leftMouseDown, cancelCentre, in: entry))
        entry.mouseUp(with: event(.leftMouseUp, cancelCentre, in: entry))
        expect(actions.last == "movie.mov:cancel" && actions.count == 4, "Clicking the cancel button cancels")
        entry.mouseDown(with: event(.leftMouseDown, paperCentre, in: entry))
        entry.mouseUp(with: event(.leftMouseUp, NSPoint(x: paperCentre.x, y: frames[3].midY), in: entry))
        expect(actions.count == 4, "Releasing over another row does nothing")
        entry.mouseDown(with: event(.leftMouseDown, paperCentre, in: entry))
        entry.mouseUp(with: event(.leftMouseUp, paperCentre, in: entry))
        expect(actions.last == "paper.pdf:open" && actions.count == 5, "Clicking a row taps it")
        func titles(_ menu: NSMenu?) -> [String] { menu?.items.map { $0.isSeparatorItem ? "—" : $0.title } ?? [] }
        func enabled(_ menu: NSMenu?) -> [Bool] { menu?.items.filter { !$0.isSeparatorItem }.map(\.isEnabled) ?? [] }
        func invoke(_ menu: NSMenu?, _ title: String) { _ = (menu?.items.first { $0.title == title }?.target as? MenuAction)?.invoke() }
        let paperMenu = entry.rowMenu(paperID)
        expect(titles(paperMenu) == ["Copy PDF", "—", "Send via iMessage", "AirDrop", "—", "Open", "Show in Finder", "—",
                                     "Hide from Parc", "Move to Trash"]
               && enabled(paperMenu) == [true, true, true, true, true, true, true], "A finished download's menu: \(titles(paperMenu))")
        for title in ["Copy PDF", "Show in Finder", "Hide from Parc", "Move to Trash"] { invoke(paperMenu, title) }
        expect(actions.suffix(4) == ["paper.pdf:copyFile", "paper.pdf:reveal", "paper.pdf:remove", "paper.pdf:trash"],
               "Copy, Show in Finder, Hide and Trash dispatch the original item through the download route")
        invoke(paperMenu, "Send via iMessage"); invoke(paperMenu, "AirDrop")
        expect(actions.suffix(2) == ["share:message:paper.pdf", "share:airDrop:paper.pdf"], "iMessage and AirDrop share the original item")
        expect(titles(entry.rowMenu(movieID)) == ["Cancel Download"] && enabled(entry.rowMenu(movieID)) == [true]
               && entry.rowMenu(failedID) == nil, "Running: Cancel Download; failed: no menu")
        let shotMenu = entry.rowMenu(shotID)
        expect(titles(shotMenu) == ["Copy Image", "—", "Send via iMessage", "AirDrop", "—", "Open Source URL", "Copy Source URL", "—", "Delete"]
               && enabled(shotMenu) == [true, true, true, true, true, true], "A capture's menu: \(titles(shotMenu))")
        invoke(shotMenu, "Open Source URL")
        expect(actions.last == "source:Screenshot", "Open Source URL goes through the capture route")
        invoke(shotMenu, "AirDrop"); invoke(shotMenu, "Delete")
        expect(actions.suffix(2) == ["share:airDrop:Screenshot", "delete:Screenshot"], "A capture's AirDrop and Delete go to the window's routes")
        expect(titles(entry.menu(for: event(.rightMouseDown, paperCentre, in: entry))) == titles(paperMenu), "Right-click on a row")

        let children = entry.accessibilityChildren() ?? []
        let labels = children.compactMap { ($0 as? NSAccessibilityElement)?.accessibilityLabel() }
        expect(labels == ["Home", "Capture \u{2014} Screenshot", "Download \u{2014} paper.pdf", "Download \u{2014} failed.bin",
                          "Download \u{2014} movie.mov"], "Expanded AX: Home and each cell's label: \(labels)")
        let movieElement = children.last as? LibraryEntryElement
        let cancelElement = movieElement?.accessibilityChildren()?.first as? LibraryEntryElement
        expect(children.allSatisfy { ($0 as? NSAccessibilityElement)?.accessibilityRole() == .button && ($0 as? NSAccessibilityElement)?.accessibilityValue() == nil }
               && cancelElement?.accessibilityLabel() == "Cancel Download"
               && (cancelElement?.accessibilityParent() as AnyObject?) === movieElement
               && movieElement?.accessibilityFrame() == window.convertToScreen(entry.convert(frames[0], to: nil)),
               "Cells are buttons framed on their rows; the running one holds Cancel Download")
        expect(cancelElement?.accessibilityPerformPress() == true && actions.last == "movie.mov:cancel"
               && (children[2] as? LibraryEntryElement)?.accessibilityPerformPress() == true && actions.last == "paper.pdf:open",
               "AX presses tap and cancel")
        entry.pointerMoved(to: nil); clock.advance(0.01)
        expect(!flyout.expanded && flyout.animating, "Collapsing animates")
        let beforeAnimatedTap = opened.count
        expect(entry.tapVisibleBadge() && opened.count == beforeAnimatedTap + 1, "A tap while animating clicks the entry (onDidClickEntryPoint)")
        clock.advance(1)

        clock.advance(1); settle(0.3)
        let cellRect = entry.visibleCellRect ?? .zero
        expect(entry.model.visibleBadge == movieID && near(cellRect, NSRect(x: 18, y: 301.6, width: 32, height: 44.8)),
               "The visible cell's hover rect: \(cellRect)")
        expect(!entry.tapVisibleBadge(), "A collapsed visible cell's tap does nothing (onDidTapItem acts only expanded)")
        entry.pointerMoved(to: NSPoint(x: cellRect.midX, y: cellRect.midY))
        expect(flyout.expanded && !flyout.visibleBadgeHovered && flyout.flyoutHovered, "Hovering the visible cell expands; expanding clears its hover")
        entry.pointerMoved(to: nil); clock.advance(1)

        var cancelled = movie; cancelled.status = .cancelled
        let cancelDismissals = dismissals {
            entry.updateFlyoutDownloads([older, paper, cancelled, failed, oldest, hidden], profiles: [profile], privateWindow: false)
        }
        expect(entry.badge.subviews.isEmpty && entry.badge.activity == nil && entry.model.visibleBadge == movieID
               && entry.model.phase == .shown && cancelDismissals == [5], "Cancel: no renderer, the empty cell stays 5 s")
        settle(0.8)
        let cancelledY = entry.model.cell.y
        clock.advance(5)
        let cancelLeaving = cellMotion(entry, travel: entry.model.cell.y - cancelledY, for: 0.25)
        expect(entry.model.phase == .hiding && (0.3...0.7).contains(cancelLeaving.progress(at: 0.07)) && cancelLeaving.rests(after: 0.17),
               "…then the leaving pose animates on the empty cell: \(cancelLeaving.trace)")
        clock.advance(1)

        var song = publish("song.mp3", date: 6_000)
        entry.updateFlyoutDownloads([older, paper, cancelled, song], profiles: [profile], privateWindow: false)
        let songID = "download:" + song.id
        clock.advance(1)
        song.status = .completed
        let songDismissals = dismissals {
            entry.updateFlyoutDownloads([older, paper, cancelled, song], profiles: [profile], privateWindow: false)
        }
        expect(entry.model.visibleBadge == songID && songDismissals == [30] && entry.model.cell.scale == 0.8,
               "The completed song stays visible at its seeded 0.8")
        entry.pointerMoved(to: NSPoint(x: entry.buttonRect.midX, y: entry.buttonRect.midY)); clock.advance(0.15)
        expect(flyout.expanded && entry.model.visibleBadge == nil && entry.model.phase == .hiding,
               "Expanding dismisses the finished download's badge")
        entry.pointerMoved(to: nil); clock.advance(1)
        expect(entry.badge.activity == nil, "Nothing renders after the dismissal")

        let temporary = directory.appendingPathComponent("flyout-drag.png")
        try NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in NSColor.systemRed.setFill(); rect.fill(); return true }
            .tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }!.write(to: temporary)
        var fileURL: URL? = temporary
        entry.downloadFileURL = { item in item.status == .completed ? fileURL : nil }
        DraggingSessions.install()
        func expandFlyout() {
            entry.pointerMoved(to: NSPoint(x: entry.buttonRect.midX, y: entry.buttonRect.midY)); clock.advance(0.15); clock.advance(0.2); settle(0.4)
        }
        func dragRow(_ id: String) -> [DraggingStart] {
            guard let frame = flyout.rowFrame(id) else { return [] }
            let start = NSPoint(x: frame.midX, y: frame.midY)
            return DraggingSessions.begun {
                entry.mouseDown(with: event(.leftMouseDown, start, in: entry))
                entry.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: start.x + 10, y: start.y), in: entry))
            }
        }
        func writer(_ drag: [DraggingStart]) -> NSPasteboardItem? { drag.first?.items.first?.item as? NSPasteboardItem }
        func delivered<Value>(_ writer: NSPasteboardWriting?, _ read: (NSPasteboard) -> Value?) -> Value? {
            guard let writer else { return nil }
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.clearContents()
            precondition(board.writeObjects([writer]), "The dragged writer could not be put on a pasteboard")
            return read(board)
        }
        expandFlyout()
        let songDrag = dragRow(songID)
        expect(flyout.expanded && songDrag.count == 1 && songDrag[0].view === entry && (songDrag[0].source as AnyObject) === entry
               && songDrag[0].items.count == 1 && writer(songDrag)?.types == [.fileURL],
               "A completed download's row drags DL28's lazy file provider from the entry")
        expect(delivered(writer(songDrag)) { $0.string(forType: .fileURL) } == temporary.absoluteString,
               "Delivered after the original item is resolved again")
        let staleDrag = dragRow(songID)
        fileURL = nil
        expect(writer(staleDrag) != nil && delivered(writer(staleDrag)) { $0.string(forType: .fileURL) } == nil,
               "A file that is no longer available is never delivered")
        fileURL = temporary
        entry.pointerMoved(to: nil); clock.advance(1)
        var runningDrag = publish("running.bin", date: 7_000); runningDrag.status = .downloading
        entry.updateFlyoutDownloads([older, paper, cancelled, song, runningDrag], profiles: [profile], privateWindow: false)
        expect(entry.dragWriter(for: "download:" + runningDrag.id) == nil, "An unfinished download drags nothing")

        let red = NSImage(contentsOf: temporary)!
        expect(LibraryFlyoutSharing.isImage(temporary) && !LibraryFlyoutSharing.isImage(directory.appendingPathComponent("a.zip")),
               "An image file shares as its image (URL content type)")
        expect((LibraryFlyoutSharing.items(.airDrop, image: red, url: temporary, text: "x").first as? NSImage) === red
               && LibraryFlyoutSharing.items(.airDrop, image: red, url: temporary, text: "x").count == 1
               && (LibraryFlyoutSharing.items(.airDrop, image: nil, url: temporary, text: nil).first as? URL) == temporary,
               "AirDrop: the image, else the file URL")
        let message = LibraryFlyoutSharing.items(.message, image: red, url: nil, text: "https://example.com/Screenshot")
        expect(message.count == 2 && (message[0] as? NSImage) === red && (message[1] as? String) == "https://example.com/Screenshot",
               "iMessage: a capture's image and its source address")
        expect(LibraryFlyoutShare.message.serviceName == .composeMessage && LibraryFlyoutShare.airDrop.serviceName == .sendViaAirDrop
               && LibraryFlyoutSharing.items(.message, image: nil, url: nil, text: nil).isEmpty, "The two macOS services; nothing to share, nothing performed")
        let deletion = LibraryFlyoutCaptureDeletion.dialog()
        let deletionText = deletion.panel.contentView!.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        expect(deletionText == ["Are you sure you want to delete this capture?", "Doing so will delete this capture permanently."]
               && deletion.confirmButton.title == "Delete" && deletion.confirmButton.destructive
               && deletion.cancelButton?.title == "Cancel", "The capture Delete confirmation, a destructive Parc dialog")

        var photo = publish("holiday.png", status: "completed", received: 100, date: 8_000)
        photo.canOpen = true; photo.canCopyFile = true
        entry.updateFlyoutDownloads([photo, song, paper], profiles: [profile], privateWindow: false)
        entry.pointerMoved(to: NSPoint(x: entry.buttonRect.midX, y: entry.buttonRect.midY)); clock.advance(0.15); clock.advance(0.2); settle(0.4)
        let photoID = "download:" + photo.id
        expect(flyout.expanded && flyout.rows.first?.id == photoID, "The photo is the newest row")
        let actionsBefore = actions.count
        expect(entry.tapRow(photoID), "A previewable tap is taken")
        settle(0.3)
        let preview = entry.preview
        expect(preview?.window?.parent === window && preview?.window?.isVisible == true && actions.count == actionsBefore,
               "The preview is a child of this window and nothing was opened")
        expect(preview?.sourceRect?() == entry.convert(entry.buttonRect, to: nil), "Closing returns to the Library button")
        func previewButton(_ label: String, in view: NSView? = nil) -> NSButton? {
            guard let view = view ?? preview?.window?.contentView else { return nil }
            if let button = view as? NSButton, button.accessibilityLabel() == label { return button }
            return view.subviews.lazy.compactMap { previewButton(label, in: $0) }.first
        }
        func previewTitle() -> String? { preview?.window?.title }
        expect(previewTitle() == "holiday.png" && previewButton("Previous download")?.isEnabled == false
               && previewButton("Next download")?.isEnabled == true, "The newest previewable row first, with a next item")
        preview?.onMove?(true)
        expect(previewTitle() == "song.mp3" && previewButton("Previous download")?.isEnabled == true
               && previewButton("Next download")?.isEnabled == true, "Next moves to the next previewable row")
        preview?.onMove?(true)
        expect(previewTitle() == "paper.pdf" && previewButton("Next download")?.isEnabled == false, "…down to the oldest")
        preview?.onMove?(true)
        expect(previewTitle() == "paper.pdf", "Nothing past the end")
        var songGone = song; songGone.status = .failed
        entry.updateFlyoutDownloads([photo, songGone, paper], profiles: [profile], privateWindow: false)
        preview?.onMove?(false)
        expect(previewTitle() == "holiday.png" && entry.preview === preview, "A listed item that is no longer a completed file is skipped")
        entry.updateFlyoutDownloads([song, paper], profiles: [profile], privateWindow: false)
        expect(entry.preview == nil && preview?.window?.isVisible != true, "Losing the original item retires the preview")
        let zipTap = actions.count
        entry.updateFlyoutDownloads([photo, song, paper, older], profiles: [profile], privateWindow: false)
        settle(0.2)
        if let olderRow = flyout.rows.first(where: { $0.title == "older.zip" }) {
            expect(entry.tapRow(olderRow.id) && actions.count == zipTap + 1 && actions.last == "older.zip:open", "A non-media file opens")
        }
        entry.pointerMoved(to: nil); clock.advance(1)
        entry.downloadFileURL = nil

        let captureStore = CaptureLibraryStore.shared(directory: directory.appendingPathComponent("Captures", isDirectory: true), profileID: profile)
        let png = try Data(contentsOf: temporary)
        let saved = SavedBox(), capturedAt = now
        Task { @MainActor in
            saved.value = try? await captureStore.save(CaptureLibraryInput(id: UUID(), expectedRevision: nil, capturedAt: capturedAt, profileID: profile,
                spaceID: UUID(), spaceName: "Space", title: "Dragged", sourceURL: "https://example.com/dragged", kind: .viewport, pngData: png))
        }
        let deadline = Date().addingTimeInterval(10)
        while saved.value == nil && Date() < deadline { settle(0.05) }
        entry.captureStore = captureStore
        settle(0.1)
        let draggedID = "capture:" + (saved.value?.id.uuidString ?? "")
        expandFlyout()
        let captureDrag = dragRow(draggedID)
        let captureWriter = writer(captureDrag)
        expect(saved.value != nil && captureDrag.count == 1 && (captureDrag.first?.source as AnyObject?) === entry
               && captureWriter?.types == [.png], "A capture's row drags a lazy PNG provider")
        var capturePNG = captureWriter?.data(forType: .png)
        while capturePNG == nil && Date() < deadline { settle(0.05); capturePNG = captureWriter?.data(forType: .png) }
        expect(capturePNG == png && delivered(captureWriter) { $0.data(forType: .png) } == png,
               "A capture drags its PNG, read from the store and supplied after the capture is checked again")
        entry.pointerMoved(to: nil); clock.advance(1)
        entry.captureStore = nil
        entry.updateFlyoutCaptures([])

        let expandedLocations = LibraryFlyoutContentMask.locations(totalHeight: 256, height: 800, dockHeight: 50, inset: 0.04).map(\.doubleValue)
        let restingLocations = LibraryFlyoutContentMask.locations(totalHeight: 256, height: 800, dockHeight: 50, inset: 0.14).map(\.doubleValue)
        expect(zip(expandedLocations, [0, 0.0625, 0.0625, 0.3425, 0.4925, 1]).allSatisfy { abs($0 - $1) < 1e-9 }
               && zip(restingLocations, [0, 0.0625, 0.0625, 0.2425, 0.3925, 1]).allSatisfy { abs($0 - $1) < 1e-9 },
               "Mask locations: dock, band to the rows' top less 0.04 (0.14 resting), a 0.15 fade")
        let content = FlippedView(frame: sidebar.bounds); content.wantsLayer = true
        sidebar.addSubview(content, positioned: .below, relativeTo: entry)
        let mask = LibraryFlyoutContentMask()
        mask.expand(on: content, totalHeight: 256, dockHeight: 50)
        expect(content.layer?.mask === mask.layer && mask.band.colors?.count == 4 && mask.band.locations?.count == 4
               && (mask.band.colors?[0] as! CGColor).alpha == 0 && mask.band.animation(forKey: "parc.flyout.colors")?.duration == 0.1,
               "Expanding masks the content: the band is clear, animated over 0.1 s")
        let bandAt800 = LibraryFlyoutContentMask.bandLocations(LibraryFlyoutContentMask.locations(totalHeight: 256, height: 800, dockHeight: 50, inset: 0.04))
        let bandLocations = LibraryFlyoutContentMask.bandLocations(LibraryFlyoutContentMask.locations(totalHeight: 256, height: content.bounds.height, dockHeight: 50, inset: 0.04))
        expect(zip(bandAt800.map(\.doubleValue), [0, 0.28 / 0.9375, 0.43 / 0.9375, 1]).allSatisfy { abs($0 - $1) < 1e-9 }
               && mask.band.locations == bandLocations
               && mask.band.frame == CGRect(x: 0, y: 0, width: content.bounds.width, height: content.bounds.height - 50)
               && mask.layer.sublayers?.first { $0 !== mask.band }?.frame
                   == CGRect(x: 0, y: content.bounds.height - 50, width: content.bounds.width, height: 50),
               "The dock strip is its own opaque layer; the band carries the stops above it")
        CATransaction.flush(); settle()
        mask.collapse(totalHeight: 256, dockHeight: 50)
        expect(abs((mask.band.colors?[0] as! CGColor).alpha - 0.8) < 0.001, "Collapsing returns the band to 0.8")
        expect(mask.band.animation(forKey: "locations") == nil && mask.band.animation(forKey: "colors") == nil
               && mask.band.animation(forKey: "parc.flyout.colors")?.duration == 0.1,
               "Only the 0.1 s animations run; no implicit 0.25 s action overrides them")
        settle(0.5)
        expect(content.layer?.mask == nil && !mask.installed, "…then removes the mask")
        content.removeFromSuperview()
        entry.updateFlyoutDownloads([], profiles: [profile], privateWindow: false)
        entry.updateFlyoutCaptures([])
        expect(flyout.rows.isEmpty && flyout.images.isEmpty, "No items, no rows")

        let folderRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let desktopFolder = folderRoot.appendingPathComponent("Desktop", isDirectory: true)
        let documentsFolder = folderRoot.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: desktopFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documentsFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderRoot) }
        try Data("shot".utf8).write(to: desktopFolder.appendingPathComponent("Screenshot 2026-10-30.png"))
        try Data("doc".utf8).write(to: documentsFolder.appendingPathComponent("notes.txt"))
        try Data("skip".utf8).write(to: desktopFolder.appendingPathComponent(".hidden"))
        let scanned = LibraryFlyoutFiles.scan(folders: [(.documents, documentsFolder), (.desktop, desktopFolder), (.screenshots, desktopFolder)])
        expect(Set(scanned.map(\.title)) == ["Screenshot 2026-10-30.png", "notes.txt"], "Folder scan lists visible files: \(scanned.map(\.title))")
        expect(scanned.contains { $0.title.hasPrefix("Screenshot") && $0.source == .screenshots && $0.isScreenshot },
               "A Desktop screenshot is also the Screenshots source")
        let listed = LibraryFlyoutFile(url: desktopFolder.appendingPathComponent("Screenshot 2026-10-30.png"),
                                       dateCreated: Date(timeIntervalSince1970: 10_000), isScreenshot: true, source: .desktop)
        entry.updateFlyoutFiles([listed])
        expect(flyout.rows.map(\.title) == ["Screenshot 2026-10-30.png"]
               && flyout.rows[0].accessibilityLabel == "File \u{2014} Screenshot 2026-10-30.png",
               "Folder files appear on the Library hover flyout")
        let fileID = flyout.rows[0].id
        var hovers = 0
        entry.onHover = { hovers += 1 }
        entry.pointerMoved(to: NSPoint(x: entry.buttonRect.midX, y: entry.buttonRect.midY))
        expect(hovers == 0, "Passing over the Library button doesn't ask for folders yet")
        clock.advance(0.16); clock.advance(0.16)
        expect(flyout.expanded && !flyout.animating, "Hover expands once folder files are present")
        expect(hovers == 1, "Settling on the Library button reports one hover: \(hovers)")
        entry.onHover = nil

        let promptSuite = "parc.library-entry-checks.folder-prompts"
        let promptDefaults = UserDefaults(suiteName: promptSuite)!
        promptDefaults.removePersistentDomain(forName: promptSuite)
        preferenceSuites.append(promptSuite)
        var probes: [@MainActor @Sendable () -> Void] = []
        let prompts = LibraryFolderPrompts(defaults: promptDefaults) { probes.append($0) }
        var started: [String] = []
        prompts.whenAnswered { started.append("first") }
        prompts.whenAnswered { started.append("second") }
        expect(!prompts.answered && started.isEmpty && probes.isEmpty, "Windows wait without reading Desktop or Documents")
        prompts.ask(); prompts.ask()
        expect(probes.count == 1 && prompts.asking && started.isEmpty, "Hovering twice asks macOS once and starts nothing early")
        probes[0]()
        expect(prompts.answered && !prompts.asking && started == ["first", "second"], "Every waiting window starts once the prompts are answered")
        prompts.ask()
        expect(probes.count == 1, "Answered prompts never probe again")
        let relaunched = LibraryFolderPrompts(defaults: promptDefaults) { probes.append($0) }
        relaunched.whenAnswered { started.append("launch") }
        expect(started.last == "launch" && probes.count == 1, "After the prompts are answered, windows start reading at launch")
        expect(entry.tapRow(fileID) && actions.last == "file:Screenshot 2026-10-30.png:open",
               "Tapping a folder file opens it")
        entry.pointerMoved(to: nil); clock.advance(1)
        entry.updateFlyoutFiles([])
        expect(flyout.rows.isEmpty, "Clearing folder files empties the flyout")

        let backdrop = publish("backdrop.iso", received: 20, date: 8_500)
        entry.updateFlyoutDownloads([backdrop], profiles: [profile], privateWindow: false)
        clock.advance(1)
        let front = publish("front.dmg", received: 60, date: 8_600)
        entry.updateFlyoutDownloads([backdrop, front], profiles: [profile], privateWindow: false)
        entry.updateFlyoutCaptures([capture("Recent", at: 8_700)])
        clock.advance(1); settle(0.5)
        expect(entry.model.visibleBadge == "download:" + front.id && flyout.rows.map(\.title) == ["Recent", "front.dmg", "backdrop.iso"]
               && entry.model.presentedSlot(in: flyout.rows, reduceMotion: false) == 1,
               "An older capture listed above keeps the new download visible, in the second slot")
        let cornerRect = NSRect(x: 34 - 16, y: 324 - 16, width: 32, height: 32)
        let frontCorner = entry.badge.convert(entry.badge.bounds, to: entry)
        expect(near(frontCorner, cornerRect, 0.5), "56 × 1 + 30 returns the second row's cell to the button's top-right: \(frontCorner)")
        let roles = DownloadBadgeColors(foreground: .systemPink, maxContrast: .systemGreen, cutout: .systemYellow)
        entry.badge.colors = roles
        entry.pointerMoved(to: buttonCentre); clock.advance(0.15); settle(0.6)
        let slots = flyout.rows.map { flyout.rowFrame($0.id) ?? .zero }
        let frontRow = entry.badge.convert(entry.badge.bounds, to: entry)
        let backdropRing = rings(in: entry.host).first { $0 !== entry.badge }
        expect(flyout.expanded && near(frontRow, NSRect(x: slots[1].minX + 4, y: slots[1].midY - 20, width: 40, height: 40), 0.5),
               "Expanded at (0, 0), the visible cell's renderer sits in the second row's thumbnail slot: \(frontRow)")
        expect(rings(in: entry.host).count == 2 && backdropRing?.activity?.identity == DownloadLibraryIdentity(backdrop)
               && backdropRing?.activity?.progress == 0.2 && backdropRing?.colors == roles,
               "The other running row draws its own renderer in the badge's palette roles")
        entry.pointerMoved(to: nil); clock.advance(0.01)
        expect(!flyout.expanded && entry.badge.activity?.identity == DownloadLibraryIdentity(front) && backdropRing?.activity != nil,
               "Collapsing: the visible renderer travels with its cell; the other row's renderer fades with its row")
        clock.advance(0.239)
        expect(backdropRing?.activity != nil, "…still drawing before 0.25 s")
        clock.advance(0.001)
        expect(backdropRing?.activity == nil && backdropRing?.subviews.isEmpty == true && entry.badge.activity != nil,
               "At 0.25 s, once the rows have faded, the other row's renderer retires; the visible one stays")
        settle(0.5)
        let frontBack = entry.badge.convert(entry.badge.bounds, to: entry)
        expect(near(frontBack, cornerRect, 0.5), "The visible cell is back at the button's top-right: \(frontBack)")
        entry.pointerMoved(to: buttonCentre); clock.advance(0.15)
        entry.pointerMoved(to: nil); clock.advance(0.1)
        entry.pointerMoved(to: buttonCentre); clock.advance(0.15)
        let reopenedRing = rings(in: entry.host).first { $0 !== entry.badge }
        expect(flyout.expanded && reopenedRing?.activity?.identity == DownloadLibraryIdentity(backdrop),
               "Expanding again within 0.25 s keeps the row's renderer")
        clock.advance(0.5)
        expect(reopenedRing?.activity != nil, "An earlier collapse's retirement never applies to a later expansion")
        entry.pointerMoved(to: nil); clock.advance(1); settle(0.3)
        SystemOverrides.reduceMotion = true
        entry.pointerMoved(to: buttonCentre)
        expect(entry.state.hovered && !entry.state.icon.isHovered, "Reduce Motion: hovering the entry leaves the box icon at rest")
        clock.advance(0.15); settle(0.6)
        let stillCorner = entry.badge.convert(entry.badge.bounds, to: entry)
        let rowRings = rings(in: entry.host).filter { $0 !== entry.badge }
        expect(flyout.expanded && flyout.reduceMotion && entry.model.presentedSlot(in: flyout.rows, reduceMotion: true) == nil
               && near(stillCorner, cornerRect, 0.5), "Reduce Motion: the visible cell stays at the button: \(stillCorner)")
        expect(Set(rowRings.compactMap { $0.activity?.identity }) == [DownloadLibraryIdentity(front), DownloadLibraryIdentity(backdrop)],
               "…and both running rows draw their own renderers, fading in place")
        entry.pointerMoved(to: nil); clock.advance(0.25)
        expect(!flyout.expanded && rowRings.allSatisfy { $0.activity == nil } && entry.badge.activity != nil,
               "Both rows' renderers retire once faded; the visible cell's stays")
        SystemOverrides.reduceMotion = false
        entry.updateFlyoutDownloads([], profiles: [profile], privateWindow: false)
        entry.updateFlyoutCaptures([])
        clock.advance(1)

        for isDark in [false, true] {
            let palette = ThemeChromePalette(theme: SpaceTheme(), isDark: isDark)
            let bin = DownloadBinBoxOfThingsItem(palette: palette)
            expect(bin.frame.size == NSSize(width: 32, height: 32) && bin.state.colors == .bin(maxContrast: palette.maxContrastColor),
                   "Bin item: 32 points, maxContrastColor on clear backgrounds")
            expect(bin.state.background == .clear && bin.state.foreground == palette.maxContrastColor && bin.state.enabled, "Enabled, clear, maxContrast")
            bin.state.hovered = true; bin.state.pressed = true
            expect(bin.state.background == .clear && bin.state.foreground == palette.maxContrastColor, "Hover and press keep it clear")
            bin.perform()
            expect(!bin.isAccessibilityElement() && !bin.acceptsFirstResponder, "No-op, decorative")
        }

        let late = publish("late.bin", date: 9_000)
        let lateDismissals = dismissals { entry.updateFlyoutDownloads([late], profiles: [profile], privateWindow: false) }
        expect(entry.model.visibleBadge != nil && entry.badge.activity != nil && lateDismissals.isEmpty, "Badged before closing")
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        expect(entry.lifecycle.visibleID == nil && entry.badge.activity == nil && entry.badge.subviews.isEmpty && entry.preview == nil,
               "Closing the window retires the item and its renderer")
        var lateDone = late; lateDone.status = .completed
        entry.updateFlyoutDownloads([late, lateDone], profiles: [profile], privateWindow: false)
        entry.updateFlyoutDownloads([late], profiles: [profile], privateWindow: false)
        expect(entry.lifecycle.visibleID == nil && entry.badge.activity == nil, "Late publications cannot badge a closed window")

        if let destination = ProcessInfo.processInfo.environment["PARC_LIBRARY_ENTRY_ACCEPTANCE"] {
            try acceptance(URL(fileURLWithPath: destination), store: store, profile: profile, publish: publish)
        }
        entry.removeFromSuperview(); window.close()
        print("Library entry checks passed: \(count)")
    }

    static func acceptance(_ directory: URL, store: BrowserStore, profile: UUID,
                           publish: (String, String, Int, Double) -> BrowserDownload) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func render(_ root: NSView, _ name: String, scale: CGFloat = 4) throws {
            root.layoutSubtreeIfNeeded(); CATransaction.flush()
            let size = root.bounds.size
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
            context.scaleBy(x: scale, y: scale)
            root.layer!.render(in: context)
            try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        }
        for isDark in [false, true] {
            let scheme = isDark ? "dark" : "light"
            let palette = ThemeChromePalette(theme: SpaceTheme(), isDark: isDark)
            func stage(_ size: NSSize) -> (NSWindow, NSView) {
                let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
                let root = NSView(frame: NSRect(origin: .zero, size: size)); root.wantsLayer = true
                window.appearance!.performAsCurrentDrawingAppearance { root.layer?.backgroundColor = palette.background.cgColor }
                window.contentView = root
                return (window, root)
            }
            let (window, root) = stage(NSSize(width: 120, height: 120))
            let dock = FlippedView(frame: root.bounds); dock.autoresizingMask = [.width, .height]; root.addSubview(dock)
            let entry = SidebarLibraryEntry()
            entry.preferences = freshPreferences()
            SystemOverrides.reduceMotion = false
            entry.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            dock.addSubview(entry)
            entry.place(button: SidebarChromeLayout.dockLeadingButton(height: dock.bounds.height))
            entry.badge.colors = DownloadBadgeColors(foreground: palette.foregroundPrimary, maxContrast: palette.maxContrastColor, cutout: palette.cutoutColor)
            settle(0.3)
            try render(root, "entry-\(scheme)-idle")
            let centre = NSPoint(x: entry.buttonRect.midX, y: entry.buttonRect.midY)
            entry.pointerMoved(to: centre); settle(1.0)
            try render(root, "entry-\(scheme)-hovered")
            entry.mouseDown(with: event(.leftMouseDown, centre, in: entry)); settle(0.6)
            try render(root, "entry-\(scheme)-pressed")
            entry.state.pressed = false
            entry.pointerMoved(to: nil); settle(1.0)
            let shotImage = NSImage(size: NSSize(width: 120, height: 80), flipped: false) { rect in
                NSGradient(starting: .systemIndigo, ending: .systemPink)!.draw(in: rect, angle: 30); return true
            }
            entry.flyout.imageLoader = { item, completion in
                completion(item.capture != nil ? shotImage : NSWorkspace.shared.icon(for: .pdf)); return {}
            }
            let item = publish("acceptance-\(scheme).pdf", "downloading", 65, 50)
            entry.updateFlyoutDownloads([item], profiles: [profile], privateWindow: false)
            settle(0.1)
            try render(root, "entry-\(scheme)-badge-landing")
            settle(1.0)
            try render(root, "entry-\(scheme)-badge")
            var done = item; done.status = .completed
            entry.updateFlyoutDownloads([done], profiles: [profile], privateWindow: false)
            settle(1.8)
            try render(root, "entry-\(scheme)-badge-completed")
            entry.updateFlyoutCaptures([SavedCapture(id: UUID(), revision: UUID(), profileID: profile, spaceID: UUID(), spaceName: "Space",
                title: "Release notes", sourceURL: "https://example.com/notes", createdAt: Date(), kind: .viewport, pixelWidth: 120, pixelHeight: 80)])
            settle(1.0)
            try render(root, "entry-\(scheme)-badge-capture")
            entry.updateFlyoutCaptures([])
            entry.updateFlyoutDownloads([], profiles: [profile], privateWindow: false); settle(0.5)
            try render(root, "entry-\(scheme)-after-badge")
            window.close()
            let (binWindow, binRoot) = stage(NSSize(width: 62, height: 62))
            let card = CALayer(); card.frame = binRoot.bounds.insetBy(dx: 8, dy: 8)
            card.cornerRadius = 12; card.cornerCurve = .continuous
            binWindow.appearance!.performAsCurrentDrawingAppearance { card.backgroundColor = palette.background.cgColor }
            card.shadowRadius = 12; card.shadowOffset = .zero; card.shadowOpacity = 1
            card.shadowColor = (isDark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.3)).cgColor
            binRoot.layer?.backgroundColor = (isDark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).cgColor
            binRoot.layer?.addSublayer(card)
            let bin = DownloadBinBoxOfThingsItem(palette: palette)
            bin.frame = NSRect(x: 15, y: 15, width: 32, height: 32)
            binRoot.addSubview(bin); settle(0.3)
            try render(binRoot, "entry-\(scheme)-bin")
            bin.pointerMoved(to: NSPoint(x: 16, y: 16)); settle(1.0)
            try render(binRoot, "entry-\(scheme)-bin-hovered")
            binWindow.close()
            try flyoutAcceptance(directory, scheme: scheme, palette: palette, isDark: isDark, store: store, profile: profile,
                                 publish: publish, stage: stage)
        }
    }

    static func flyoutAcceptance(_ directory: URL, scheme: String, palette: ThemeChromePalette, isDark: Bool, store: BrowserStore, profile: UUID,
                                 publish: (String, String, Int, Double) -> BrowserDownload,
                                 stage: (NSSize) -> (NSWindow, NSView)) throws {
        let size = NSSize(width: 260, height: 420), scale: CGFloat = 3
        func bitmap(_ root: NSView) -> NSBitmapImageRep {
            root.layoutSubtreeIfNeeded(); CATransaction.flush()
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
            context.scaleBy(x: scale, y: scale)
            root.layer!.render(in: context)
            return rep
        }
        func write(_ rep: NSBitmapImageRep, _ name: String) throws {
            try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
        }
        func icon(_ type: UTType) -> NSImage { NSWorkspace.shared.icon(for: type) }
        let captureImage = NSImage(size: NSSize(width: 120, height: 80), flipped: false) { rect in
            NSGradient(starting: .systemIndigo, ending: .systemPink)!.draw(in: rect, angle: 30)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: 12, y: 12, width: 60, height: 10), xRadius: 3, yRadius: 3).fill()
            NSBezierPath(roundedRect: NSRect(x: 12, y: 30, width: 90, height: 34), xRadius: 4, yRadius: 4).fill()
            return true
        }
        let base = Date().timeIntervalSince1970
        var movie = publish("flyout-trailer-\(scheme).mov", "downloading", 65, base - 20)
        movie.canCancel = true; movie.receivedBytes = 136_000_000; movie.totalBytes = 209_000_000
        let paper = publish("flyout-annual-report-\(scheme).pdf", "completed", 100, base - 600)
        let archive = publish("flyout-assets-\(scheme).zip", "completed", 100, base - 7_200)
        let shot = SavedCapture(id: UUID(), revision: UUID(), profileID: profile, spaceID: UUID(), spaceName: "Space",
                                title: "Release notes", sourceURL: "https://example.com/notes",
                                createdAt: Date(timeIntervalSince1970: base - 1_800), kind: .viewport, pixelWidth: 1200, pixelHeight: 800)
        for (variant, items, captures) in [("several", [movie, paper, archive], [shot]), ("single", [movie], [SavedCapture]())] {
            let (window, root) = stage(size)
            let content = FlippedView(frame: root.bounds); content.wantsLayer = true
            root.addSubview(content)
            for (index, title) in ["Inbox", "Calendar", "Q4 planning doc", "Design review", "Team standup notes", "Reading list"].enumerated() {
                let row = NSView(frame: NSRect(x: 8, y: 70 + CGFloat(index) * 40, width: size.width - 16, height: 34))
                row.wantsLayer = true; row.layer?.cornerRadius = 8
                window.appearance!.performAsCurrentDrawingAppearance {
                    row.layer?.backgroundColor = (index == 2 ? palette.hover : NSColor.clear).cgColor
                }
                let label = NSTextField(labelWithString: title)
                label.font = .systemFont(ofSize: 13); label.textColor = palette.foregroundPrimary
                label.frame = NSRect(x: 36, y: 8, width: size.width - 60, height: 18)
                let glyph = NSView(frame: NSRect(x: 10, y: 9, width: 16, height: 16)); glyph.wantsLayer = true
                glyph.layer?.cornerRadius = 4
                window.appearance!.performAsCurrentDrawingAppearance { glyph.layer?.backgroundColor = palette.foregroundTertiary.cgColor }
                row.addSubview(glyph); row.addSubview(label)
                content.addSubview(row)
            }
            let dock = FlippedView(frame: root.bounds); dock.autoresizingMask = [.width, .height]; root.addSubview(dock)
            let entry = SidebarLibraryEntry()
            entry.preferences = freshPreferences()
            SystemOverrides.reduceMotion = false
            entry.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            entry.flyout.imageLoader = { item, completion in
                switch item {
                case .capture: completion(captureImage)
                case .file: completion(icon(.png))
                case .download(let download): completion(icon(download.name.hasSuffix(".pdf") ? .pdf : .zip))
                }
                return {}
            }
            dock.addSubview(entry)
            entry.containerWidth = size.width
            entry.place(button: SidebarChromeLayout.dockLeadingButton(height: dock.bounds.height))
            entry.badge.colors = DownloadBadgeColors(foreground: palette.foregroundPrimary, maxContrast: palette.maxContrastColor, cutout: palette.cutoutColor)
            entry.updateFlyoutCaptures(captures)
            entry.updateFlyoutDownloads(items, profiles: [profile], privateWindow: false)
            entry.canExpand = true
            settle(1.2)
            let name = "flyout-\(scheme)-\(variant)"
            if variant == "several" { try write(bitmap(root), name + "-collapsed") }
            entry.pointerMoved(to: NSPoint(x: entry.buttonRect.midX, y: entry.buttonRect.midY))
            settle(1.2)
            precondition(entry.flyout.expanded, "The acceptance flyout expands")
            func composite(_ output: String) throws {
                let full = bitmap(root)
                content.isHidden = true; let bare = bitmap(root); content.isHidden = false
                let stops = LibraryFlyoutContentMask.locations(totalHeight: LibraryEntryLayout.totalHeight(count: entry.flyout.rows.count),
                                                               height: size.height, dockHeight: SidebarChromeLayout.dockHeight, inset: 0.04).map { CGFloat($0.doubleValue) }
                let alphas: [CGFloat] = LibraryFlyoutContentMask.expandedColors.map { $0.alpha }
                func alpha(_ t: CGFloat) -> CGFloat {
                    for index in 1..<stops.count where t <= stops[index] {
                        let span = stops[index] - stops[index - 1]
                        let f = span > 0 ? (t - stops[index - 1]) / span : 1
                        return alphas[index - 1] + (alphas[index] - alphas[index - 1]) * f
                    }
                    return alphas.last!
                }
                let width = full.pixelsWide, height = full.pixelsHigh, row = full.bytesPerRow
                let f = full.bitmapData!, b = bare.bitmapData!
                for y in 0..<height {
                    let m = alpha(1 - (CGFloat(y) + 0.5) / CGFloat(height))
                    for x in 0..<width * 4 { let i = y * row + x; f[i] = UInt8((CGFloat(f[i]) * m + CGFloat(b[i]) * (1 - m)).rounded()) }
                }
                try write(full, output)
            }
            try composite(name + "-expanded")
            if variant == "several", let running = entry.flyout.rows.first, let frame = entry.flyout.rowFrame(running.id) {
                entry.pointerMoved(to: NSPoint(x: frame.midX, y: frame.midY)); settle(0.6)
                try composite(name + "-expanded-hover")
            }
            entry.pointerMoved(to: nil); settle(0.3)
            entry.removeFromSuperview(); window.close()
        }
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }
@MainActor final class SavedBox { var value: SavedCapture? }
