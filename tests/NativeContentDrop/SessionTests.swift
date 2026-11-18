import AppKit

@MainActor class LayoutView: NSView { override var isFlipped: Bool { true } }
@MainActor enum SidebarSplitDrag { static let pasteboardType = NSPasteboard.PasteboardType("org.parc.sidebar-split-drag") }
@MainActor enum SidebarMoveSession { static let pasteboardType = NSPasteboard.PasteboardType("org.parc.sidebar-item-move") }

@MainActor final class Drag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation = NSPoint(x: 40, y: 40)
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any? { nil }
    var draggingSequenceNumber = 7
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight = NSSpringLoadingHighlight.none
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    var items: [NSDraggingItem] = []
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for (index, item) in items.enumerated() where !classArray.isEmpty { block(item, index, &stop); if stop.boolValue { break } }
    }
    func resetSpringLoading() {}
}

@MainActor final class ReservedPane: NSView {
    let body = NSView()
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; addSubview(body)
        body.autoresizingMask = [.width, .height]
        body.frame = NSRect(x: 0, y: 40, width: frame.width, height: max(0, frame.height - 40))
    }
    required init?(coder: NSCoder) { fatalError() }
}
@MainActor final class ReservedHost: NSView { override var isFlipped: Bool { true } }
extension ReservedPane: SplitLayoutFollowing {
    static var followed: [(NSView, CGRect, CFTimeInterval)] = []
    static var cancelled = 0
    func followSplitLayout(from previous: CGRect, animation: CAAnimation) { Self.followed.append((self, previous, animation.duration)) }
    func cancelSplitLayoutFollow() { Self.cancelled += 1 }
}

@main @MainActor struct SessionTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ reason: String) {
        count += 1; precondition(value(), reason)
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 200,height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let host = NSView(frame: NSRect(x: 0,y: 0,width: 200,height: 200)); window.contentView = host
        let ink = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let drag = Drag(); drag.draggingDestinationWindow = window
        let pb = drag.draggingPasteboard; defer { pb.releaseGlobally() }
        func write(_ types: [(NSPasteboard.PasteboardType, String)]) {
            pb.clearContents(); let item = NSPasteboardItem(); for (type, value) in types { item.setString(value, forType: type) }; pb.writeObjects([item])
        }
        write([(.URL, "https://native.invalid/original?plus=a+b"),(.string,"https://fallback.invalid")])
        check(ExternalSplitDropSession.readURL(pb)?.host == "native.invalid", "public URL has precedence")
        write([(.string,"https://string.invalid")]); check(ExternalSplitDropSession.readURL(pb)?.host == "string.invalid", "single literal string fallback")
        write([(.fileURL,"file:///tmp/test"),(.URL,"https://native.invalid")]); check(ExternalSplitDropSession.readURL(pb) == nil,"file drag remains native renderer owned")
        write([(SidebarMoveSession.pasteboardType,"opaque"),(.URL,"https://native.invalid")]); check(ExternalSplitDropSession.readURL(pb) == nil,"original internal item retains move owner")
        pb.clearContents(); let one=NSPasteboardItem(),two=NSPasteboardItem(); one.setString("https://one.invalid",forType:.URL);two.setString("https://two.invalid",forType:.URL);pb.writeObjects([one,two]);check(ExternalSplitDropSession.readURL(pb)==nil,"plural payload is not silently reduced")
        write([(.URL,"https://native.invalid")]); var valid=true, commits=0
        func session(_ commitResult: Bool = true) -> ExternalSplitDropSession {
            ExternalSplitDropSession(host:host,info:drag,frames:[host.bounds],orientation:.horizontal,validate:{valid},insertionColor:{.black},canPropose:{_,_ in true},commit:{_,_ in commits += 1;return commitResult})!
        }
        let first=session(); check(first.update(drag) == .copy,"real preview admitted");check(host.subviews.isEmpty,"session adds no overlay to the original host")
        valid=false;check(first.update(drag).isEmpty && !first.perform(drag) && commits==0,"expired owner cannot commit");check(host.subviews.isEmpty,"expired session leaves the host unchanged")
        valid=true;let changed=session();write([(.URL,"https://replacement.invalid")]);check(changed.update(drag).isEmpty && !changed.perform(drag),"changed pasteboard cannot retarget")
        let oneShot=session();check(oneShot.perform(drag) && commits==1,"one real commit");check(!oneShot.perform(drag) && commits==1 && host.subviews.isEmpty,"consumed session never repeats")
        let refused=session(false);check(!refused.perform(drag) && commits==2,"actual model failure returned")
        let escaped=session();escaped.end();check(!escaped.perform(drag) && commits==2,"exit is cancellation")
        var proposals: [SplitDropTarget?] = []
        func trackedSession() -> ExternalSplitDropSession {
            ExternalSplitDropSession(host:host,info:drag,frames:[host.bounds],orientation:.horizontal,validate:{true},insertionColor:{.black},canPropose:{_,_ in true},commit:{_,_ in true})!
        }
        let tracked = trackedSession(); tracked.targets.performFeedback = {}
        tracked.targets.onChange = { proposals.append($0) }
        drag.draggingLocation = NSPoint(x: 100, y: 100)
        check(tracked.update(drag) == .copy && proposals == [.replace(0)], "admitted URL publishes its replacement")
        check(tracked.perform(drag) && proposals.last == .some(nil), "perform clears the proposal before commit")
        let cancelledTrack = trackedSession(); cancelledTrack.targets.performFeedback = {}
        proposals = []; cancelledTrack.targets.onChange = { proposals.append($0) }
        _ = cancelledTrack.update(drag); cancelledTrack.end(); cancelledTrack.end()
        check(proposals == [.replace(0), nil], "session end clears the proposal once")
        drag.draggingLocation = NSPoint(x: 40, y: 40)
        var ending: ExternalSplitDropSession?
        var terminalValidations = 0
        ending = ExternalSplitDropSession(host: host, info: drag, frames: [host.bounds], orientation: .horizontal,
            validate: {
                terminalValidations += 1
                check(ending?.ended == true, "terminal callback sees revoked session")
                ending?.end()
                return true
            }, insertionColor: { .black }, canPropose: { _, _ in true }, commit: { _, _ in false })!
        ending?.end(); ending?.end()
        check(terminalValidations == 1 && host.subviews.isEmpty,
              "terminal validation reentry cannot repeat cleanup or leave a view")
        ending = nil
        let geometry=ExternalSplitDropSession.proposal(at:NSPoint(x:100,y:5),frames:[host.bounds],orientation:.horizontal)
        if case .insert(0)? = geometry?.0 { check(geometry?.1 == .vertical,"secondary axis uses recovered top edge") } else { fatalError("wrong top target") }
        let center=ExternalSplitDropSession.proposal(at:NSPoint(x:100,y:100),frames:[host.bounds],orientation:.horizontal)
        if case .replace(0)? = center?.0 { check(center?.2 == host.bounds,"center replacement exact pane") } else { fatalError("wrong center target") }
        check(ExternalSplitDropSession.proposal(at:NSPoint(x:250,y:100),frames:[host.bounds],orientation:.horizontal)==nil,"outside content has no proposal")
        var acceptedTarget: SplitDropTarget?
        drag.draggingLocation = NSPoint(x: 10, y: 100)
        let fallback = ExternalSplitDropSession(host: host, info: drag, frames: [host.bounds], orientation: .horizontal,
            validate: { true }, insertionColor: { .black }, canPropose: { target, _ in if case .replace = target { return true }; return false },
            commit: { target, _ in acceptedTarget = target; return true })!
        check(fallback.update(drag) == .copy && fallback.perform(drag), "unavailable insertion falls back through real replacement owner")
        if case .replace(0)? = acceptedTarget { check(true, "fallback commits exact original pane") } else { fatalError("wrong fallback") }
        let unavailable = ExternalSplitDropSession(host: host, info: drag, frames: [host.bounds], orientation: .horizontal,
            validate: { true }, insertionColor: { .black }, canPropose: { _, _ in false }, commit: { _, _ in fatalError("unavailable target committed") })!
        check(unavailable.update(drag).isEmpty && !unavailable.perform(drag), "no supported target has no preview or commit")
        let owner = ExternalSplitDropHost(frame: host.bounds); host.addSubview(owner)
        let childA = NSView(frame: host.bounds), childB = NSView(frame: host.bounds); owner.addSubview(childA); owner.addSubview(childB)
        owner.makeSession = { _, info in ExternalSplitDropSession(host:owner,info:info,frames:[owner.bounds],orientation:.horizontal,validate:{true},insertionColor:{.black},canPropose:{_,_ in true},commit:{_,_ in commits += 1;return true}) }
        check(owner.contentView(childA, beginDrop:drag) == .copy && owner.contentView(childB, beginDrop:drag) == .copy,"new native pane receives its own drag owner")
        owner.contentViewDidEndDrop(childA)
        check(owner.contentView(childB, updateDrop:drag) == .copy && !owner.contentView(childA, performDrop:drag),"old pane exit/drop cannot cancel or retarget new recipient")
        check(owner.contentView(childB, performDrop:drag) && commits == 3,"only current native recipient commits")
        let reserveWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1810, height: 700),
            styleMask: .borderless, backing: .buffered, defer: false)
        let reserveHost = ReservedHost(frame: NSRect(x: 0, y: 0, width: 1810, height: 700))
        reserveWindow.contentView = reserveHost
        let split = ParcSplitView(frame: reserveHost.bounds); reserveHost.addSubview(split)
        let firstPane = ReservedPane(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let secondPane = ReservedPane(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        split.addArrangedSubview(firstPane); split.addArrangedSubview(secondPane)
        split.configure(orientation: .horizontal, factors: [0.75, 0.25]); split.constrain(to: reserveHost)
        let originalFrames = split.arrangedSubviews.map(\.frame)
        let lease = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        check(lease.isCurrent && split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body]) == nil,
              "one presentation lease admits only the exact original surfaces")
        lease.setInsertionColor { ink }
        let insert = lease.proposal(at: NSPoint(x: 1, y: 200), canPropose: { _, _ in true })!
        check(insert.0 == .insert(0) && insert.1 == .horizontal && insert.2.minY == 0 && insert.2.height == 700,
              "reserved region uses original insertion identity and the whole pane slot, header included")
        check(lease.incomingPaneSize == NSSize(width: split.bounds.width / 3, height: split.bounds.height),
              "incoming pane size is the split's width over one more pane, by its full height")
        check(!lease.reusedRegion, "a new insertion slot has no existing drop region")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(ReservedPane.followed.contains { $0.0 === firstPane && $0.2 == 0.2 && $0.1 != firstPane.layer?.bounds },
                  "pane highlight receives the pane layer's previous bounds and 0.2-second transition")
        }
        check(split.arrangedSubviews.count == 2 && split.arrangedSubviews[0] === firstPane && split.arrangedSubviews[1] === secondPane,
              "presentation never inserts a saved/native page into original arranged owners")
        check(abs(insert.2.width - 597) <= 1 && abs(firstPane.frame.width - 895) <= 1 && abs(secondPane.frame.width - 298) <= 1,
              "incoming region gets one third while originals preserve their 3-to-1 factor ratio")
        check(firstPane.frame.minX == insert.2.maxX + 10 && secondPane.frame.minX == firstPane.frame.maxX + 10,
              "reserved layout retains both genuine ten-point gaps")
        let regionView = split.subviews.first { $0 !== firstPane && $0 !== secondPane }!
        check(regionView.frame == insert.2 && regionView.layer?.borderWidth == 2 && regionView.layer?.cornerRadius == 6,
              "actual reserved region renders the recovered border on original content geometry")
        check(regionView.layer?.backgroundColor == nil && regionView.layer?.opacity == 1,
              "expanded border is transparent with already-authoritative visible alpha")
        check(!regionView.isAccessibilityElement() && regionView.accessibilityChildren()?.isEmpty == true,
              "active and retiring region is a passive native presentation")
        let borderMotion = regionView.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup
        check(borderMotion?.duration == 0.2 && borderMotion?.timingFunction == CAMediaTimingFunction(name: .easeOut),
              "actual border expands with original alpha/layout duration and curve whatever the Reduce Motion setting")
        let bounds = borderMotion?.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds" }
        let alpha = borderMotion?.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "opacity" }
        check((bounds?.fromValue as? NSValue)?.rectValue.width == 0 && (bounds?.toValue as? NSValue)?.rectValue == regionView.layer?.bounds,
              "border starts from collapsed zero-axis geometry and targets exact reserved size")
        check((alpha?.fromValue as? NSNumber)?.doubleValue == 0 && (alpha?.toValue as? NSNumber)?.doubleValue == 1,
              "display-state alpha goes from collapsed zero to expanded one")
        let ownedInk = NSColor(cgColor: regionView.layer!.borderColor!)!.usingColorSpace(.deviceRGB)!
        check(abs(ownedInk.alphaComponent - 0.5) < 0.001, "region resolves actual original-window half-opacity ink")
        let movement = firstPane.layer?.animation(forKey: "Split reserved layout") as? CAAnimationGroup
        check(movement?.duration == 0.2 && movement?.animations?.count == 2,
              "actual original pane layer receives the attributed position/bounds transition")
        check(movement?.timingFunction == CAMediaTimingFunction(name: .easeOut),
              "reservation uses the actual ease-out timing function")
        let boundsMotion = movement?.animations?.first { ($0 as? CABasicAnimation)?.keyPath == "bounds" } as? CABasicAnimation
        check((boundsMotion?.toValue as? NSValue)?.rectValue == firstPane.layer?.bounds,
              "animation targets already-authoritative geometry, not a deferred frame write")
        check(lease.isCurrent && !split.isAccessibilityElement() && (split.accessibilitySplitters() ?? []).isEmpty,
              "controlled geometry stays admitted; the plain container exposes no divider")
        let held = lease.proposal(at: NSPoint(x: insert.2.midX, y: insert.2.midY), canPropose: { _, _ in true })!
        check(held.0 == insert.0 && held.2 == insert.2 && lease.reusedRegion, "pointer in its own reserved region keeps the original proposal and region")
        let moved = lease.proposal(at: NSPoint(x: secondPane.frame.maxX - 1, y: 200), canPropose: { _, _ in true })!
        check(moved.0 == .insert(2) && split.subviews.contains(where: { $0 === regionView }), "pointer retarget reorders the same reserved region")
        check(!lease.reusedRegion, "a different insertion slot is a new proposal region")
        check(regionView.hitTest(.zero) == nil && !regionView.acceptsFirstResponder, "region has no input/focus owner")
        check(lease.proposal(at: NSPoint(x: -20, y: -20), canPropose: { _, _ in true }) == nil && split.arrangedSubviews.map(\.frame) == originalFrames,
              "exit restores all original frames without a model transaction")
        check(lease.isCurrent && !lease.containsReservedPoint(NSPoint(x: moved.2.midX, y: moved.2.midY)),
              "collapsed border never remains a valid drop region")
        check(regionView.layer?.opacity == 0 && regionView.frame.width == 0,
              "normal exit synchronously publishes collapsed border state")
        check(regionView.superview === split && regionView.layer?.animation(forKey: "Split drop region") != nil,
              "only the exact passive border remains during its exit transition")
        check(firstPane.layer?.animation(forKey: "Split reserved layout") != nil,
              "exit restores original logical geometry while same surfaces ease back")
        _ = lease.proposal(at: NSPoint(x: 1, y: 200), canPropose: { _, _ in true })
        check(split.subviews.contains(where: { $0 === regionView }) && regionView.layer?.opacity == 1,
              "reentry reuses original region and supersedes its retiring transition")
        check(!lease.reusedRegion, "reentry at a different slot than the retiring region is a new region")
        _ = lease.proposal(at: NSPoint(x: -20, y: -20), canPropose: { _, _ in true })
        _ = lease.proposal(at: NSPoint(x: 1, y: 200), canPropose: { _, _ in true })
        check(lease.reusedRegion == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              "returning to the still-collapsing region at the same slot reuses it (no feedback)")
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        check(regionView.superview === split && regionView.layer?.opacity == 1,
              "old exit completion cannot remove a reentered original region")
        lease.clear()
        check(regionView.superview == nil && regionView.layer?.animation(forKey: "Split drop region") == nil,
              "precommit clear synchronously removes border and presentation animation")
        check(lease.isCurrent && split.arrangedSubviews.map(\.frame) == originalFrames, "precommit clear restores original geometry while keeping validation alive")
        check(firstPane.layer?.animation(forKey: "Split reserved layout") == nil,
              "precommit clear ends motion before original transaction admission")
        var editing: [Bool] = []
        split.onInteractivePaneEditing = { editing.append($0) }
        check(editing.isEmpty && !split.isInteractivePaneEditing,
              "a presentation lease alone is not interactive pane editing")
        let edit = lease.beginInteractivePaneEdit()
        check(edit != nil && editing == [true] && split.isInteractivePaneEditing,
              "the drag's first admitted entry begins editing (reason 0x4)")
        _ = lease.proposal(at: NSPoint(x: -20, y: -20), canPropose: { _, _ in true })
        check(editing == [true] && split.isInteractivePaneEditing, "leaving the pane area keeps editing until the drag ends")
        check(ReservedPane.cancelled > 0, "cleared pane motion also cancels the pane highlight's path transition")
        lease.end(); lease.end()
        check(lease.ended && !lease.isCurrent && split.subviews.count == 2, "end is one-shot and retains original owners")
        check(editing == [true] && split.isInteractivePaneEditing, "the drag's edit outlives its presentation lease")
        check(lease.beginInteractivePaneEdit() == nil, "an ended lease cannot begin an edit")
        edit?.end(); edit?.end()
        check(editing == [true, false] && !split.isInteractivePaneEditing, "only the drag's terminal end clears it, once")
        let refusedLease = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        let replace = refusedLease.proposal(at: NSPoint(x: 1, y: 200), canPropose: { target, _ in if case .replace = target { return true }; return false })!
        check(replace.0 == .replace(0) && split.arrangedSubviews.map(\.frame) == originalFrames, "refused insertion keeps genuine original replacement without reservation")
        check(!refusedLease.reusedRegion, "replacement has no drop region")
        refusedLease.end()
        let headerLease = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        let header = headerLease.proposal(at: NSPoint(x: 1, y: 20), canPropose: { _, _ in true })
        check(header?.0 == .insert(0) && header?.2.minY == 0 && header?.2.height == 700,
              "a pointer over a pane's header targets that pane's edge, since the top bar is inside its pane")
        headerLease.end()
        check(split.arrangedSubviews.map(\.frame) == originalFrames, "header proposal lease restores the original frames")
        let stackLease = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        stackLease.setInsertionColor { ink }
        let stackPoint = NSPoint(x: originalFrames[0].midX, y: originalFrames[0].maxY - 10)
        let stack = stackLease.proposal(at: stackPoint, canPropose: { _, _ in true })!
        let stackShape = BrowserSplitStacks(slotSizes: [2, 1], slotFactors: BrowserSplitLayout.normalized([0.75, 0.25], count: 2)!,
                                            stackFactors: [[0.5, 0.5], [1]])
        let stackFrames = SplitStackGeometry.paneFrames(size: split.bounds.size, orientation: .horizontal, stacks: stackShape,
            thickness: split.dividerThickness, minimum: 220, scale: reserveWindow.backingScaleFactor)
        let stackRegion = split.subviews.first { $0 !== firstPane && $0 !== secondPane }!
        check(stack.0 == .stack(0, after: true) && stack.1 == .horizontal && !stackLease.reusedRegion && stackLease.isCurrent,
              "a pane's bottom band reserves a new region inside its column and keeps the lease admitted")
        check(firstPane.frame == stackFrames[0] && stackRegion.frame == stackFrames[1] && stack.2 == stackFrames[1]
              && secondPane.frame == stackFrames[2],
              "a flat split previews the stacked shape the commit would produce, the region below its pane in that column")
        check(stackRegion.frame.minX == originalFrames[0].minX && stackRegion.frame.maxX == originalFrames[0].maxX
              && secondPane.frame.height == split.bounds.height, "only the stacked column divides")
        check(stackLease.incomingPaneSize == NSSize(width: originalFrames[0].width, height: split.bounds.height / 2),
              "a stacked incoming pane is its column wide and half the split high")
        check((split.accessibilitySplitters() ?? []).isEmpty, "a stack reservation hides every divider")
        let stackMotion = stackRegion.layer?.animation(forKey: "Split drop region") as? CAAnimationGroup
        let stackStart = stackMotion?.animations?.compactMap { $0 as? CABasicAnimation }.first { $0.keyPath == "bounds" }
        check(stackMotion?.duration == 0.2 && (stackStart?.fromValue as? NSValue)?.rectValue.size == NSSize(width: originalFrames[0].width, height: 0),
              "the region grows from a zero-height line across only its column")
        check(firstPane.layer?.animation(forKey: "Split reserved layout") != nil, "the stacked pane eases into its new frame")
        let stackHeld = stackLease.proposal(at: NSPoint(x: stack.2.midX, y: stack.2.midY), canPropose: { _, _ in true })!
        check(stackHeld.0 == stack.0 && stackHeld.2 == stack.2 && stackLease.reusedRegion,
              "pointer in its own stacked region keeps the proposal")
        let stackRepeat = stackLease.proposal(at: NSPoint(x: stackFrames[0].midX, y: stackFrames[0].maxY - 5), canPropose: { _, _ in true })!
        check(stackRepeat.0 == stack.0 && stackLease.reusedRegion && firstPane.frame == stackFrames[0],
              "reclassifying to the same stack target reuses the region without relayout")
        let mainRow = stackLease.proposal(at: NSPoint(x: stackFrames[0].maxX - 5, y: 100), canPropose: { _, _ in true })!
        check(mainRow.0 == .insert(1) && !stackLease.reusedRegion && firstPane.frame.height == split.bounds.height
              && stackRegion.frame.height == split.bounds.height,
              "a main-row slot at the same reading-order index is a different reservation")
        check(stackLease.incomingPaneSize == NSSize(width: split.bounds.width / 3, height: split.bounds.height),
              "a main-row reservation keeps today's incoming pane size")
        let backToStack = stackLease.proposal(at: NSPoint(x: firstPane.frame.midX, y: firstPane.frame.maxY - 10), canPropose: { _, _ in true })!
        check(backToStack.0 == stack.0 && !stackLease.reusedRegion && firstPane.frame == stackFrames[0],
              "moving from a main-row slot back to the stack is a new region")
        check(stackLease.proposal(at: NSPoint(x: -20, y: -20), canPropose: { _, _ in true }) == nil
              && split.arrangedSubviews.map(\.frame) == originalFrames, "leaving restores the flat frames")
        check(stackRegion.frame == NSRect(x: originalFrames[0].minX, y: originalFrames[0].maxY, width: originalFrames[0].width, height: 0)
              && stackRegion.layer?.opacity == 0, "a retiring stack region collapses to its pane's edge across only its column")
        check(stackLease.incomingPaneSize == NSSize(width: split.bounds.width / 3, height: split.bounds.height),
              "with nothing reserved the incoming pane size is today's")
        _ = stackLease.proposal(at: stackPoint, canPropose: { _, _ in true })
        check(stackLease.reusedRegion == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              "returning to the still-collapsing stack region reuses it (no feedback)")
        stackLease.end()
        check(split.arrangedSubviews.map(\.frame) == originalFrames && split.subviews.count == 2 && split.isVertical,
              "ending a stack reservation restores the flat split")
        let staleLease = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        let staleEdit = staleLease.beginInteractivePaneEdit()
        _ = staleLease.proposal(at: NSPoint(x: 1, y: 200), canPropose: { _, _ in true })
        split.configure(orientation: .vertical, factors: [0.5, 0.5])
        check(editing == [true, false, true] && split.isInteractivePaneEditing,
              "retiring the lease on an owner change keeps the drag's edit")
        check(staleLease.ended && !staleLease.isCurrent && split.subviews.count == 2 && !split.isVertical,
              "new authoritative group layout retires old reservation and cannot be overwritten by stale end")
        staleLease.end()
        check(!split.isVertical, "stale region cleanup cannot restore the old orientation")
        check(firstPane.layer?.animation(forKey: "Split reserved layout") == nil,
              "authoritative orientation replacement retires original-layer transition")
        let resizeLease = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        let nextEdit = resizeLease.beginInteractivePaneEdit()
        check(staleEdit?.ended == true && nextEdit?.ended == false && editing == [true, false, true],
              "a new drag's edit replaces an unterminated one without a gap")
        staleEdit?.end()
        check(editing == [true, false, true] && split.isInteractivePaneEditing, "a replaced edit's late end changes nothing")
        nextEdit?.end()
        check(editing == [true, false, true, false], "the current drag's end clears the reason")
        let topEdge = resizeLease.proposal(at: NSPoint(x: 200, y: 41), canPropose: { _, _ in true })
        check(topEdge?.0 == .insert(0) && topEdge?.1 == .vertical
              && resizeLease.incomingPaneSize == NSSize(width: split.bounds.width, height: split.bounds.height / 3),
              "an incoming pane at a top-and-bottom split's top edge is the split wide and a third of it high")
        reserveHost.frame.size.width += 30
        check(!resizeLease.isCurrent, "outside host resize is never accepted as owned preview geometry")
        resizeLease.end()
        let reentrant = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        let invalidatedProposal = reentrant.proposal(at: NSPoint(x: 200, y: 41), canPropose: { _, _ in
            split.configure(orientation: .horizontal, factors: [0.75, 0.25]); return true
        })
        check(invalidatedProposal == nil && reentrant.ended && split.subviews.count == 2,
              "admission callback retirement cannot attach an orphan region or publish an old proposal")
        let beforeReorder = split.arrangedSubviews.map(\.frame)
        let terminalMotion = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        _ = terminalMotion.proposal(at: NSPoint(x: 1, y: 200), canPropose: { _, _ in true })
        terminalMotion.end(animated: true)
        check(terminalMotion.ended && !terminalMotion.isCurrent && split.arrangedSubviews.map(\.frame) == beforeReorder,
              "cancel retires its lease synchronously before passive presentation finishes")
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: reserveWindow)
        check(firstPane.layer?.animation(forKey: "Split reserved layout") == nil && split.subviews.count == 2,
              "original window resignation clears terminal border and remaining layer transition")
        let hiddenMotion = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        _ = hiddenMotion.proposal(at: NSPoint(x: 1, y: 200), canPropose: { _, _ in true })
        split.isHidden = true
        check(hiddenMotion.ended && split.subviews.count == 2 && firstPane.layer?.animation(forKey: "Split reserved layout") == nil,
              "native hiding revokes gesture and border presentation without waiting for completion")
        split.isHidden = false
        let completeMotion = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body])!
        _ = completeMotion.proposal(at: NSPoint(x: 1, y: 200), canPropose: { _, _ in true })
        completeMotion.end(animated: true)
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        check(split.subviews.count == 2 && !completeMotion.isCurrent,
              "current passive completion removes its own retired region without a drag owner")
        let thirdPane = ReservedPane(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        split.addArrangedSubview(thirdPane)
        let column = BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.5, 0.5], stackFactors: [[0.5, 0.5], [1]])
        split.configure(orientation: .horizontal, factors: column.flattenedFactors, stacks: column)
        reserveHost.layoutSubtreeIfNeeded()
        let columnFrames = split.arrangedSubviews.map(\.frame)
        let columnLease = split.prepareDropReservation(in: reserveHost, contents: [firstPane.body, secondPane.body, thirdPane.body])!
        let grow = columnLease.proposal(at: NSPoint(x: columnFrames[1].midX, y: columnFrames[1].maxY - 10), canPropose: { _, _ in true })!
        let grownFrames = SplitStackGeometry.paneFrames(size: split.bounds.size, orientation: .horizontal,
            stacks: BrowserSplitStacks(slotSizes: [3, 1], slotFactors: [0.5, 0.5], stackFactors: [[1.0 / 3, 1.0 / 3, 1.0 / 3], [1]]),
            thickness: split.dividerThickness, minimum: 220, scale: reserveWindow.backingScaleFactor)
        check(grow.0 == .stack(1, after: true) && grow.1 == .horizontal && !columnLease.reusedRegion && columnLease.isCurrent,
              "a stacked pane's bottom band reserves room inside its own stack")
        check([firstPane.frame, secondPane.frame, grow.2, thirdPane.frame] == grownFrames,
              "the stack of two grows to three in the preview while the lone column keeps its frame")
        check(columnLease.incomingPaneSize == NSSize(width: columnFrames[1].width, height: split.bounds.height / 3),
              "an incoming pane in a stack of two is its column wide and a third of the split high")
        check((split.accessibilitySplitters() ?? []).isEmpty, "a stacked split hides its stack and main-row dividers while reserving")
        columnLease.end()
        check(split.arrangedSubviews.map(\.frame) == columnFrames && split.subviews.count == 3,
              "ending the stacked reservation restores the stacked frames")
        let handWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1810, height: 700),
            styleMask: .borderless, backing: .buffered, defer: false)
        let handHost = ExternalSplitDropHost(frame: NSRect(x: 0, y: 0, width: 1810, height: 700))
        handWindow.contentView = handHost
        let handSplit = ParcSplitView(frame: handHost.bounds); handHost.addSubview(handSplit)
        let handA = ReservedPane(frame: handHost.bounds), handB = ReservedPane(frame: handHost.bounds)
        handSplit.addArrangedSubview(handA); handSplit.addArrangedSubview(handB)
        handSplit.configure(orientation: .horizontal, factors: [0.75, 0.25]); handSplit.constrain(to: handHost)
        var handButtonDown = true
        handSplit.primaryMouseButtonIsDown = { handButtonDown }
        func settle() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15)) }
        let handFrames = handSplit.arrangedSubviews.map(\.frame)
        let handDrag = Drag(); handDrag.draggingDestinationWindow = handWindow
        handDrag.draggingPasteboard.setString("https://handoff.invalid/path", forType: .URL)
        defer { handDrag.draggingPasteboard.releaseGlobally() }
        var handCommits = 0, handAdmits = 0, handValid = true, handCommitResult = true
        handHost.makeSession = { _, info in
            handAdmits += 1
            let reservation = handSplit.prepareDropReservation(in: handHost, contents: [handA.body, handB.body])!
            return ExternalSplitDropSession(host: handHost, info: info,
                frames: [handA.body, handB.body].map { $0.convert($0.bounds, to: handHost) }, orientation: .horizontal,
                reservation: reservation, validate: { handValid && reservation.isCurrent }, insertionColor: { .black },
                canPropose: { _, _ in true }, commit: { _, _ in
                    check(handSplit.arrangedSubviews.map(\.frame) == handFrames, "original geometry restored before actual durable commit")
                    handCommits += 1; return handCommitResult
                })
        }
        let handRouter = PCCreateNativeContentDropRouter(handA.body)
        func beginHandoff() {
            handDrag.draggingLocation = handHost.convert(NSPoint(x: 1, y: 200), to: nil)
            check(handRouter.begin(handDrag) && handRouter.operation == .copy, "original content admits external URL before reservation")
            check(handSplit.arrangedSubviews.map(\.frame) != handFrames && handSplit.arrangedSubviews.count == 2, "URL reserves layout without new page owner")
            handDrag.draggingLocation = handHost.convert(NSPoint(x: 200, y: 200), to: nil)
            handRouter.exit(handDrag)
            check(handHost.draggingEntered(handDrag) == .copy, "host accepts only exact original native-to-region handoff")
        }
        var handEditing: [Bool] = []
        handSplit.onInteractivePaneEditing = { handEditing.append($0) }
        check(handHost.draggingEntered(handDrag).isEmpty && handAdmits == 0, "unclaimed host URL cannot create a session")
        beginHandoff()
        check(handEditing == [true] && handSplit.isInteractivePaneEditing,
              "an admitted external URL begins interactive pane editing before its reserved layout")
        check(handHost.performDragOperation(handDrag) && handCommits == 1 && handAdmits == 1, "one native gesture performs once through original receiver")
        check(handEditing == [true, false] && !handSplit.isInteractivePaneEditing, "the performed drop ends interactive editing")
        check(!handHost.performDragOperation(handDrag) && handCommits == 1 && handSplit.subviews.count == 2, "late host callbacks cannot replay or leave region")
        beginHandoff(); handRouter.end()
        check(handHost.draggingUpdated(handDrag).isEmpty && handCommits == 1 && handSplit.arrangedSubviews.map(\.frame) == handFrames,
              "original native terminal callback cancels handoff and restores exact layout")
        check(handEditing == [true, false, true, false], "terminal cancellation ends interactive editing")
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 1, y: 200), to: nil)
        check(handRouter.begin(handDrag) && handSplit.isInteractivePaneEditing, "a new admitted entry begins the drag's edit")
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 1700, y: 200), to: nil)
        handRouter.exit(handDrag)
        check(handRouter.claimed && handSplit.arrangedSubviews.map(\.frame) == handFrames
              && handEditing == [true, false, true, false, true] && handSplit.isInteractivePaneEditing,
              "leaving the page ends its preview but keeps the drag's edit and its router as terminal witness")
        check(handHost.draggingUpdated(handDrag).isEmpty && !handHost.prepareForDragOperation(handDrag),
              "the witness router cannot drop through the host")
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 1, y: 200), to: nil)
        check(handRouter.begin(handDrag) && handSplit.isInteractivePaneEditing && handEditing.last == true,
              "re-entering the same page resumes the drag's edit before any layout")
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 1700, y: 200), to: nil)
        handRouter.exit(handDrag)
        handRouter.end()
        check(!handRouter.claimed && !handSplit.isInteractivePaneEditing && handEditing.last == false,
              "the exited page view's terminal draggingEnded ends the edit")
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 1, y: 200), to: nil)
        check(handRouter.begin(handDrag) && handSplit.isInteractivePaneEditing, "another admitted entry begins an edit")
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 1700, y: 200), to: nil)
        handRouter.exit(handDrag)
        settle()
        check(handSplit.isInteractivePaneEditing, "outside the page with the button held, the edit stays")
        let handBRouter = PCCreateNativeContentDropRouter(handB.body)
        let editsBeforeOtherPage = handEditing
        check(handBRouter.begin(handDrag) && handSplit.isInteractivePaneEditing && handEditing == editsBeforeOtherPage,
              "entering the other page before button release continues the same edit")
        handButtonDown = false; settle()
        check(handSplit.isInteractivePaneEditing, "while a page has the drag, button state cannot end the edit")
        handButtonDown = true
        handBRouter.exit(handDrag)
        check(handSplit.isInteractivePaneEditing && handBRouter.claimed, "leaving the other page keeps the edit")
        handButtonDown = false; settle()
        check(!handSplit.isInteractivePaneEditing && handEditing.last == false,
              "with no route holding the drag, button release ends the edit when no terminal callback arrives")
        let afterFallback = handEditing
        handRouter.end(); handBRouter.end()
        check(handEditing == afterFallback && !handRouter.claimed && !handBRouter.claimed,
              "late terminal callbacks after the fallback change nothing")
        handButtonDown = true
        beginHandoff(); handValid = false; handHost.validateDrop()
        check(handHost.draggingUpdated(handDrag).isEmpty && !handHost.performDragOperation(handDrag) && handCommits == 1,
              "original page/editor expiry refuses continuation without a new owner")
        handValid = true; beginHandoff(); handHost.draggingExited(handDrag)
        check(handSplit.arrangedSubviews.map(\.frame) == handFrames && !handHost.prepareForDragOperation(handDrag),
              "leaving reserved host area cancels rather than retaining a stranded draft")
        check(handSplit.isInteractivePaneEditing && handRouter.claimed, "leaving the host keeps the drag's edit")
        handHost.draggingEnded(handDrag)
        check(!handSplit.isInteractivePaneEditing, "the host's terminal draggingEnded ends the edit")
        beginHandoff(); handDrag.draggingSequenceNumber += 1
        check(handHost.draggingUpdated(handDrag).isEmpty && handSplit.subviews.count == 2, "foreign sequence cannot enter old reserved region")
        handCommitResult = false; beginHandoff()
        check(!handHost.performDragOperation(handDrag) && handCommits == 2 && handSplit.subviews.count == 2, "real commit refusal removes reservation and reports failure")
        let localReceiver = LocalContentDropView(frame: handA.body.bounds)
        localReceiver.autoresizingMask = [.width, .height]; handA.body.addSubview(localReceiver)
        handCommitResult = true
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 1, y: 200), to: nil)
        check(localReceiver.draggingEntered(handDrag) == .copy, "actual local document forwarder admits same native reservation")
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 200, y: 200), to: nil)
        localReceiver.draggingExited(handDrag)
        check(handHost.draggingEntered(handDrag) == .copy && handHost.performDragOperation(handDrag) && handCommits == 3,
              "actual local exit forwards exact router instead of terminating before host entry")
        localReceiver.draggingEnded(handDrag)
        check(handSplit.subviews.count == 2 && handSplit.arrangedSubviews.map(\.frame) == handFrames,
              "late local terminal callback leaves originals and consumed transaction unchanged")
        localReceiver.removeFromSuperview()
        let textReceiver = LocalContentDropTextView(frame: handA.body.bounds)
        textReceiver.autoresizingMask = [.width, .height]; handA.body.addSubview(textReceiver)
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 1, y: 200), to: nil)
        check(textReceiver.draggingEntered(handDrag) == .copy, "actual native text receiver admits original URL")
        handDrag.draggingLocation = handHost.convert(NSPoint(x: 200, y: 200), to: nil)
        textReceiver.draggingExited(handDrag)
        check(handHost.draggingEntered(handDrag) == .copy, "text receiver exit retains original handoff")
        textReceiver.draggingEnded(handDrag)
        check(handHost.draggingUpdated(handDrag).isEmpty && handCommits == 3 && handSplit.arrangedSubviews.map(\.frame) == handFrames,
              "optional native text terminal cleanup cancels same handoff and restores authority without superclass exception")
        CATransaction.flush()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        check(handSplit.subviews.count == 2,
              "normal text terminal presentation removes only its passive region after collapse")
        textReceiver.removeFromSuperview()

        beginHandoff(); handA.removeFromSuperview()
        check(handHost.draggingUpdated(handDrag).isEmpty && !handHost.performDragOperation(handDrag) && handCommits == 3,
              "original native receiver detachment cannot retarget remaining pane")
        let headWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1810, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        let headHost = ExternalSplitDropHost(frame: NSRect(x: 0, y: 0, width: 1810, height: 700)); headWindow.contentView = headHost
        let headSplit = ParcSplitView(frame: headHost.bounds); headHost.addSubview(headSplit)
        let headA = ReservedPane(frame: headHost.bounds)
        headSplit.addArrangedSubview(headA)
        headSplit.configure(orientation: .horizontal, factors: [1]); headSplit.constrain(to: headHost)
        let headDrag = Drag(); headDrag.draggingDestinationWindow = headWindow
        headDrag.draggingPasteboard.setString("https://header.invalid/path", forType: .URL)
        defer { headDrag.draggingPasteboard.releaseGlobally() }
        let linkItem = NSPasteboardItem(); linkItem.setString("https://header.invalid/path", forType: .URL)
        let linkDragItem = NSDraggingItem(pasteboardWriter: linkItem)
        let linkImage = NSImage(size: NSSize(width: 120, height: 20))
        linkDragItem.setDraggingFrame(NSRect(x: 40, y: 50, width: 120, height: 20), contents: linkImage)
        headDrag.items = [linkDragItem]
        var headTargets: [(SplitDropTarget, SplitOrientation)] = []
        headHost.makeSession = { _, info in
            let reservation = headSplit.prepareDropReservation(in: headHost, contents: [headA.body])!
            return ExternalSplitDropSession(host: headHost, info: info, frames: [], orientation: .horizontal,
                reservation: reservation, validate: { reservation.isCurrent }, insertionColor: { .black },
                canPropose: { _, _ in true }, commit: { target, orientation in headTargets.append((target, orientation)); return true })
        }
        let headRouter = PCCreateNativeContentDropRouter(headA.body)
        headDrag.draggingLocation = headHost.convert(NSPoint(x: 905, y: 400), to: nil)
        check(headRouter.begin(headDrag) && headRouter.operation == .copy, "the page admits the link")
        let cardSize = SplitDropPlaceholderCard.size(forIncomingPane: NSSize(width: headSplit.bounds.width / 2, height: headSplit.bounds.height))!
        let cardImage = linkDragItem.imageComponentsProvider?().first?.contents as? NSImage
        check(cardImage !== linkImage && cardImage?.size == cardSize && linkDragItem.draggingFrame == NSRect(origin: NSPoint(x: 40, y: 50), size: cardSize),
              "the admitted link becomes a placeholder card at its own bottom-left")
        let headerPoint = NSPoint(x: headA.frame.midX, y: 20)
        headDrag.draggingLocation = headHost.convert(headerPoint, to: nil)
        headRouter.exit(headDrag)
        check(headHost.draggingEntered(headDrag) == .copy, "over a pane header the host continues the link drag")
        check(headHost.performDragOperation(headDrag) && headTargets.count == 1 && headTargets[0].0 == .insert(0) && headTargets[0].1 == .vertical,
              "a single pane's header is in its 50-point top zone, as over a full-height pane")
        check(linkDragItem.draggingFrame.size == cardSize, "a performed drop keeps the card")
        headRouter.end()
        linkDragItem.setDraggingFrame(NSRect(x: 40, y: 50, width: 120, height: 20), contents: linkImage)
        headDrag.draggingLocation = headHost.convert(NSPoint(x: 905, y: 400), to: nil)
        check(headRouter.begin(headDrag) && linkDragItem.draggingFrame.size == cardSize, "a new entry shows the card again")
        headDrag.draggingLocation = headHost.convert(NSPoint(x: headA.frame.midX, y: headA.frame.maxY + 40), to: nil)
        headRouter.exit(headDrag)
        check(linkDragItem.draggingFrame == NSRect(x: 40, y: 50, width: 120, height: 20)
              && (linkDragItem.imageComponentsProvider?().first?.contents as? NSImage) === linkImage,
              "leaving the split gives the link its own image back")
        headRouter.end()
        print("External split native session: \(count) checks passed")
    }
}
