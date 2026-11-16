import AppKit

@main @MainActor struct DownloadEntryChecks {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) { count += 1; precondition(value(), message) }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory), profile = store.state.profiles[0].id
        let path = store.independentEngineProfilePath(for: profile)
        func publish(_ id: String, status: String = "downloading", date: Double = 10, received: Int = 30, total: Int = 100, identity: String? = "live") -> BrowserDownload {
            var data: [String: Any] = ["id": id, "profilePath": path, "name": id, "status": status,
                "startedAt": date, "receivedBytes": received, "totalBytes": total, "available": identity != nil]
            data["itemIdentity"] = identity
            store.recordDownload(data)
            return store.state.downloads.first { $0.nativeID == id }!
        }
        let older = publish("older"), newest = publish("newest", date: 20, received: 60)
        let paused = publish("paused", status: "paused", date: 30)
        let profiles: Set<UUID> = [profile]
        expect(DownloadActivity.active(in: [paused, older, newest], profiles: profiles)?.name == "newest", "Newest active original wins, not collection order or paused row")
        expect(DownloadActivity.active(in: [older, newest], profiles: profiles)?.progress == 0.6, "Progress is one original item, not aggregate bytes")
        expect(DownloadActivity.active(in: [newest], profiles: []) == nil, "Retired profile contributes no entry activity")
        var sameDate = newest; sameDate.id = "a-same-date"; sameDate.name = "Second equal date"
        expect(DownloadActivity.active(in: [newest, sameDate], profiles: profiles)?.name == newest.name,
               "Equal creation dates preserve original provider order, not record-ID order")
        expect(DownloadActivity.active(in: [sameDate, newest], profiles: profiles)?.name == sameDate.name,
               "Reversing the original provider order reverses the equal-date winner")
        var metadata = newest; metadata.nativeIdentity = nil
        expect(DownloadActivity.active(in: [metadata], profiles: profiles) == nil, "Persisted metadata cannot animate as live work")
        var state = DownloadActivityState()
        _ = state.update([newest], profiles: profiles, now: 100)
        var complete = newest; complete.status = .completed
        expect(state.update([complete], profiles: profiles, now: 101)?.completed == true, "Original active-to-completed transition owns completion")
        expect(state.update([complete], profiles: profiles, now: 102)?.completed == true, "Ordinary repeat publication preserves original completion deadline")
        expect(state.update([complete], profiles: profiles, now: 102.46) == nil, "Completion expires after recovered 1.45 second timeline")
        expect(state.update([complete], profiles: profiles, now: 103) == nil, "Restored/completed rows never replay completion")
        _ = state.update([newest], profiles: profiles, now: 110)
        expect(state.update([complete, older], profiles: profiles, now: 111)?.name == "older", "Remaining actual active work takes priority over completion")
        var failed = older; failed.status = .failed
        expect(state.update([failed], profiles: profiles, now: 112) == nil, "Failure is never displayed as successful completion")
        _ = state.update([newest], profiles: profiles, now: 120)
        var replaced = complete; replaced.nativeIdentity = "replacement"
        expect(state.update([replaced], profiles: profiles, now: 121) == nil, "New incarnation cannot finish a retired item")
        let unknown = publish("unknown", date: 40, total: 0)
        expect(DownloadActivity.active(in: [unknown], profiles: profiles)?.progress == nil, "Unknown length is not invented percent")
        let overflow = publish("over", received: 200)
        expect(DownloadActivity.active(in: [overflow], profiles: profiles)?.progress == 1, "Published byte progress is clamped safely")
        let pending = publish("pending", status: "pending", date: 50, received: 0)
        expect(DownloadActivity.inFlight(in: [older, newest, paused, pending], profiles: profiles)?.name == "newest",
               "In flight is the newest in-progress download; newer paused and not-started ones do not count")
        expect(DownloadActivity.inFlight(in: [newest, older], profiles: profiles)?.progress == 0.6, "In-flight progress is that one item's bytes")
        expect(DownloadActivity.inFlight(in: [paused, pending], profiles: profiles) == nil
               && DownloadActivity.active(in: [paused, pending], profiles: profiles)?.name == "pending",
               "Paused and not-started downloads are never in flight, while the sidebar entry still badges not-started work")
        expect(DownloadActivity.inFlight(in: [metadata], profiles: profiles) == nil && DownloadActivity.inFlight(in: [newest], profiles: []) == nil,
               "Persisted metadata and retired profiles are never in flight")

        let badge = DownloadActivityBadge(frame: NSRect(x: 0, y: 0, width: 40, height: 56))
        let window = NSWindow(contentRect: badge.frame, styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSView(frame: badge.frame); window.contentView = host; host.addSubview(badge)
        defer { badge.reset(); window.contentView = nil }
        var changes = 0; badge.onChange = { _ in changes += 1 }
        badge.update([newest], profiles: profiles, enabled: true)
        expect(!badge.isHidden && badge.activity?.identity == DownloadLibraryIdentity(newest), "Actual attached badge projects original manager activity")
        badge.update([newest], profiles: profiles, enabled: true)
        expect(changes == 1, "Repeat publication does not restart presentation")
        expect(badge.hitTest(NSPoint(x: 20, y: 28)) == nil, "Decoration takes no input: the Library entry keeps the pointer")
        let firstRenderer = badge.subviews.first!
        var progressed = newest; progressed.receivedBytes = 80
        badge.update([progressed], profiles: profiles, enabled: true)
        expect(badge.subviews.count == 1 && badge.subviews.first === firstRenderer,
               "Original item progress updates the same native SwiftUI renderer")
        badge.colors = DownloadBadgeColors(foreground: .systemBlue, maxContrast: .systemBlue, cutout: .white)
        expect(badge.subviews.first === firstRenderer, "Palette publication preserves current animation owner")
        expect(!firstRenderer.isAccessibilityElement() && firstRenderer.accessibilityChildren()?.isEmpty == true && !badge.isAccessibilityElement(),
               "Renderer remains decoration, never a duplicate accessibility action")
        badge.setFrameSize(NSSize(width: 40, height: 40)); badge.layoutSubtreeIfNeeded()
        expect(firstRenderer.frame == badge.bounds, "Actual renderer remains centered in resized cell geometry")
        badge.colors = DownloadBadgeColors(foreground: .blue, maxContrast: .red, cutout: .green)
        badge.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let roles = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let rolesContext = NSGraphicsContext(bitmapImageRep: roles)!.cgContext
        rolesContext.scaleBy(x: 2, y: 2); firstRenderer.layer!.render(in: rolesContext)
        func sample(radius: CGFloat, degrees: CGFloat) -> NSColor {
            let angle = degrees * .pi / 180
            return roles.colorAt(x: Int((20 + radius * sin(angle)) * 2), y: Int((20 - radius * cos(angle)) * 2))!.usingColorSpace(.sRGB)!
        }
        func solid(_ c: NSColor, red: CGFloat, green: CGFloat) -> Bool {
            abs(c.redComponent - red) < 0.12 && abs(c.greenComponent - green) < 0.12 && c.alphaComponent > 0.9
        }
        let fill = sample(radius: 6, degrees: 270), stroke = sample(radius: 10.75, degrees: 90)
        let upper = sample(radius: 10.75, degrees: 330), lower = sample(radius: 10.75, degrees: 210)
        let upperTrack = solid(upper, red: 0.2, green: 0.8) && solid(lower, red: 1, green: 0)
        let lowerTrack = solid(lower, red: 0.2, green: 0.8) && solid(upper, red: 1, green: 0)
        let trackDegrees: CGFloat? = upperTrack ? 330 : lowerTrack ? 210 : nil
        var outlineAlphas: [CGFloat] = []
        if let degrees = trackDegrees {
            for radius in stride(from: 12 as CGFloat, through: 13, by: 0.25) {
                let c = sample(radius: radius, degrees: degrees)
                if c.blueComponent > 0.8 && c.redComponent < 0.2 && c.greenComponent < 0.2 { outlineAlphas.append(c.alphaComponent) }
            }
        }
        let outlined = outlineAlphas.contains { $0 > 0.2 } && outlineAlphas.allSatisfy { $0 < 0.6 }
        expect(solid(fill, red: 0, green: 1) && solid(stroke, red: 1, green: 0) && trackDegrees != nil && outlined,
               "Disc in cutoutColor, progress and 0.2 track in maxContrastColor, outline in foregroundPrimary at 0.5")
        expect(badge.subviews.first === firstRenderer, "Palette roles change on the same renderer")
        badge.layoutSubtreeIfNeeded()
        badge.update([complete], profiles: profiles, enabled: true)
        expect(badge.activity?.completed == true, "Native decoration receives genuine completion")
        expect(badge.subviews.first === firstRenderer, "Completion changes state on the original rendered item")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        expect(badge.subviews.first !== firstRenderer && firstRenderer.superview == nil,
               "Accessibility change retires the actual old repeating-animation tree")
        expect(badge.activity?.completed == true, "Accessibility refresh preserves original completion lifetime")
        let completionRenderer = badge.subviews.first!
        badge.update([complete], profiles: profiles, enabled: true)
        expect(badge.subviews.first === completionRenderer, "Repeated completion publication does not replay the animation")
        badge.update([older], profiles: profiles, enabled: true)
        expect(badge.activity?.name == "older" && completionRenderer.superview == nil && badge.subviews.first !== completionRenderer,
               "New original work retires the prior completion subtree")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        expect(badge.activity?.name == "older", "Old completion deadline cannot clear a replacement original item")
        var finishedOlder = older; finishedOlder.status = .completed
        badge.update([finishedOlder], profiles: profiles, enabled: true)
        let finishedRenderer = badge.subviews.first!
        badge.update([older], profiles: profiles, enabled: true)
        expect(badge.subviews.first !== finishedRenderer && finishedRenderer.superview == nil,
               "Reactivated original item receives a fresh visible arrow and uncancelled progress tree")
        badge.onChange = { value in if value?.completed == true { badge.reset() } }
        badge.update([finishedOlder], profiles: profiles, enabled: true)
        expect(badge.activity == nil && badge.subviews.isEmpty,
               "Synchronous owner retirement during completion publication cannot restart the renderer")
        badge.onChange = nil
        badge.update([older], profiles: profiles, enabled: false)
        expect(badge.isHidden && badge.activity == nil, "Private/closing owner clears entry state")
        badge.update([newest], profiles: profiles, enabled: true); badge.removeFromSuperview()
        expect(badge.activity == nil && badge.isHidden, "Native detach retires timer and item")
        badge.update([newest], profiles: profiles, enabled: true)
        expect(badge.activity == nil, "Detached updates cannot resurrect decoration")

        host.addSubview(badge); badge.update([newest], profiles: profiles, enabled: true)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        expect(badge.isHidden && badge.activity == nil, "Original window closing retires completion and activity without detach")
        badge.update([newest], profiles: profiles, enabled: true)
        expect(badge.activity == nil && badge.subviews.isEmpty, "Late native updates cannot resurrect a closed original window")
        let otherWindow = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        let otherHost = NSView(frame: host.frame); otherWindow.contentView = otherHost
        otherHost.addSubview(badge); badge.update([newest], profiles: profiles, enabled: true)
        expect(badge.activity?.identity == DownloadLibraryIdentity(newest),
               "A newly attached physical window can establish its own activity owner")
        badge.update([complete], profiles: profiles, enabled: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        expect(badge.activity == nil && badge.subviews.isEmpty && badge.isHidden,
               "Actual completion deadline retires the full native animation subtree")
        badge.removeFromSuperview(); otherWindow.contentView = nil

        let url = directory.appendingPathComponent("inert.png")
        var current: URL? = url
        let drag = DownloadFileDrag(resolve: { current })!
        expect(drag.item.types == [.fileURL], "File provider advertises only a real file URL, not fabricated bytes")
        current = nil
        drag.pasteboard(nil, item: drag.item, provideDataForType: .fileURL)
        expect(drag.item.string(forType: .fileURL) == nil, "Lost file admission publishes nothing")
        current = url
        let retired = DownloadFileDrag(resolve: { current })!
        retired.invalidate()
        retired.pasteboard(nil, item: retired.item, provideDataForType: .fileURL)
        expect(retired.item.string(forType: .fileURL) == nil, "Retired provider cannot reacquire its original file")
        expect(DownloadFileDrag(resolve: { URL(string: "https://example.invalid/file") }) == nil, "External URL is never offered as downloaded file")
        weak var releasedOwner: DownloadFileDrag?
        let retainedItem: NSPasteboardItem = {
            let owner = DownloadFileDrag(resolve: { url })!
            releasedOwner = owner
            return owner.item
        }()
        expect(releasedOwner == nil, "A retained pasteboard item cannot retain the Library drag owner")
        expect(retainedItem.string(forType: .fileURL) == nil, "Provider outliving its owner supplies no stale file")
        print("Download entry/file-provider checks passed: \(count)")
        if Bundle.main.object(forInfoDictionaryKey: "ParcEntryComponent") as? Bool == true {
            NSApp.setActivationPolicy(.regular)
            let preview = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 210),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            preview.isReleasedWhenClosed = false
            preview.title = "Downloads entry — inert component"
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 210))
            preview.contentView = root
            let heading = NSTextField(labelWithString: "Original item progress and completion")
            heading.font = .systemFont(ofSize: 15, weight: .medium)
            heading.frame = NSRect(x: 24, y: 164, width: 450, height: 22); root.addSubview(heading)
            let detail = NSTextField(labelWithString: "Synthetic manager records · no files or browser actions")
            detail.textColor = .secondaryLabelColor
            detail.frame = NSRect(x: 24, y: 135, width: 450, height: 20); root.addSubview(detail)
            var badges: [DownloadActivityBadge] = []
            for (index, amount) in [20, 60, 100].enumerated() {
                let column = CGFloat(index) * 150 + 32
                let cell = NSView(frame: NSRect(x: column, y: 62, width: 40, height: 56))
                root.addSubview(cell)
                let indicator = DownloadActivityBadge(frame: cell.bounds)
                cell.addSubview(indicator); badges.append(indicator)
                var item = newest; item.receivedBytes = Int64(amount)
                indicator.update([item], profiles: profiles, enabled: true)
                let label = NSTextField(labelWithString: "\(amount)%")
                label.frame = NSRect(x: column - 3, y: 44, width: 90, height: 20); root.addSubview(label)
            }
            preview.center(); preview.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                badges[2].update([complete], profiles: profiles, enabled: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
                badges.forEach { $0.reset() }; preview.close(); NSApp.terminate(nil)
            }
            NSApp.run()
        }
    }
}
