import Foundation

var checks = 0
func expect(_ value: Bool, _ message: String) {
    checks += 1
    precondition(value, "PeekSwipeDismissal: \(message)")
}

typealias Effect = PeekCloseTransition.Effect

struct Pad: HistorySwipeEnvironment {
    var swipesBetweenPages = true
    var allowsHistorySwipe = true
    var back = 0
    func historyEntries(toward direction: HistorySwipeDirection) -> Int { direction == .back ? back : 0 }
    func dismisses(toward direction: HistorySwipeDirection) -> Bool { back == 0 && direction == .back }
}

@MainActor
final class Peek {
    var transition = PeekCloseTransition()
    let confirmation = PeekDismissalConfirmation()
    var recognizer = HistorySwipeRecognizer()
    var pad = Pad()
    var visible = true
    var call = false
    var effects: [Effect] = []
    var closeRequests = 0
    var hangUp = false
    var time = 100.0
    var x = 0.3
    var y = 0.5

    func apply(_ list: [Effect]) {
        effects += list
        for effect in list where effect == .requestClose && !transition.holdForParent() { closeRequests += 1 }
    }

    func cancelled() {
        if !transition.holdForParent() { apply(transition.refused(visible: visible)) }
    }

    var reappeared: Bool { effects.contains(.reappear) }

    func requestDismiss(_ mechanism: PeekDismissalConfirmation.Dismissal) {
        guard transition.phase == .resting || transition.phase == .dragging else { return }
        if let reason = confirmation.request(mechanism, mediaInput: call, onExpiry: {}) {
            hangUp = reason == .mediaInput
            return
        }
        apply(transition.close(visible: visible, exit: mechanism == .swipe ? .slide : .fade))
    }

    func commit() {
        guard transition.phase == .dragging else { return }
        requestDismiss(.swipe)
        if transition.phase == .dragging { apply(transition.springBack()) }
    }

    func feed(_ input: HistorySwipeInput) {
        let step = recognizer.receive(input, in: pad)
        for output in step.outputs {
            switch output {
            case .beginDismissal:
                expect(transition.beginDrag(), "a resting Peek accepts the drag")
            case .commit(.dismiss):
                commit()
            default:
                apply(transition.drag(output))
            }
        }
    }

    var fingers: [HistorySwipePoint] { [HistorySwipePoint(x: x - 0.06, y: y), HistorySwipePoint(x: x + 0.06, y: y)] }

    func open() {
        feed(.touches(.began, fingers, time: time))
        feed(.scroll(HistorySwipeScroll(phase: .began, deltaX: 2, directionInverted: true)))
        feed(.pageScroll(.began(synthetic: false, momentum: false)))
        feed(.overscroll(propagatesX: true))
        feed(.pageScroll(.updated(consumed: false)))
        move(0.305)
        feed(.scroll(HistorySwipeScroll(phase: .changed, deltaX: 3, directionInverted: true)))
    }

    func move(_ to: Double, _ toY: Double? = nil, after delay: Double = 0.008) {
        time += delay
        x = to
        if let toY { y = toY }
        feed(.touches(.moved, fingers, time: time))
    }

    func lift(rested: Bool = true) {
        if rested { move(x + 0.0005, after: 0.2) }
        time += 0.008
        feed(.touches(.ended, fingers, time: time))
    }

    var haptics: Int { effects.filter { $0 == .haptic }.count }
    var follows: [Double] { effects.compactMap { if case let .follow(value) = $0 { value } else { nil } } }
    var lastExit: (PeekCloseTransition.Exit, Double, Double, Int)? {
        for effect in effects.reversed() {
            if case let .exit(kind, from, velocity, generation) = effect { return (kind, from, velocity, generation) }
        }
        return nil
    }
}

@MainActor
func run() {
    do {
        let peek = Peek()
        peek.open()
        for x in [0.36, 0.42, 0.47, 0.5] { peek.move(x) }
        peek.lift()
        expect(peek.follows.count >= 4 && abs(peek.follows[3] - 2.0 / 3) < 1e-9, "the card follows the fingers")
        expect(peek.haptics == 1, "crossing halfway taps once")
        guard let exit = peek.lastExit else { return expect(false, "a swipe past halfway starts the exit") }
        expect(exit.0 == .slide && abs(exit.1 - 2.0 / 3) < 0.01, "the exit slides on from where the fingers let go")
        expect(peek.transition.phase == .exiting && peek.closeRequests == 0,
               "the page isn't asked to close until the card has gone")
        peek.apply(peek.transition.exitFinished(exit.3))
        expect(peek.closeRequests == 1 && peek.transition.phase == .closing && peek.transition.cardHidden,
               "once the card has slid off, the page's real close is requested")
        peek.apply(peek.transition.exitFinished(exit.3))
        expect(peek.closeRequests == 1, "a late exit timer never asks twice")
        peek.apply(peek.transition.finish())
        expect(peek.effects.last == .vanish && peek.transition.phase == .finished,
               "a closed Peek stays invisible as it is removed, so nothing flashes")
    }

    do {
        let peek = Peek()
        peek.open()
        for x in [0.42, 0.5] { peek.move(x) }
        peek.lift()
        peek.apply(peek.transition.exitFinished(peek.lastExit?.3 ?? 0))
        peek.apply(peek.transition.sheetBegan(visible: true))
        expect(peek.effects.last == .reappear && !peek.transition.cardHidden,
               "when the page asks Leave site?, the card springs back under the question")
        peek.apply(peek.transition.refused(visible: true))
        expect(peek.effects.last == .reappear && peek.transition.phase == .resting,
               "choosing to stay leaves the card in place without a second spring")
        expect(peek.transition.beginDrag(), "the Peek can be swiped again after staying")
    }

    do {
        let peek = Peek()
        peek.open()
        peek.move(0.5)
        peek.lift()
        peek.apply(peek.transition.exitFinished(peek.lastExit?.3 ?? 0))
        peek.apply(peek.transition.refused(visible: true))
        expect(peek.effects.last == .reappear && peek.transition.phase == .resting,
               "a page that refuses without asking brings the card back")
        peek.apply(peek.transition.refused(visible: true))
        expect(peek.effects.filter { $0 == .reappear }.count == 1, "a second refusal is ignored")
    }

    do {
        let peek = Peek()
        peek.call = true
        peek.open()
        for x in [0.42, 0.5] { peek.move(x) }
        peek.lift()
        expect(peek.hangUp && peek.closeRequests == 0 && peek.lastExit == nil,
               "during a call a swipe past halfway shows Hang up instead of closing")
        expect(peek.effects.last.map { if case .springBack = $0 { true } else { false } } == true
               && peek.transition.phase == .resting, "the card springs back beside the red Hang up")
        peek.x = 0.3
        peek.recognizer = HistorySwipeRecognizer()
        peek.open()
        peek.move(0.5)
        peek.lift()
        expect(peek.confirmation.attempts == 2 && peek.closeRequests == 0,
               "a second swipe keeps Hang up pending and still never closes")
        peek.call = false
        peek.x = 0.3
        peek.recognizer = HistorySwipeRecognizer()
        peek.open()
        peek.move(0.5)
        peek.lift()
        expect(peek.closeRequests == 0 && peek.confirmation.reason == .mediaInput,
               "a swipe after the call stopped still needs Hang up")
        peek.confirmation.cancel()
    }

    do {
        let peek = Peek()
        peek.open()
        peek.move(0.42)
        peek.lift()
        expect(peek.lastExit == nil && peek.effects.last.map { if case .springBack = $0 { true } else { false } } == true,
               "letting go before halfway springs the card back")
        expect(peek.haptics == 0, "a swipe that never reached halfway never taps")
    }

    do {
        let peek = Peek()
        peek.open()
        peek.move(0.31)
        peek.move(0.34, after: 0.01)
        peek.lift(rested: false)
        guard let exit = peek.lastExit else { return expect(false, "a flick closes") }
        expect(exit.0 == .slide && exit.2 > 2 && peek.haptics == 0, "a flick slides off at its own speed without a tap")
    }

    do {
        let peek = Peek()
        peek.open()
        for x in [0.4, 0.47, 0.43, 0.38] { peek.move(x) }
        peek.lift()
        expect(peek.haptics == 1 && peek.lastExit == nil, "pulling back stays silent and springs back")
    }

    do {
        let peek = Peek()
        peek.open()
        peek.move(0.36)
        peek.move(0.37, 0.56)
        peek.move(0.5, 0.56)
        peek.lift()
        expect(peek.lastExit == nil && peek.transition.phase == .resting
               && peek.effects.contains { if case .springBack = $0 { true } else { false } },
               "drifting up or down springs the card back")
    }

    do {
        var transition = PeekCloseTransition()
        _ = transition.beginDrag()
        _ = transition.drag(.progress(HistorySwipeProgress(fraction: 0.6, stretch: 0.6)))
        _ = transition.close(visible: true, exit: .slide)
        let hidden = transition.hide()
        expect(hidden == [.vanish, .requestClose] && transition.cardHidden,
               "switching tabs mid-exit hides the card at once and closes the page without waiting for the fade")
        expect(transition.exitFinished(1).isEmpty, "the old exit timer can't act after the tab switch")
        expect(transition.refused(visible: false) == [.settle] && transition.phase == .resting,
               "a page that refuses while its tab is hidden is put back at rest for when the tab returns")
        expect(transition.sheetBegan(visible: true).isEmpty, "a later sheet never revives a resting card")
    }

    do {
        var transition = PeekCloseTransition()
        let effects = transition.close(visible: true, exit: .fade)
        expect(effects == [.exit(.fade, from: 0, velocity: 0, generation: 1)],
               "Escape, a click outside or Close fade the card in place")
        expect(transition.beginDrag() == false, "a closing Peek can't be grabbed")
        expect(transition.close(visible: true, exit: .fade).isEmpty, "a second close is ignored")
        expect(transition.exitFinished(1) == [.requestClose], "the fade's end asks the page to close")
        expect(transition.sheetBegan(visible: false).isEmpty, "a sheet in a hidden tab doesn't show the card")
        expect(transition.finish() == [.vanish], "removing a faded Peek keeps it invisible")
        expect(transition.finish().isEmpty, "finishing twice does nothing")
    }

    do {
        var transition = PeekCloseTransition()
        expect(transition.close(visible: false, exit: .fade) == [.requestClose] && !transition.cardHidden,
               "a hidden Peek closes straight away")
        expect(transition.refused(visible: false).isEmpty && transition.phase == .resting,
               "a hidden Peek that refuses is untouched")
        _ = transition.beginDrag()
        expect(transition.hide() == [.settle] && transition.phase == .resting, "hiding mid-drag drops the card back")
        _ = transition.beginDrag()
        _ = transition.drag(.progress(HistorySwipeProgress(fraction: 0.4, stretch: 0.4)))
        expect(transition.finish() == [.vanish], "a Peek removed mid-drag leaves nothing behind")
    }

    do {
        var first = PeekCloseTransition()
        _ = first.close(visible: true, exit: .slide)
        let generation = first.generation
        _ = first.hide()
        _ = first.refused(visible: true)
        _ = first.close(visible: true, exit: .fade)
        expect(first.generation == generation + 1 && first.exitFinished(generation).isEmpty,
               "an exit timer from an earlier close can't finish a newer one")
        expect(first.exitFinished(first.generation) == [.requestClose], "the newer exit finishes normally")
    }

    keyboard()
    parentClosing()
    motion()
    print("PeekSwipeDismissal: \(checks) checks passed")
}

func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

func keyboard() {
    var transition = PeekCloseTransition()
    expect(!transition.isLeaving, "a resting Peek keeps the keyboard")
    _ = transition.beginDrag()
    _ = transition.drag(.progress(HistorySwipeProgress(fraction: 0.6, stretch: 0.6)))
    expect(!transition.isLeaving, "dragging the card doesn't move the keyboard")
    _ = transition.close(visible: true, exit: .slide)
    expect(transition.isLeaving, "the moment the slide starts, typing belongs to the parent page instead of the leaving one")
    _ = transition.exitFinished(transition.generation)
    expect(transition.isLeaving, "the parent keeps the keyboard while the page decides whether to close")
    _ = transition.sheetBegan(visible: true)
    expect(!transition.isLeaving, "Leave site? brings the card back, so the Peek takes the keyboard back for its answer")
    _ = transition.refused(visible: true)
    expect(!transition.isLeaving && transition.phase == .resting, "choosing to stay leaves the keyboard with the Peek")

    _ = transition.close(visible: true, exit: .fade)
    expect(transition.isLeaving, "Escape, Close or a click outside hand the keyboard over as the fade starts")
    _ = transition.exitFinished(transition.generation)
    _ = transition.refused(visible: true)
    expect(!transition.isLeaving, "a page that refuses without asking gets the keyboard back with its card")

    _ = transition.close(visible: true, exit: .fade)
    _ = transition.hide()
    expect(transition.isLeaving, "a Peek hidden mid-fade never takes the keyboard back on its way out")
    _ = transition.finish()
    expect(!transition.isLeaving, "a finished Peek claims nothing")

    var hidden = PeekCloseTransition()
    _ = hidden.close(visible: false, exit: .fade)
    expect(!hidden.isLeaving, "a Peek closed while its tab is in the background has no keyboard to hand over")
}

@MainActor
func parentClosing() {
    do {
        let peek = Peek()
        peek.requestDismiss(.closeButton)
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        expect(peek.closeRequests == 0 && peek.transition.waitsForParent && peek.transition.cardHidden,
               "when the parent tab starts closing mid-fade, the Peek leaves its close to the tab's instead of asking itself")
        expect(!peek.reappeared && peek.transition.isLeaving, "the card stays gone while the tab closes")
        peek.apply(peek.transition.finish())
        expect(peek.effects.last == .vanish && peek.closeRequests == 0 && !peek.reappeared,
               "the Peek goes with its tab: no return flash and no second close")
    }

    do {
        let peek = Peek()
        peek.requestDismiss(.escape(prefersConfirmation: false))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        expect(peek.closeRequests == 1, "the fade's end asks the page to close")
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.cancelled()
        expect(!peek.reappeared && peek.transition.waitsForParent && peek.transition.phase == .closing,
               "a close the tab's close took over waits for the tab instead of springing the card back")
        let resumed = peek.transition.parentClosingChanged(false)
        expect(resumed == [.requestClose], "if the tab stays open without asking anything, the Peek's own close carries on")
        peek.apply(resumed)
        expect(peek.closeRequests == 2 && peek.transition.cardHidden && !peek.reappeared,
               "it asks the page once more, still invisible")
        expect(peek.transition.parentClosingChanged(false).isEmpty && peek.transition.parentClosingChanged(true).isEmpty,
               "repeated or newer tab notices can't ask again while that close is out")
    }

    do {
        let peek = Peek()
        peek.requestDismiss(.background)
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        peek.apply(peek.transition.sheetBegan(visible: true))
        expect(!peek.reappeared && peek.transition.cardHidden && peek.closeRequests == 0,
               "a Leave site? question from the tab's close leaves the handed-over card gone, so Leave takes it with no flash")
        let settled = peek.transition.parentClosingChanged(false)
        expect(settled == [.cancelClose], "if the tab then stays open, the Peek's close counts as refused, so nobody is asked twice")
        peek.apply(peek.transition.refused(visible: true))
        expect(peek.transition.phase == .resting && !peek.transition.cardHidden
               && peek.effects.filter { $0 == .reappear }.count == 1, "choosing Stay brings the card back once")
        expect(peek.transition.beginDrag(), "the Peek works normally afterwards")
    }

    do {
        let peek = Peek()
        peek.requestDismiss(.closeButton)
        peek.apply(peek.transition.sheetBegan(visible: true))
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        expect(!peek.reappeared && peek.transition.parentClosingChanged(false) == [.cancelClose],
               "a question asked while the card was still fading also counts")
        peek.apply(peek.transition.refused(visible: true))
        expect(peek.effects.last == .reappear && peek.transition.phase == .resting,
               "the invisible card the tab couldn't take fades back")
    }

    do {
        var transition = PeekCloseTransition()
        _ = transition.parentClosingChanged(true)
        expect(transition.close(visible: false, exit: .fade) == [.requestClose] && transition.holdForParent(),
               "a hidden Peek closed while its tab is closing waits too")
        expect(transition.hide().isEmpty && transition.waitsForParent, "hiding a waiting Peek changes nothing")
        expect(transition.parentClosingChanged(false) == [.requestClose] && !transition.waitsForParent,
               "it closes once the tab is done, so it is never left stranded")
        expect(!transition.holdForParent(), "with the tab done nothing holds the close")
    }

    do {
        var transition = PeekCloseTransition()
        _ = transition.parentClosingChanged(true)
        expect(!transition.holdForParent() && transition.parentClosingChanged(false).isEmpty,
               "a resting Peek has nothing to hold or resume")
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        expect(!transition.holdForParent(), "a card still fading isn't held; the fade's end decides")
        expect(transition.parentClosingChanged(false).isEmpty, "a tab close that ends during the fade resumes nothing")
        expect(transition.exitFinished(transition.generation) == [.requestClose] && !transition.holdForParent(),
               "and the Peek's own close then goes ahead normally")
    }

    do {
        let peek = Peek()
        peek.requestDismiss(.closeButton)
        peek.apply(peek.transition.parentClosingChanged(true))
        peek.apply(peek.transition.exitFinished(peek.transition.generation))
        expect(peek.transition.waitsForParent && peek.closeRequests == 0, "the Peek waits while its parent tab closes")
        expect(peek.transition.waitsForParent && peek.transition.phase == .closing,
               "when the tab's close ends with only the parent page gone, the Peek is still waiting, so orphan promotion can take it")
        peek.apply(peek.transition.finish())
        expect(peek.effects.last == .vanish && !peek.transition.waitsForParent && peek.transition.phase == .finished,
               "a waiting Peek promoted to its own tab retires its card cleanly")
        expect(peek.transition.parentClosingChanged(false).isEmpty && peek.closeRequests == 0 && !peek.reappeared,
               "the tab's late all-clear can't close or revive a Peek that was promoted")
    }

    do {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .fade)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        _ = transition.holdForParent()
        expect(transition.parentClosingChanged(false) == [.requestClose],
               "a Peek whose tab close ended by either route carries on as soon as it hears the all-clear")
        expect(transition.parentClosingChanged(true).isEmpty && !transition.waitsForParent,
               "a second tab close starting before that request is sent only holds it again when the request is made")
        expect(transition.holdForParent() && transition.parentClosingChanged(false) == [.requestClose],
               "and the second all-clear resumes it the same way")
    }

    do {
        var transition = PeekCloseTransition()
        _ = transition.close(visible: true, exit: .slide)
        _ = transition.parentClosingChanged(true)
        _ = transition.exitFinished(transition.generation)
        expect(transition.holdForParent(), "the Peek waits for its tab")
        expect(transition.refused(visible: true) == [.reappear] && !transition.waitsForParent,
               "a refusal that still arrives clears the wait, so a later tab notice can't close the Peek")
        expect(transition.parentClosingChanged(false).isEmpty, "the tab finishing afterwards does nothing")
    }
}

func motion() {
    let geometry = PeekDismissalMotion.Geometry(paneWidth: 508, cardMinX: 53)
    expect(geometry.exitDistance == 463 && geometry.paneWidth == 508,
           "the card is fully off once it has moved past the pane's right edge and its shadow")
    expect(PeekDismissalTiming.springDamping == 0.86 && PeekDismissalTiming.springResponse == 0.34
           && PeekDismissalTiming.slide == 0.22 && PeekDismissalTiming.fade == 0.2 && PeekDismissalTiming.reduced == 0.15,
           "the approved spring, slide, fade and Reduce Motion timings")

    var m = PeekDismissalMotion(geometry: geometry)
    expect(m.frame(at: 0) == .rest && !m.isAnimating(at: 0), "a new card rests in place, fully shown")
    m.begin(reducesMotion: false)
    m.follow(0.4)
    let drag = m.frame(at: 0)
    expect(close(Double(drag.offset), 0.4 * 463) && drag.card == 1 && close(drag.wash, 0.6),
           "the card slides with the fingers and the wash fades as it moves away")
    m.follow(1.4)
    expect(m.frame(at: 0).offset == 463 && m.frame(at: 0).wash == 0, "the card stops once it is fully off")
    m.follow(-0.2)
    expect(m.frame(at: 0) == PeekDismissalFrame(offset: 0, card: 1, wash: 1), "pulling past the start holds it at rest")

    m.follow(0.35)
    m.springBack(velocity: 0, at: 10)
    var lowest = CGFloat.infinity, previous = m.frame(at: 10).offset, monotonic = true
    for step in 1...60 {
        let frame = m.frame(at: 10 + Double(step) / 120)
        if frame.offset > previous + 1e-9 && frame.offset > 0 { monotonic = false }
        lowest = min(lowest, frame.offset)
        expect(close(frame.wash, 1 - min(max(Double(frame.offset) / 463, 0), 1)), "the wash returns with the card")
        previous = frame.offset
    }
    expect(monotonic && lowest == 0, "the spring brings the card home without passing its resting place")
    expect(!m.isAnimating(at: 11) && m.frame(at: 11) == .rest, "the spring settles within a second")

    var flung = PeekDismissalMotion(geometry: geometry)
    flung.begin(reducesMotion: false)
    flung.follow(0.3)
    flung.springBack(velocity: 2, at: 0)
    expect(flung.frame(at: 0.02).offset > 0.3 * 463, "a card let go while still moving out carries on briefly before returning")
    var thrown = PeekDismissalMotion(geometry: geometry)
    thrown.begin(reducesMotion: false)
    thrown.follow(0.5)
    thrown.springBack(velocity: -12, at: 0)
    var leftmost = CGFloat.infinity
    for step in 0...60 { leftmost = min(leftmost, thrown.frame(at: Double(step) / 120).offset) }
    expect(leftmost == 0 && thrown.frame(at: 2) == .rest, "a hard flick back lands the card at rest, never past it")

    var exit = PeekDismissalMotion(geometry: geometry)
    exit.begin(reducesMotion: false)
    exit.follow(0.62)
    let duration = exit.exit(.slide, velocity: 1.2, reducesMotion: false, at: 5)
    let start = 0.62 * 463.0, travel = 1.2 * 463 * 0.22 / 2
    let middle = exit.frame(at: 5.11)
    expect(duration == 0.22 && close(Double(middle.offset), start + travel * 0.75, 1e-3) && close(middle.card, 0.75)
           && close(middle.wash, 0.38 * 0.25, 1e-9), "the slide matches the approved mockup halfway through")
    let end = exit.frame(at: 5.2201)
    expect(end.card == 0 && end.wash == 0 && close(Double(end.offset), start + travel, 1e-3) && !exit.isAnimating(at: 5.2201),
           "the slide ends fully faded where it stopped")
    exit.complete(at: 5.3)
    expect(exit.frame(at: 6).card == 0, "settling a finished slide never brings the card back for a frame")

    var still = PeekDismissalMotion(geometry: geometry)
    _ = still.exit(.slide, velocity: 0, reducesMotion: false, at: 0)
    expect(close(Double(still.frame(at: 0.22).offset), 0.12 * 508, 1e-6),
           "a three-finger swipe or Magic Mouse close still slides a short way while it fades")
    var fast = PeekDismissalMotion(geometry: geometry)
    _ = fast.exit(.slide, velocity: 20, reducesMotion: false, at: 0)
    expect(close(Double(fast.frame(at: 0.22).offset), 0.5 * 508, 1e-6), "a very fast flick travels at most half the pane")

    var fade = PeekDismissalMotion(geometry: geometry)
    expect(fade.exit(.fade, velocity: 3, reducesMotion: false, at: 0) == 0.2, "Escape, a click outside or Close fade in 0.2 s")
    expect(fade.frame(at: 0.1).offset == 0 && close(fade.frame(at: 0.1).card, 0.25) && close(fade.frame(at: 0.1).wash, 0.25),
           "the quick fade dims card and wash together without moving")
    expect(fade.frame(at: 0.2).card == 0 && !fade.isAnimating(at: 0.2), "the quick fade ends invisible")
    fade.reappear(reducesMotion: false, at: 1)
    expect(fade.frame(at: 1.1).offset == 0 && fade.frame(at: 1.1).card > 0 && fade.frame(at: 1.2) == .rest,
           "a refused fade-out fades back in place")

    var back = PeekDismissalMotion(geometry: geometry)
    back.begin(reducesMotion: false)
    back.follow(0.64)
    _ = back.exit(.slide, velocity: 1.5, reducesMotion: false, at: 0)
    back.vanish(at: 0.22)
    let gone = back.frame(at: 0.22)
    expect(gone.card == 0 && gone.offset > 0.64 * 463, "a vanished card stays off and invisible")
    back.reappear(reducesMotion: false, at: 1)
    let early = back.frame(at: 1.06), later = back.frame(at: 1.14)
    expect(early.offset < gone.offset && early.card > 0 && early.card < 1 && later.card > early.card
           && close(early.wash, early.card), "a card the page refused to lose springs back in, fading up as it comes")
    expect(back.frame(at: 2) == .rest && !back.isAnimating(at: 2), "the spring-back from off-screen settles at rest")

    var reduced = PeekDismissalMotion(geometry: geometry)
    reduced.begin(reducesMotion: true)
    reduced.follow(0.5)
    expect(reduced.frame(at: 0) == PeekDismissalFrame(offset: 0, card: 0.65, wash: 0.5),
           "with Reduce Motion the fingers fade the card in place instead of sliding it")
    reduced.springBack(velocity: 2, at: 0)
    expect(reduced.frame(at: 0.075).offset == 0 && reduced.frame(at: 0.075).card > 0.65 && reduced.frame(at: 0.15) == .rest,
           "with Reduce Motion letting go early fades back in 0.15 s")
    reduced.follow(0.62)
    expect(reduced.exit(.slide, velocity: 3, reducesMotion: true, at: 1) == 0.15, "Reduce Motion fades out in 0.15 s")
    var offsets = Set<CGFloat>()
    for step in 0...10 { offsets.insert(reduced.frame(at: 1 + Double(step) * 0.015).offset) }
    expect(offsets == [0] && reduced.frame(at: 1.1501).card == 0, "nothing slides under Reduce Motion")
    reduced.reappear(reducesMotion: true, at: 2)
    expect(reduced.frame(at: 2.07).offset == 0 && reduced.frame(at: 2.1501) == .rest, "and a refused close fades back in place")

    var settled = PeekDismissalMotion(geometry: geometry)
    settled.begin(reducesMotion: false)
    settled.follow(0.5)
    settled.complete(at: 0)
    expect(settled.frame(at: 0).offset == 0.5 * 463, "settling other motion leaves a live drag under the fingers")
    settled.springBack(velocity: 0, at: 0)
    settled.complete(at: 0.01)
    expect(settled.frame(at: 0.01) == .rest, "settling a spring puts the card home at once")
    settled.follow(0.3)
    settled.settle()
    expect(settled.frame(at: 0) == .rest && !settled.isFollowing, "settle puts the card back at rest")
}

MainActor.assumeIsolated { exitOnFailure { run() } }
