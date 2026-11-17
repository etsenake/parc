import CoreGraphics
import Foundation

var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    precondition(condition(), message)
}

final class Thing {}

func same(_ changes: [ExtensionPopupActivityChange], _ expected: [(AnyObject, ExtensionPopupActivityPhase?)]) -> Bool {
    changes.count == expected.count && zip(changes, expected).allSatisfy { $0.control === $1.0 && $0.phase == $1.1 }
}

let first = Thing(), second = Thing(), third = Thing(), fourth = Thing()
let clicked = Thing(), toolbar = Thing(), pinned = Thing(), siteControls = Thing()
var tracker = ExtensionPopupActivityTracker()

check(same(tracker.place(popup: first, control: clicked), [(clicked, .loading)]),
      "a click lights its button as loading the moment its popup starts")
check(tracker.tracks(first), "the starting popup is the one being followed")
check(same(tracker.place(popup: first, control: clicked), []), "placing the same popup again changes nothing")
check(same(tracker.reveal(popup: first), [(clicked, .open)]), "the revealed popup turns its button open")
check(same(tracker.reveal(popup: first), []), "a second reveal changes nothing")

check(same(tracker.place(popup: second, control: toolbar), [(clicked, nil), (toolbar, .loading)]),
      "a replacing popup moves the lit state to its own button")
check(tracker.tracks(second) && !tracker.tracks(first), "only the replacing popup is followed")
check(same(tracker.reveal(popup: first), []) && same(tracker.end(popup: first), []),
      "the replaced popup's late reveal or close never touches the new button")
check(same(tracker.place(popup: first, control: clicked), []), "the replaced popup can't claim a button again")
var fading = ExtensionPopupActivityTracker()
let fadingPopup = Thing(), refusedPopup = Thing()
check(same(fading.place(popup: fadingPopup, control: clicked), [(clicked, .loading)])
          && same(fading.place(popup: refusedPopup, control: toolbar), [(clicked, nil), (toolbar, .loading)])
          && same(fading.end(popup: refusedPopup), [(toolbar, nil)]), "a quickly refused replacement lets go")
check(same(fading.place(popup: fadingPopup, control: clicked), []),
      "an older popup still fading out can't claim a button after a newer one was refused")

check(same(tracker.place(popup: second, control: pinned), [(toolbar, nil), (pinned, .loading)]),
      "a popup re-anchored while loading moves its loading state")
check(same(tracker.reveal(popup: second), [(pinned, .open)]), "the re-anchored button turns open on reveal")
check(same(tracker.place(popup: second, control: siteControls), [(pinned, nil), (siteControls, .open)]),
      "a popup re-anchored after reveal keeps its new button open")
check(same(tracker.place(popup: second, control: nil), [(siteControls, nil)]),
      "an anchor that can't show the state clears the old button")
check(same(tracker.place(popup: second, control: pinned), [(pinned, .open)]), "a later anchor picks the state back up")

check(same(tracker.end(popup: second), [(pinned, nil)]), "closing the popup lets its button go")
check(!tracker.tracks(second) && same(tracker.end(popup: second), []), "a second close changes nothing")
check(same(tracker.place(popup: second, control: pinned), []) && same(tracker.reveal(popup: second), []),
      "a closed popup never relights a button")

check(same(tracker.place(popup: third, control: clicked), [(clicked, .loading)]), "a new click starts fresh")
check(same(tracker.reveal(popup: third), [(clicked, .open)]), "the new popup opens")
check(same(tracker.place(popup: fourth, control: clicked), [(clicked, .loading)]),
      "reopening from the same button goes straight back to loading without dropping the light")
check(same(tracker.end(popup: fourth), [(clicked, nil)]), "a popup refused or closed before it appears lets go at once")

let unanchored = Thing()
check(same(tracker.place(popup: unanchored, control: nil), []), "a popup with no lightable anchor lights nothing")
check(same(tracker.reveal(popup: unanchored), []) && same(tracker.end(popup: unanchored), []),
      "an unanchored popup's reveal and close change nothing")

let fleeting = Thing()
do {
    let removed = Thing()
    check(same(tracker.place(popup: fleeting, control: removed), [(removed, .loading)]), "a soon-removed button lights")
}
check(same(tracker.end(popup: fleeting), []), "a button that went away is never touched again")

typealias Bounce = ExtensionPopupBounce
let step = 1.0 / 120
let past = 1e-6
func samples(_ from: Double, _ to: Double) -> [Double] { stride(from: from, through: to, by: step).map { $0 } }
func smooth(_ bounce: Bounce, _ from: Double, _ to: Double) -> Bool {
    let lifts = samples(from, to).map { bounce.lift(at: $0) }
    return zip(lifts, lifts.dropFirst()).allSatisfy { abs($0 - $1) <= 0.3 }
}

check(Bounce.cycle >= 0.6 && Bounce.cycle <= 0.9, "the hop repeats at a calm Dock-like rhythm")
check(Bounce.height >= 2 && Bounce.height <= (24 - 16) / 2,
      "the hop is a few points and keeps the 16-point icon inside even the 24-point toolbar button")
let curve = stride(from: 0.0, through: 1.0, by: 0.001).map { Bounce.lift(atHopProgress: $0) }
check(curve.allSatisfy { $0 >= 0 && $0 <= Bounce.height } && abs((curve.max() ?? 0) - Bounce.height) < 0.001,
      "a hop rises exactly to its height and never dips below the resting place")
check(Bounce.lift(atHopProgress: 0) == 0 && Bounce.lift(atHopProgress: 1) == 0, "a hop starts and ends on the ground")
let launch = Bounce.lift(atHopProgress: 0.02) / 0.02, touchdown = Bounce.lift(atHopProgress: 0.98) / 0.02
check(launch > 8 * touchdown && Bounce.lift(atHopProgress: 0.98) < 0.02, "a springy take-off and a soft landing")

let bouncing = Bounce(start: 10)
check(samples(10, 10 + Bounce.delay).allSatisfy { bouncing.lift(at: $0) == 0 },
      "a popup that opens almost at once never hops")
check(samples(11, 12).allSatisfy { abs(bouncing.lift(at: $0) - bouncing.lift(at: $0 + Bounce.cycle)) < 0.0001 },
      "the hop keeps repeating while the popup loads")
check(smooth(bouncing, 10, 13) && !bouncing.isFinished(at: 30), "the loading bounce glides and never stops on its own")
check(samples(10, 13).contains { bouncing.lift(at: $0) > 0 } && samples(10, 13).contains { bouncing.lift(at: $0) == 0 },
      "each hop lands for a breather before the next")

let midHop = 10 + Bounce.delay + Bounce.cycle + 0.2
var landing = bouncing
landing.land(at: midHop)
let touchdownTime = 10 + Bounce.delay + Bounce.cycle + Bounce.hop
check(abs(landing.landingTime(after: midHop) - touchdownTime) < 0.0001 && !landing.isFinished(at: touchdownTime - 0.01),
      "a revealed popup lets the icon finish its current hop")
check(samples(midHop, touchdownTime - 0.001).allSatisfy { landing.lift(at: $0) == bouncing.lift(at: $0) },
      "the finishing hop follows the same arc instead of cutting off mid-air")
check(landing.isFinished(at: touchdownTime + past)
          && samples(touchdownTime + past, touchdownTime + 2).allSatisfy { landing.lift(at: $0) == 0 },
      "the icon stays down once it lands")
check(smooth(landing, midHop - 0.5, touchdownTime + 0.5), "the landing is smooth")

var resting = bouncing
let restTime = 10 + Bounce.delay + Bounce.hop + 0.05
resting.land(at: restTime)
check(resting.isFinished(at: restTime) && resting.lift(at: restTime + 0.1) == 0,
      "a popup revealed between hops stops the bounce right there")

var quick = Bounce(start: 10)
quick.land(at: 10.1)
check(quick.isFinished(at: 10.1) && samples(10.1, 12).allSatisfy { quick.lift(at: $0) == 0 },
      "a very fast popup skips the bounce")

let apex = 10 + Bounce.delay + Bounce.hop * Bounce.rise
var dropped = bouncing
dropped.drop(at: apex)
check(abs(dropped.lift(at: apex) - Bounce.height) < 0.0001, "a failure lands the icon from exactly where it is")
check(zip(samples(apex, apex + Bounce.drop), samples(apex, apex + Bounce.drop).dropFirst())
          .allSatisfy { dropped.lift(at: $1) <= dropped.lift(at: $0) },
      "a failure brings the icon straight down")
check(dropped.isFinished(at: apex + Bounce.drop + past) && dropped.lift(at: apex + Bounce.drop + past) == 0
          && !dropped.isFinished(at: apex + Bounce.drop - 0.01),
      "a failure lands the icon quickly and cleanly")
check(apex + Bounce.drop < 10 + Bounce.delay + Bounce.hop, "a failure lands sooner than finishing the hop would")
check(smooth(dropped, apex - 0.2, apex + 0.5), "a failure's landing doesn't jump")

var grounded = bouncing
grounded.drop(at: restTime)
check(grounded.isFinished(at: restTime), "a failure while the icon rests ends the bounce at once")

var resumed = landing
resumed.resume(at: midHop + 0.1)
check(samples(midHop, midHop + 3).allSatisfy { resumed.lift(at: $0) == bouncing.lift(at: $0) } && !resumed.isFinished(at: 40),
      "loading again while landing keeps the same rhythm going")

var recovered = dropped
recovered.resume(at: apex + 0.05)
check(abs(recovered.lift(at: apex + 0.05) - dropped.lift(at: apex + 0.05)) < 0.0001
          && samples(apex + Bounce.drop + past, apex + Bounce.drop + Bounce.delay - past).allSatisfy { recovered.lift(at: $0) == 0 },
      "loading again mid-landing finishes the landing, then pauses before hopping")
check(samples(apex, apex + 2).contains { $0 > apex + Bounce.drop + Bounce.delay && recovered.lift(at: $0) > 0 }
          && smooth(recovered, apex, apex + 2),
      "the restarted bounce hops again smoothly")
var settled = recovered
settled.land(at: apex + 0.08)
check(settled.isFinished(at: apex + Bounce.drop + past) && settled.lift(at: apex + 1) == 0,
      "a reveal during that landing keeps the icon down")

typealias Fade = ExtensionPopupActivityFade
var fade = Fade()
check(fade.value(at: 0) == 0 && fade.isFinished(at: 0), "the fill starts off")
fade.retarget(1, at: 5)
let lighting = samples(5, 5 + Fade.lighten).map { fade.value(at: $0) }
check(zip(lighting, lighting.dropFirst()).allSatisfy { $1 >= $0 } && fade.value(at: 5 + Fade.lighten + past) == 1,
      "the fill eases in")
check(fade.value(at: 5.05) > 0 && fade.value(at: 5.05) < 1 && !fade.isFinished(at: 5.05), "the fill doesn't snap")
let partway = fade.value(at: 5.09)
fade.retarget(0, at: 5.09)
check(fade.value(at: 5.09) == partway && fade.value(at: 5.1) < partway, "a change mid-fade turns back from the current fill")
check(fade.value(at: 5.09 + Fade.dim + past) == 0 && fade.isFinished(at: 5.09 + Fade.dim + past), "the fill eases out")

typealias Motion = ExtensionPopupActivityMotion
var motion = Motion()
motion.show(.loading, at: 0, reduceMotion: false)
check(motion.frame(at: 0, reduceMotion: false) == ExtensionPopupActivityFrame(fill: 0, lift: 0, finished: false),
      "loading starts lighting and bouncing")
check(motion.frame(at: 1, reduceMotion: false).fill == 1 && !motion.frame(at: 5, reduceMotion: false).finished,
      "the button stays lit and bouncing while the popup loads")
let revealAt = Bounce.delay + 0.1
motion.show(.open, at: revealAt, reduceMotion: false)
let landed = Bounce.delay + Bounce.hop
check(!motion.frame(at: landed - 0.01, reduceMotion: false).finished
          && motion.frame(at: landed - 0.01, reduceMotion: false).lift > 0,
      "an open popup's button finishes its hop")
check(motion.frame(at: landed + past, reduceMotion: false) == ExtensionPopupActivityFrame(fill: 1, lift: 0, finished: true),
      "an open popup's button rests lit")
motion.show(nil, at: 3, reduceMotion: false)
check(motion.frame(at: 3 + Fade.dim + past, reduceMotion: false) == ExtensionPopupActivityFrame(fill: 0, lift: 0, finished: true),
      "closing the popup eases the light out")

var refused = Motion()
refused.show(.loading, at: 0, reduceMotion: false)
refused.show(nil, at: 0, reduceMotion: false)
check(refused.frame(at: 0, reduceMotion: false) == ExtensionPopupActivityFrame(fill: 0, lift: 0, finished: true),
      "a popup refused right away never flashes the button")

var failing = Motion()
failing.show(.loading, at: 0, reduceMotion: false)
failing.show(nil, at: apex - 10, reduceMotion: false)
check(failing.frame(at: apex - 10, reduceMotion: false).lift > 2.9
          && failing.frame(at: apex - 10 + Bounce.drop + past, reduceMotion: false).lift == 0
          && failing.frame(at: apex - 10 + Fade.dim + past, reduceMotion: false).finished,
      "a failure mid-hop lands the icon and lets the light go together")

var again = Motion()
again.show(.loading, at: 0, reduceMotion: false)
again.show(.open, at: revealAt, reduceMotion: false)
again.show(.loading, at: revealAt + 0.1, reduceMotion: false)
check(!again.frame(at: 10, reduceMotion: false).finished && again.frame(at: revealAt + 0.1, reduceMotion: false).fill == 1,
      "a replacing popup from the same button keeps it lit and bouncing")

var still = Motion()
still.show(.loading, at: 0, reduceMotion: true)
check(samples(0, 3).allSatisfy { still.frame(at: $0, reduceMotion: true).lift == 0 }
          && still.frame(at: Fade.lighten + past, reduceMotion: true) == ExtensionPopupActivityFrame(fill: 1, lift: 0, finished: true),
      "Reduce Motion keeps the light and drops the bounce")
var turnedOn = Motion()
turnedOn.show(.loading, at: 0, reduceMotion: false)
check(turnedOn.frame(at: apex - 10, reduceMotion: true).lift == 0, "turning on Reduce Motion mid-hop stops the bounce")

print("extension popup activity: \(assertions) assertions passed")
