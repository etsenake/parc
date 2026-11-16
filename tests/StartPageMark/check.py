#!/usr/bin/env python3
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
here = Path(__file__).parent
eggs = [app / f"StartPageMark{name}.swift" for name in ("EasterEgg", "Gesture", "Motion", "Taffy", "Swoop", "Charge", "Stage")]
builds = {
    "model": eggs + [here / "main.swift"],
    "view": [root / "Sources/ParcCore/SpaceTheme.swift", app / "StartPageMarkView.swift"] + eggs
            + [here / "ViewStandIns.swift", here / "view.swift"],
}

mark = (app / "StartPageMarkView.swift").read_text()
for use in ("override var mouseDownCanMoveWindow: Bool { false }", "RunLoop.main.add(timer, forMode: .common)",
            "recognizer.clickInterval = NSEvent.doubleClickInterval", "idle: session.isIdle",
            "NSWorkspace.shared.accessibilityDisplayShouldReduceMotion", "case .haptic:\n                ThemeHapticFeedback.perform()",
            "case .reset:\n                motion?.reset()", "stopInteraction()\n        super.viewWillMove(toWindow: newWindow)",
            "if !activity.canAnimate { stopInteraction() }", "abandonInteraction()\n        recognizer.clickInterval",
            "if case .interacting = session.phase { stopInteraction() }", "forName: NSWindow.didResignKeyNotification",
            "guard NSEvent.pressedMouseButtons & 1 != 0 else { return stopInteraction() }"):
    assert use in mark, f"StartPageMarkView no longer wires the checked behaviour: {use}"
assert mark.count("Timer(") == 1, "the mark keeps a single one-shot timer for the hold threshold"


def build(directory, target, name, replace=None):
    files = list(builds[target])
    if replace:
        source, old, new = replace
        text = (app / source).read_text()
        assert text.count(old) == 1, f"negative control no longer matches {source}: {old}"
        changed = Path(directory) / f"{name}-{source}"
        changed.write_text(text.replace(old, new))
        files = [changed if path == app / source else path for path in files]
    executable = Path(directory) / f"{target}-{name}"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    *map(str, files), "-o", str(executable)], check=True)
    return executable


controls = {
    "no slop": ("model", ("StartPageMarkGesture.swift", "guard hypot(drag.dx, drag.dy) > Self.slop else { break }",
                          "guard hypot(drag.dx, drag.dy) >= 0 else { break }"), "a jitter inside the slop does not start the stretch"),
    "double click swoops": ("model", ("StartPageMarkGesture.swift", "static let clicksToSwoop = 3", "static let clicksToSwoop = 2"),
                            "two clicks do nothing"),
    "slow triple": ("model", ("StartPageMarkGesture.swift", "time - $0.released <= clickInterval &&", "true &&"),
                    "a slow third click does not swoop"),
    "far triple": ("model", ("StartPageMarkGesture.swift", "Self.distance($0.origin, point) <= Self.clickRadius ? $0 : nil",
                             "true ? $0 : nil"), "a third click away from the first does not swoop"),
    "busy press counts": ("model", ("StartPageMarkGesture.swift", "guard idle else {", "guard idle || true else {"),
                          "an ignored press arms no hold"),
    "late drag stretches": ("model", ("StartPageMarkGesture.swift",
                                      "    mutating func pointerDragged(to point: CGPoint, time: TimeInterval) -> [StartPageMarkCue] {\n"
                                      "        var cues = advance(to: time)",
                                      "    mutating func pointerDragged(to point: CGPoint, time: TimeInterval) -> [StartPageMarkCue] {\n"
                                      "        var cues: [StartPageMarkCue] = []"),
                            "movement after the hold threshold charges rather than stretching"),
    "charge ignores movement": ("model", ("StartPageMarkGesture.swift", "guard Self.distance(origin, point) > Self.chargeSlop else { break }",
                                          "guard Self.distance(origin, point) > .infinity else { break }"),
                                "moving past the charge slop cancels the charge quietly"),
    "stacking": ("model", ("StartPageMarkEasterEgg.swift", "case (.begin(let egg), .rest):", "case (.begin(let egg), _):"),
                 "a trigger during playback is ignored"),
    "stale completion": ("model", ("StartPageMarkEasterEgg.swift", "guard finished == generation, case .playing = phase",
                                   "guard case .playing = phase"), "a stale completion cannot end a newer play"),
    "double landing tick": ("model", ("StartPageMarkEasterEgg.swift", "        landing = false\n        return [.haptic]",
                                      "        return [.haptic]"), "the landing ticks once"),
    "undercharged loop": ("model", ("StartPageMarkEasterEgg.swift", "guard StartPageMarkCharge.launches(level) else", "guard true else"),
                          "an undercharged release relaxes without a loop"),
    "motion ignores Reduce Motion": ("model", ("StartPageMarkEasterEgg.swift", "self = reduceMotion ? .shimmer : .motion", "self = .motion"),
                                     "Reduce Motion selects the shimmer"),
    "swoop ignores Reduce Motion": ("model", ("StartPageMarkEasterEgg.swift",
                                              "return style == .motion ? [.play(.swoop)] : [.shimmer, .haptic]", "return [.play(.swoop)]"),
                                    "Reduce Motion replaces the swoop with the shimmer"),
    "loop ignores Reduce Motion": ("model", ("StartPageMarkEasterEgg.swift",
                                             "return style == .motion ? [.play(.loop)] : [.shimmer, .haptic]", "return [.play(.loop)]"),
                                   "Reduce Motion replaces the loop with the shimmer"),
    "occluded animates": ("model", ("StartPageMarkEasterEgg.swift", "windowVisible && !occluded && !miniaturized && !hidden",
                                    "windowVisible && !miniaturized && !hidden"), "an occluded window pauses"),
    "paused window plays": ("model", ("StartPageMarkEasterEgg.swift", "guard canAnimate else { return pause() }", ""),
                            "a trigger in a paused window is skipped"),
    "pause keeps effects": ("model", ("StartPageMarkStage.swift", "        StartPageMarkShimmer.reset(shimmer)\n        removeEffects()",
                                      "        StartPageMarkShimmer.reset(shimmer)"), "pausing removes the ribbon"),
    "stale flight lands": ("model", ("StartPageMarkStage.swift",
                                     "key: Self.swoopKey, frame: frame) { [weak self] in\n            guard let self, self.token == token else { return }",
                                     "key: Self.swoopKey, frame: frame) { [weak self] in\n            guard let self else { return }"),
                           "a paused swoop never lands or ticks afterwards"),
    "ribbon over the mark": ("model", ("StartPageMarkSwoop.swift", ".first { !covers(point($0), home: home, mark: mark, pose: markPose) }",
                                       ".first { covers(point($0), home: home, mark: mark, pose: markPose) || true }"),
                             "the ribbon starts behind the mark"),
    "pose ignores flip": ("model", ("StartPageMarkMotion.swift", "let flip: CGFloat = frame.yDown ? 1 : -1", "let flip: CGFloat = 1"),
                          "an upward layer space mirrors the pose"),
    "landing at centre": ("model", ("StartPageMarkMotion.swift",
                                    "StartPageMarkPose(scale: CGSize(width: 1 + spread * squash, height: 1 - squash), origin: StartPageMarkPose.bottom)",
                                    "StartPageMarkPose(scale: CGSize(width: 1 + spread * squash, height: 1 - squash))"),
                          "the landing squashes onto its base"),
    "unanchored stretch": ("model", ("StartPageMarkTaffy.swift", "+ ux * stretch / 2", "+ ux * stretch"),
                           "the far edge follows the pointer by the stretch"),
    "flat taffy": ("model", ("StartPageMarkTaffy.swift", "let across = 1 / along.squareRoot()", "let across: CGFloat = 1"),
                   "the mark thins across the pull like taffy"),
    "overdamped": ("model", ("StartPageMarkTaffy.swift", "static let dampingRatio = 0.3", "static let dampingRatio = 0.95"),
                   "the release wobbles past home"),
    "ignores layer flip": ("model", ("StartPageMarkTaffy.swift", "yDown: stage.superlayer?.contentsAreFlipped() ?? true", "yDown: true"),
                           "tracking mirrors the pull in an upward superlayer"),
    "dropped swipe": ("view", ("StartPageMarkView.swift", "renderer.pagingTransition = paging", "renderer.pagingTransition = nil"),
                      "a swipe reaches the mark's gradient"),
    "untextured swipe": ("view", ("StartPageMarkView.swift", "renderer.pagingTransition = paging",
                                  "renderer.pagingTransition = paging.map { var plain = $0; plain.from.noise = 0; plain.theme.noise = 0; return plain }"),
                         "the mark's gradient keeps its texture through a swipe"),
    "stale tint": ("view", ("StartPageMarkView.swift", "inkColor = StartPageMarkTint.blend(inks.from, inks.to, progress: paging.progress)",
                            "inkColor = inks.from"), "the mark's tint blends through a swipe"),
    "colourless side hides gradient": ("view", ("StartPageMarkView.swift",
                                                "pagingHasColor: paging.map { (Self.hasColor($0.from), Self.hasColor($0.theme)) }",
                                                "pagingHasColor: nil"), "a swipe from a colourless Space shows the incoming gradient"),
}

with tempfile.TemporaryDirectory(prefix="parc-start-page-mark-") as directory:
    with ThreadPoolExecutor() as pool:
        mains = [pool.submit(build, directory, target, "check") for target in builds]
        built = {name: pool.submit(build, directory, target, name.replace(" ", "-"), replace)
                 for name, (target, replace, _) in controls.items()}
    for main in mains:
        subprocess.run([str(main.result())], check=True)
    for name, (target, replace, failure) in controls.items():
        result = subprocess.run([str(built[name].result())], capture_output=True, text=True)
        assert result.returncode >= 0, f"negative control crashed with signal {-result.returncode} instead of failing: {name}\n{result.stderr[-1000:]}"
        assert result.returncode != 0 and failure in result.stderr, f"negative control did not fail: {name}\n{result.stderr[-1000:]}"
        print(f"StartPageMark negative control fails as expected: {name}")
