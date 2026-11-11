import AppKit

@main struct EaselPagePoolTests {
    @MainActor static var assertions = 0
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        assertions += 1; if !value() { fatalError(message) }
    }
    @MainActor static func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03)) }
    @MainActor static func browser(in view: NSView) -> PCBrowserView? {
        if let browser = view as? PCBrowserView { return browser }
        return view.subviews.lazy.compactMap { browser(in: $0) }.first
    }
    @MainActor static func crossProfileRetirement(captured: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-profile-pool-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceStore = try EaselStore(directory: directory.appendingPathComponent("source"))
        let targetStore = try EaselStore(directory: directory.appendingPathComponent("target"))
        let original = try sourceStore.create()
        var item = EaselItem(kind: .browser, frame: .init(x: 0, y: 0, width: 480, height: 320), url: "https://fixture.invalid/original")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        if captured {
            item.kind = .webCard; item.assetID = try original.importPNG(png)
            item.captureLayout = EaselCaptureLayout(viewport: .init(x: 1000, y: 700), scroll: .init(x: 10, y: 300),
                region: .init(x: 20, y: 40, width: 300, height: 200))
            item.capturedAt = Date(timeIntervalSince1970: 42); item.liveCapture = true
        }
        try original.perform("Seed") { $0.items = [item] }
        let sourceWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let targetWindow = NSWindow(contentRect: sourceWindow.frame, styleMask: [.titled], backing: .buffered, defer: false)
        sourceWindow.isReleasedWhenClosed = false; targetWindow.isReleasedWhenClosed = false
        defer { sourceWindow.close(); targetWindow.close() }
        let sourceBinding = PCNativeBrowserWindow(sourceWindow), targetBinding = PCNativeBrowserWindow(targetWindow)
        let canvas = EaselCanvasView(session: original); sourceWindow.contentView = canvas
        let pool = EaselBrowserObjects(session: original, canvas: canvas, binding: sourceBinding, profilePath: "/fixture/source-profile",
            validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: {})
        canvas.layoutSubtreeIfNeeded()
        let surface = pool.surface(for: item)!
        if surface.superview == nil { canvas.addSubview(surface) }
        surface.frame = NSRect(x: 0, y: 0, width: 480, height: 320); surface.layoutSubtreeIfNeeded()
        let wrapper = browser(in: surface)!
        do { try sourceStore.retireSessionForRelocation(original.document.id); fatalError("pending child retired") }
        catch { expect(!original.isClosed, "Pending child creation keeps its source session writable and owned") }
        let oldPage = PCNativePage(); oldPage.owner = sourceBinding; wrapper.request!.reply(oldPage)
        canvas.selectBrowserObject(item.id)
        do { try sourceStore.retireSessionForRelocation(original.document.id); fatalError("live child retired") }
        catch { expect(pool.pages.first === oldPage, "Live source child cannot be bypassed by durable relocation") }
        oldPage.isClosed = true; pool.didClose(oldPage); pool.disposeAfterClosure()
        try sourceStore.retireSessionForRelocation(original.document.id)
        expect(!canvas.canFinishEditingForTransfer, "Retired source canvas cannot authorize another transfer")
        _ = try sourceStore.relocate(original.document.id, to: targetStore)
        let arrived = try targetStore.load(original.document.id)
        let destinationCanvas = EaselCanvasView(session: arrived); targetWindow.contentView = destinationCanvas
        let destinationPool = EaselBrowserObjects(session: arrived, canvas: destinationCanvas, binding: targetBinding,
            profilePath: "/fixture/target-profile", validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: {})
        destinationCanvas.layoutSubtreeIfNeeded()
        let destinationSurface = destinationPool.surface(for: arrived.document.items[0])!
        if destinationSurface.superview == nil { destinationCanvas.addSubview(destinationSurface) }
        destinationSurface.frame = surface.frame; destinationSurface.layoutSubtreeIfNeeded()
        let targetWrapper = browser(in: destinationSurface)!
        expect(targetWrapper !== wrapper && targetWrapper.profilePath == "/fixture/target-profile", "Destination creates its own wrapper with the exact new Profile")
        expect(targetWrapper.requestedURL?.absoluteString == item.url && targetWrapper.creations == 1,
               "Durable original URL admits exactly one fresh destination request")
        let newPage = PCNativePage(); newPage.owner = targetBinding; targetWrapper.request!.reply(newPage)
        expect(newPage !== oldPage && destinationPool.pages.first === newPage && pool.pages.isEmpty,
               "No original WebContents/session identity crosses Profiles")
        expect(arrived.document == original.document && arrived !== original && original.isClosed,
               "Durable object identity survives while the retained source editor remains revoked")
        surface.needsLayout = true; surface.layoutSubtreeIfNeeded(); pool.refreshVisibility()
        expect(wrapper.creations == 1 && wrapper.loads == 0 && pool.selectedPage == nil,
               "Retained source surface cannot reconstruct or replay the retired page")
        newPage.isClosed = true; destinationPool.didClose(newPage); destinationPool.disposeAfterClosure()
        if captured {
            expect(try! arrived.assetData(item.assetID!) == png, "Live capture relocation preserves its original screenshot bytes")
            try arrived.perform("Pause capture") { $0.items[0].liveCapture = false }
            try targetStore.retireSessionForRelocation(arrived.document.id)
            _ = try targetStore.relocate(arrived.document.id, to: sourceStore)
            let paused = try sourceStore.load(arrived.document.id)
            let pausedCanvas = EaselCanvasView(session: paused); sourceWindow.contentView = pausedCanvas
            let pausedPool = EaselBrowserObjects(session: paused, canvas: pausedCanvas, binding: sourceBinding,
                profilePath: "/fixture/source-profile", validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: {})
            pausedCanvas.layoutSubtreeIfNeeded()
            expect(paused.document.items[0].captureLayout == item.captureLayout && paused.document.items[0].liveCapture == false,
                   "A paused capture keeps its actual durable geometry/preference in the other Profile")
            expect(pausedPool.surface(for: paused.document.items[0]) == nil && pausedPool.pages.isEmpty && !pausedPool.hasPendingCreation,
                   "A paused capture does not silently create live destination content")
            pausedPool.disposeAfterClosure()
        }
    }

    @MainActor static func exportSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-export-pool-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try EaselStore(directory: directory).create()
        let item = EaselItem(kind: .browser, frame: .init(x: 40, y: 20, width: 480, height: 320), url: "https://fixture.invalid/original")
        let second = EaselItem(kind: .browser, frame: .init(x: 40, y: 400, width: 300, height: 200), url: "https://fixture.invalid/second")
        let unplaced = EaselItem(kind: .browser, frame: .init(x: 400, y: 400, width: 300, height: 200), url: "https://fixture.invalid/unplaced")
        try session.perform("Seed") { $0.items = [item, second, unplaced] }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let binding = PCNativeBrowserWindow(window)
        let canvas = EaselCanvasView(session: session); window.contentView = canvas
        let pool = EaselBrowserObjects(session: session, canvas: canvas, binding: binding, profilePath: "/fixture/profile",
            validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: {})
        canvas.layoutSubtreeIfNeeded()
        func livePage(for object: EaselItem, frame: NSRect) -> PCNativePage {
            let surface = pool.surface(for: object)!
            if surface.superview == nil { canvas.addSubview(surface) }
            surface.frame = NSRect(x: 0, y: 0, width: 300, height: 200); surface.needsLayout = true; surface.layoutSubtreeIfNeeded()
            let page = PCNativePage(); page.owner = binding; browser(in: surface)!.request!.reply(page)
            surface.frame = frame; surface.needsLayout = true; surface.layoutSubtreeIfNeeded()
            return page
        }
        let page = livePage(for: item, frame: NSRect(x: 40, y: 20, width: 480, height: 320))
        let secondPage = livePage(for: second, frame: NSRect(x: 40, y: 400, width: 300, height: 200))
        let unplacedPage = livePage(for: unplaced, frame: .zero)
        page.snapshotImage = NSImage(size: NSSize(width: 480, height: 288), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill(); rect.fill(); return true
        }
        unplacedPage.snapshotImage = page.snapshotImage
        func collect() -> [UUID: EaselPageSnapshot]? {
            var collected: [UUID: EaselPageSnapshot]?
            expect(canvas.collectExportPages { collected = $0 }, "An idle canvas starts collecting its live pages")
            if collected == nil {
                expect(!canvas.collectExportPages { _ in fatalError("second collection") }, "A second export waits for the first collection")
            }
            drain(); return collected
        }
        func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
            let data = Array(image.dataProvider!.data! as Data), i = y * image.bytesPerRow + x * 4
            return Array(data[i..<i + 3])
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { NSApp.appearance = nil }
        guard let pages = collect(), let snapshot = pages[item.id] else { fatalError("No live page snapshot was collected") }
        expect(page.snapshotRequests == 1 && snapshot.pageFrame == NSRect(x: 0, y: 32, width: 480, height: 288)
               && snapshot.visibleFrame == snapshot.pageFrame, "The snapshot keeps the page's place below the surface's control strip")
        expect(secondPage.snapshotRequests == 1 && pages[second.id] == nil && pages.count == 1,
               "A reply without pixels leaves that object to its card while the others export")
        expect(unplacedPage.snapshotRequests == 0, "A surface with no page frame is never asked and keeps its card")
        let live = canvas.exportImage(backingScale: 1, pages: pages)!
        expect(pixel(live, 280, 200) == [255, 0, 0], "The export draws the page's own pixels")
        expect(pixel(live, 280, 30) == [255, 255, 255], "The control strip exports as the surface's paper, without its controls")

        secondPage.refusesSnapshot = true
        let refused = collect()
        expect(secondPage.snapshotRequests == 2 && refused?[item.id] != nil && refused?[second.id] == nil,
               "An engine NO for one page still completes with the others")

        secondPage.refusesSnapshot = false; secondPage.withholdsSnapshot = true
        var deliveries = 0, late: [UUID: EaselPageSnapshot]?
        pool.exportSnapshots(within: 0.2) { deliveries += 1; late = $0 }
        drain()
        expect(deliveries == 0 && secondPage.withheldSnapshot != nil, "The collection waits for an outstanding page")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        expect(deliveries == 1 && late?[item.id] != nil && late?[second.id] == nil, "The deadline completes with what has arrived")
        secondPage.withheldSnapshot?(PCNativePageCaptureResult(image: page.snapshotImage)); drain()
        expect(deliveries == 1, "A reply after the deadline is ignored")
        secondPage.withholdsSnapshot = false

        for each in [page, secondPage, unplacedPage] { each.supportsSnapshot = false }
        let older = collect()
        expect(older?.isEmpty == true && page.snapshotRequests == 3, "An engine without the snapshot is never asked")
        let card = canvas.exportImage(backingScale: 1, pages: older ?? [:])!
        expect(pixel(card, 280, 200) != [255, 0, 0], "Without it the export keeps the webpage card")
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-pool-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EaselStore(directory: directory), session = try store.create()
        let item = EaselItem(kind: .browser, frame: .init(x: 0, y: 0, width: 480, height: 320), url: "https://fixture.invalid/original")
        try session.perform("Seed") { $0.items = [item] }
        let sourceWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let targetWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        sourceWindow.isReleasedWhenClosed = false; targetWindow.isReleasedWhenClosed = false
        defer { sourceWindow.close(); targetWindow.close() }
        let source = PCNativeBrowserWindow(sourceWindow), target = PCNativeBrowserWindow(targetWindow)
        let canvas = EaselCanvasView(session: session)
        sourceWindow.contentView = canvas
        var originalMetadata = 0, targetMetadata = 0
        let pool = EaselBrowserObjects(session: session, canvas: canvas, binding: source, profilePath: "/fixture/profile",
            validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: { originalMetadata += 1 })
        canvas.layoutSubtreeIfNeeded()
        let surface = pool.surface(for: item)!
        if surface.superview == nil { canvas.addSubview(surface) }
        surface.frame = NSRect(x: 0, y: 0, width: 480, height: 320); surface.layoutSubtreeIfNeeded()
        let wrapper = browser(in: surface)!
        expect(wrapper.request != nil && wrapper.creations == 1, "Real pool issues exactly one admitted request to the injected boundary")
        expect(pool.snapshotForWindowTransfer() == nil, "Pending native creation refuses the whole pool")
        let page = PCNativePage(); page.owner = source; wrapper.request!.reply(page)
        canvas.selectBrowserObject(item.id)
        drain()
        expect(pool.selectedPage === page, "Existing selection retains the injected original page")
        wrapper.addSubview(page.nativeView)
        expect(pool.focusPage(for: item.id) && sourceWindow.firstResponder === page.nativeView, "Keyboard entry focuses the actual retained native page")
        let crash = PCNativeRendererCrash(); page.rendererCrash = crash
        pool.browserView(wrapper, didChangeRendererCrash: crash)
        expect(pool.focusPage(for: item.id) && (sourceWindow.firstResponder as? NSButton)?.title == crash.actionTitle,
               "A selected crashed page enters its existing recovery button, never its unusable native renderer")
        page.rendererCrash = nil; pool.browserView(wrapper, didChangeRendererCrash: nil)
        expect(pool.focusPage(for: item.id) && sourceWindow.firstResponder === page.nativeView,
               "Clearing genuine recovery state restores entry to the same native page")
        expect(pool.accessibilitySurface(for: item.id) === surface && !EaselBrowserObjects.excludesFromKeyboardNavigation(surface), "Selected original surface admits native control and AX traversal")
        let unchanged = session.document
        let delete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: sourceWindow.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        canvas.keyDown(with: delete)
        expect(session.document == unchanged, "Unhandled native page Delete cannot remove canvas objects")
        surface.cancelOperation(nil)
        expect(sourceWindow.firstResponder === canvas, "Return action restores original canvas first responder")
        expect(pool.selectedPage == nil, "Return action removes original page interaction")
        expect(pool.accessibilitySurface(for: item.id) == nil && EaselBrowserObjects.excludesFromKeyboardNavigation(surface), "Unselected page is excluded from AX controls and native key loop")
        canvas.selectBrowserObject(item.id)
        expect(wrapper.creations == 1 && wrapper.loads == 0, "Entry and return never recreate or navigate the page")
        page.embeddedOwnerValid = false
        expect(!pool.focusPage(for: item.id) && pool.accessibilitySurface(for: item.id) == nil && EaselBrowserObjects.excludesFromKeyboardNavigation(surface), "Revoked native ownership refuses page focus and control traversal")
        page.embeddedOwnerValid = true
        page.nativeView.removeFromSuperview()
        expect(!pool.focusPage(for: item.id), "A detached live page cannot report recovery-control focus as successful page entry")
        wrapper.addSubview(page.nativeView)
        let snapshot = pool.snapshotForWindowTransfer()!
        expect(snapshot.pages.values.first === page && snapshot.views.values.first === wrapper, "Snapshot captures original page and wrapper identities")
        expect(pool.beginWindowTransfer(snapshot), "Original window starts transfer once")
        expect(!pool.beginWindowTransfer(snapshot), "Second entry into the same transfer is refused")
        expect(pool.selectedPage == nil && pool.visiblePages.isEmpty, "Transfer suspends page input and visibility publication")
        expect(!pool.focusPage(for: item.id) && pool.accessibilitySurface(for: item.id) == nil, "Transfer also revokes keyboard/AX entry")
        expect(pool.snapshotForWindowTransfer() == nil, "No competing snapshot is admitted")
        surface.needsLayout = true; surface.layoutSubtreeIfNeeded()
        expect(wrapper.creations == 1 && wrapper.loads == 0, "Layout does not create or replay the original page")
        var replacement = session.document; replacement.items.removeAll()
        var accepted: Bool?
        pool.prepareReplacement(replacement, valid: { true }) { accepted = $0 }
        expect(accepted == false && PCNativeBrowserApplication.closeCalls == 0, "Shared destructive replacement cannot race transfer with a second close")
        do { try session.perform("Invalid replacement") { $0.items.removeAll() }; fatalError("live child deletion accepted") }
        catch { expect(session.document.items == [item], "Actual shared-session replacement guard retains live child") }
        let unrelated = EaselItem(kind: .rectangle, frame: .init(x: 500, y: 0, width: 20, height: 20))
        try session.perform("Other content") { $0.items.append(unrelated) }
        expect(pool.isCurrent(snapshot), "Unrelated shared document edits preserve original snapshot")
        func rebind(_ binding: PCNativeBrowserWindow, path: String = "/fixture/profile") -> Bool {
            pool.rebindWindowTransfer(snapshot, binding: binding, profilePath: path, validOwner: { true },
                activeOwner: { true }, selectionChanged: {}, metadataChanged: { targetMetadata += 1 })
        }
        expect(!rebind(target), "A destination lease cannot precede actual view/window movement")
        targetWindow.contentView = canvas
        expect(!rebind(target), "Moving AppKit views alone cannot claim a native page")
        page.owner = target
        expect(!rebind(target, path: "/another/profile"), "Profile substitution refuses the same page")
        page.embeddedOwnerValid = false
        expect(!rebind(target), "Revoked native auxiliary lease refuses rebind")
        page.embeddedOwnerValid = true
        expect(rebind(target), "Same original page and actual target window permit explicit rebind")
        expect(pool.finishWindowTransfer(snapshot), "Accepted rebind settles the exact pool")
        pool.refreshVisibility()
        expect(pool.selectedPage === page && pool.pages.first === page, "Original selection and page survive transfer")
        expect(wrapper.window === targetWindow && wrapper.creations == 1 && wrapper.loads == 0, "Original wrapper moved without creation/navigation")
        expect(!pool.beginWindowTransfer(snapshot), "Consumed transfer snapshot cannot be replayed")
        drain(); let oldMetadata = originalMetadata
        pool.browserView(wrapper, didChangeTitle: "Original")
        drain()
        expect(originalMetadata == oldMetadata && targetMetadata > 0, "Metadata follows new original-window callback owner")
        let rollback = pool.snapshotForWindowTransfer()!
        expect(pool.beginWindowTransfer(rollback), "Next real move obtains a fresh snapshot")
        expect(pool.rebindWindowTransfer(rollback, binding: target, profilePath: "/fixture/profile",
            validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: {}), "Rollback preserves current owner rather than recreating it")
        expect(pool.finishWindowTransfer(rollback), "Refused transfer releases the original pool gate")
        let closing = pool.snapshotForWindowTransfer()!
        expect(pool.beginWindowTransfer(closing), "Last original snapshot admitted")
        page.isClosed = true; pool.didClose(page)
        expect(pool.isCurrent(closing, checkingDocument: false), "Actual page destruction is explicitly accountable")
        try session.perform("Delete closed original") { $0.items.removeAll { $0.id == item.id } }
        expect(!session.document.items.contains { $0.id == item.id }, "Genuinely closed child permits ordinary shared document deletion")
        expect(pool.canFinishWindowTransfer(closing), "Removed closed entry still drains its captured identity")
        expect(pool.finishWindowTransfer(closing), "Closed child can drain without orphaned gate")
        pool.disposeAfterClosure()
        expect(pool.snapshotForWindowTransfer() == nil, "Disposed owner never returns a new capability")
        expect(wrapper.creations == 1 && wrapper.loads == 0, "All accepted/refused paths preserve one original creation")
        try liveCaptures(store: store)
        try crossProfileRetirement(captured: false)
        try crossProfileRetirement(captured: true)
        try exportSnapshots()
        print("EaselPagePool: \(assertions) assertions passed (real pool/AppKit/session, injected engine replies; no browser)")
    }
    @MainActor static func liveCaptures(store: EaselStore) throws {
        let session = try store.create(title: "Captured region")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let asset = try session.importPNG(png)
        let layout = EaselCaptureLayout(viewport: .init(x: 1000, y: 700), scroll: .init(x: 10, y: 300),
            region: .init(x: 20, y: 40, width: 300, height: 200))
        let item = EaselItem(kind: .webCard, frame: .init(x: 0, y: 0, width: 480, height: 320),
            url: "https://fixture.invalid/captured", assetID: asset, captureLayout: layout, liveCapture: true)
        try session.perform("Seed capture") { $0.items = [item] }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let binding = PCNativeBrowserWindow(window), canvas = EaselCanvasView(session: session)
        window.contentView = canvas
        let pool = EaselBrowserObjects(session: session, canvas: canvas, binding: binding, profilePath: "/fixture/profile",
            validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: {})
        canvas.layoutSubtreeIfNeeded()
        let surface = pool.surface(for: item)!
        if surface.superview == nil { canvas.addSubview(surface) }
        surface.frame = NSRect(x: 0, y: 0, width: 480, height: 320); surface.layoutSubtreeIfNeeded()
        let wrapper = surface.subviews.flatMap(\.subviews).compactMap { $0 as? PCBrowserView }.first!
        expect(wrapper.creations == 1 && pool.hasPendingCreation, "Live capture owns an actual pending auxiliary request")
        let page = PCNativePage(); page.owner = binding; wrapper.request!.reply(page)
        canvas.selectBrowserObject(item.id); surface.needsLayout = true; surface.layoutSubtreeIfNeeded(); drain()
        expect(pool.pages.first === page && pool.selectedPage === page, "Live card participates in page selection and closure ownership")
        expect(page.positions.last?.0 == NSRect(x: 20, y: 40, width: 300, height: 200) && page.positions.last?.1 == NSPoint(x: 10, y: 300),
            "Positioning consumes the original crop and document offset")
        expect(wrapper.frame.size == NSSize(width: 1000, height: 700), "Original viewport preserves page layout independent of card size")
        expect(pool.snapshotForWindowTransfer()?.pages.values.first === page, "Live region is included in whole-window child transfer")
        page.url = URL(string: "https://fixture.invalid/later")
        pool.browserView(wrapper, didChangeURL: page.url!)
        expect(session.document.items[0].url == item.url, "Live navigation never overwrites immutable capture provenance")
        pool.browserView(wrapper, didChangeLoading: false, canGoBack: false, canGoForward: false); drain()
        let stablePositions = page.positions.count
        pool.browserView(wrapper, didChangeLoading: false, canGoBack: false, canGoForward: false); drain()
        expect(page.positions.count == stablePositions, "Unchanged native metadata never resets live-page interaction or scroll")
        let priorPositions = page.positions.count
        surface.frame.size.width = 600; surface.needsLayout = true; surface.layoutSubtreeIfNeeded(); drain()
        expect(wrapper.creations == 1 && wrapper.loads == 0, "Resize preserves the same live page without URL replay")
        expect(page.positions.count >= priorPositions, "Resize remains within the same positioning owner")
        let destination = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        destination.isReleasedWhenClosed = false; defer { destination.close() }
        let destinationBinding = PCNativeBrowserWindow(destination)
        page.delayPositions = true
        pool.browserView(wrapper, didChangeLoading: true, canGoBack: false, canGoForward: false)
        pool.browserView(wrapper, didChangeLoading: false, canGoBack: false, canGoForward: false)
        let pending = page.positionRequests.last!, staleReply = page.positionReplies.last!
        let moving = pool.snapshotForWindowTransfer()!
        expect(pool.beginWindowTransfer(moving) && pending.cancelled, "Transfer cancels pending source-window positioning")
        let beforeMovePositions = page.positions.count
        surface.needsLayout = true; surface.layoutSubtreeIfNeeded()
        expect(page.positions.count == beforeMovePositions, "Transfer gate prevents layout from restarting source positioning")
        destination.contentView = canvas; page.owner = destinationBinding
        expect(pool.rebindWindowTransfer(moving, binding: destinationBinding, profilePath: "/fixture/profile",
            validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: {}), "Live capture rebinds only its original page at destination")
        expect(pool.finishWindowTransfer(moving), "Live capture transfer settles")
        pool.refreshVisibility(); surface.layoutSubtreeIfNeeded()
        expect(page.positions.count == beforeMovePositions + 1, "Same-size destination retries suspended original region positioning")
        let status = surface.subviews.compactMap { $0 as? NSTextField }.first!
        expect(status.stringValue == "Positioning live capture…" && !status.isHidden, "Destination exposes its own pending positioning status")
        staleReply(false); drain()
        expect(page.positions.count == beforeMovePositions + 1 && status.stringValue == "Positioning live capture…" && !status.isHidden,
            "Late source positioning callback cannot replace destination work or its status")
        page.positionReplies.last!(true); drain()
        expect(status.isHidden && status.stringValue.isEmpty, "Only current successful reply reveals the live region")
        let completedCount = page.positions.count
        let rollback = pool.snapshotForWindowTransfer()!
        expect(pool.beginWindowTransfer(rollback), "Completed live region begins next transfer")
        expect(pool.rebindWindowTransfer(rollback, binding: destinationBinding, profilePath: "/fixture/profile",
            validOwner: { true }, activeOwner: { true }, selectionChanged: {}, metadataChanged: {}), "Refused movement rebinds same original owner")
        expect(pool.finishWindowTransfer(rollback), "Rollback settles completed live region")
        pool.refreshVisibility(); surface.layoutSubtreeIfNeeded()
        expect(page.positions.count == completedCount, "Completed live page is not reset by a transfer rollback")
        PCNativeBrowserApplication.closeAllowed = false
        canvas.setLiveCapture(item.id, enabled: false)
        expect(session.document.items[0].liveCapture == true && !page.isClosed, "Refused real close preserves live mode and original page")
        PCNativeBrowserApplication.closeAllowed = true
        canvas.setLiveCapture(item.id, enabled: false); drain()
        expect(page.isClosed && session.document.items[0].liveCapture == false, "Snapshot commits only after actual child retirement")
        expect(session.document.items[0].assetID == asset && (try! session.assetData(asset)) == png,
            "Live transitions preserve exact immutable captured PNG")
        expect(pool.pages.isEmpty && !pool.hasPendingCreation, "Retired live capture leaves no orphaned child")
        pool.disposeAfterClosure()
    }

}
