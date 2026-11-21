import AppKit
import Combine
import Testing
import ParcCore
@testable import Parc

@MainActor
private func editorControl(_ label: String, in view: NSView) throws -> NSView {
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    return try #require(descendants(view).first { $0.accessibilityLabel() == label })
}

@MainActor
private func themeMouse(_ type: NSEvent.EventType, in view: NSView, at point: NSPoint) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [],
                                   timestamp: 30, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
}

@MainActor
private func themeButton(_ label: String, in view: NSView) throws -> NSButton {
    try #require(try editorControl(label, in: view) as? NSButton)
}

private final class EditorGesture: NSEvent {
    let gesturePhase: NSEvent.Phase
    let gestureMomentum: NSEvent.Phase
    let degrees: Float
    let delta: CGFloat
    let time: TimeInterval
    let point: NSPoint

    @MainActor init(in view: NSView, phase: NSEvent.Phase, momentum: NSEvent.Phase = [], degrees: Float = 0, delta: CGFloat = 0) {
        gesturePhase = phase
        gestureMomentum = momentum
        self.degrees = degrees
        self.delta = delta
        time = 30
        point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var phase: NSEvent.Phase { gesturePhase }
    override var momentumPhase: NSEvent.Phase { gestureMomentum }
    override var locationInWindow: NSPoint { point }
    override var rotation: Float { degrees }
    override var scrollingDeltaY: CGFloat { delta }
    override var timestamp: TimeInterval { time }
}

struct SpaceThemeHapticTests {
    @Test(arguments: [(0.21, 0.29, false), (0.19, 0.2, true), (0.2, 0.21, true),
                      (0.21, 0.19, true), (0.05, 0.95, true), (0.2, 0.2, false)])
    func physicalRotationPulsesWhenCrossingANoiseDetent(example: (Double, Double, Bool)) {
        #expect(ThemeHapticFeedback.shouldPerformNoise(from: example.0, to: example.1, gesture: .rotation) == example.2)
    }

    @Test(arguments: [SpaceThemeNoiseGesture.slider, .dialClick, .scrollWheel])
    func discreteNoiseChangesDoNotPulse(gesture: SpaceThemeNoiseGesture) {
        #expect(!ThemeHapticFeedback.shouldPerformNoise(from: 0, to: 1, gesture: gesture))
    }

    @Test(arguments: [(0.21, 0.39, false), (0.39, 0.4, true), (0.4, 0.41, true), (0.41, 0.39, true),
                      (0.0, 0.01, true), (0.99, 1.0, true), (1.0, 1.0, false), (Double.nan, 0.4, false),
                      (0.4, Double.infinity, false)])
    func intensityPulsesAtItsOwnDetents(example: (Double, Double, Bool)) {
        #expect(ThemeHapticFeedback.shouldPerformIntensity(from: example.0, to: example.1) == example.2)
    }

    @Test @MainActor func anIntensityDragAcrossSeveralDetentsPulsesOnce() throws {
        _ = NSApplication.shared
        var baseline = SpaceTheme()
        baseline.intensity = 0.1
        var pulses = 0
        let editor = SpaceThemeEditorView(theme: baseline, performHapticFeedback: { pulses += 1 })
        editor.layoutSubtreeIfNeeded()
        let intensity = try editorControl("Theme intensity", in: editor)
        let start = NSPoint(x: 20 + (intensity.bounds.width - 40) * 0.1, y: intensity.bounds.midY)
        let end = NSPoint(x: 20 + (intensity.bounds.width - 40) * 0.9, y: intensity.bounds.midY)
        intensity.mouseDown(with: try themeMouse(.leftMouseDown, in: intensity, at: start))
        let before = pulses
        intensity.mouseDragged(with: try themeMouse(.leftMouseDragged, in: intensity, at: end))
        intensity.mouseUp(with: try themeMouse(.leftMouseUp, in: intensity, at: end))
        #expect(pulses == before + 1)
    }

    @Test @MainActor func aPhysicalNoiseRotationPulsesWithoutRepeatingAtRelease() throws {
        _ = NSApplication.shared
        var initial = SpaceTheme()
        initial.noise = 0.15
        var pulses = 0
        let editor = SpaceThemeEditorView(theme: initial, performHapticFeedback: { pulses += 1 })
        editor.layoutSubtreeIfNeeded()
        let noise = try editorControl("Theme texture and noise", in: editor)
        noise.rotate(with: EditorGesture(in: noise, phase: .began))
        noise.rotate(with: EditorGesture(in: noise, phase: .changed, degrees: 180))
        #expect(pulses == 1)
        noise.rotate(with: EditorGesture(in: noise, phase: .ended))
        #expect(pulses == 1)
    }
}

struct SpaceThemeInputTests {
    @MainActor private final class ScrollDelivery {
        var latest: (() -> Void)?

        func hold(_ input: AnyPublisher<Double, Never>) -> AnyPublisher<Double, Never> {
            let output = PassthroughSubject<Double, Never>()
            let upstream = input.sink { [weak self, weak output] value in
                self?.latest = { [weak output] in output?.send(value) }
            }
            return output.handleEvents(receiveCancel: { upstream.cancel() }).eraseToAnyPublisher()
        }

        func deliver() {
            let work = latest
            latest = nil
            work?()
        }
    }

    @MainActor private func editor(theme: SpaceTheme = SpaceTheme(), delivery: ScrollDelivery? = nil) -> SpaceThemeEditorView {
        _ = NSApplication.shared
        let view = SpaceThemeEditorView(theme: theme, scrollPublisher: delivery.map { $0.hold },
                                        scrollTime: { 30 }, performHapticFeedback: {})
        view.layoutSubtreeIfNeeded()
        return view
    }

    @Test @MainActor func aColorPadDragPreviewsUntilThePointerReleases() throws {
        let view = editor()
        let pad = try editorControl("Theme color pad", in: view)
        let start = CGPoint(x: pad.bounds.width * 0.8, y: pad.bounds.midY)
        let end = CGPoint(x: pad.bounds.width * 0.7, y: pad.bounds.height * 0.7)
        var commits: [SpaceTheme] = []
        view.onCommit = { commits.append($0) }
        pad.mouseDown(with: try themeMouse(.leftMouseDown, in: pad, at: start))
        pad.mouseDragged(with: try themeMouse(.leftMouseDragged, in: pad, at: end))
        #expect(view.theme.colorCount == 1)
        #expect(commits.isEmpty)
        pad.mouseUp(with: try themeMouse(.leftMouseUp, in: pad, at: end))
        #expect(commits == [view.theme])
    }

    @Test @MainActor func parentReplacementRejectsTheRemainderOfAnOldColorDrag() throws {
        let view = editor()
        let pad = try editorControl("Theme color pad", in: view)
        let point = CGPoint(x: pad.bounds.width * 0.8, y: pad.bounds.midY)
        pad.mouseDown(with: try themeMouse(.leftMouseDown, in: pad, at: point))
        var replacement = SpaceTheme()
        replacement.intensity = 0.3
        view.synchronizeTheme(replacement)
        view.onCommit = { _ in Issue.record("The old drag committed after replacement") }
        pad.mouseDragged(with: try themeMouse(.leftMouseDragged, in: pad, at: .zero))
        pad.mouseUp(with: try themeMouse(.leftMouseUp, in: pad, at: .zero))
        #expect(view.theme == replacement)
    }

    @Test @MainActor func discreteNoiseInputCommitsSeparatelyFromARotation() throws {
        let view = editor()
        let noise = try editorControl("Theme texture and noise", in: view)
        noise.rotate(with: EditorGesture(in: noise, phase: .began, degrees: 72))
        #expect(noise.accessibilityPerformIncrement())
        #expect(abs(view.theme.noise - 0.15) < 0.000001)
        noise.rotate(with: EditorGesture(in: noise, phase: .changed, degrees: 72))
        noise.rotate(with: EditorGesture(in: noise, phase: .ended))
        #expect(abs(view.theme.noise - 0.15) < 0.000001)
        view.undo(nil)
        #expect(abs(view.theme.noise - 0.1) < 0.000001)
    }

    @Test @MainActor func noiseRotationBelowTheGestureThresholdDoesNotEdit() throws {
        let view = editor()
        let noise = try editorControl("Theme texture and noise", in: view)
        noise.rotate(with: EditorGesture(in: noise, phase: .began, degrees: 0.5))
        noise.rotate(with: EditorGesture(in: noise, phase: .ended))
        #expect(view.theme.noise == 0)
    }

    @Test(arguments: [(1.0, 0.65), (-100.0, 0.4), (0.0, 0.5)])
    @MainActor func deliveredWheelDirectionMakesOneQuantizedNoiseStep(example: (Double, Double)) throws {
        let delivery = ScrollDelivery()
        var theme = SpaceTheme()
        theme.noise = 0.5
        let view = editor(theme: theme, delivery: delivery)
        let noise = try editorControl("Theme texture and noise", in: view)
        let center = CGPoint(x: noise.bounds.midX, y: noise.bounds.midY)
        noise.mouseMoved(with: try themeMouse(.mouseMoved, in: noise, at: center))
        noise.scrollWheel(with: EditorGesture(in: noise, phase: .began, delta: example.0))
        #expect(view.theme == theme)
        delivery.deliver()
        #expect(abs(view.theme.noise - example.1) < 0.000001)
    }

    @Test @MainActor func finishingTheEditorCancelsQueuedWheelInput() throws {
        let delivery = ScrollDelivery()
        let view = editor(delivery: delivery)
        let noise = try editorControl("Theme texture and noise", in: view)
        let center = CGPoint(x: noise.bounds.midX, y: noise.bounds.midY)
        noise.mouseMoved(with: try themeMouse(.mouseMoved, in: noise, at: center))
        noise.scrollWheel(with: EditorGesture(in: noise, phase: .began, delta: 1))
        view.finishEditing()
        delivery.deliver()
        #expect(view.theme.noise == 0)
    }

    @Test @MainActor func aQueuedWheelStepChecksWhereThePointerIsAtDelivery() throws {
        let delivery = ScrollDelivery()
        let view = editor(delivery: delivery)
        let noise = try editorControl("Theme texture and noise", in: view)
        let center = CGPoint(x: noise.bounds.midX, y: noise.bounds.midY)
        noise.mouseMoved(with: try themeMouse(.mouseMoved, in: noise, at: center))
        noise.scrollWheel(with: EditorGesture(in: noise, phase: .began, delta: 1))
        noise.mouseExited(with: try themeMouse(.mouseMoved, in: noise, at: .zero))
        delivery.deliver()
        #expect(view.theme.noise == 0)
    }

    @Test(arguments: [0, 1, 4])
    @MainActor func openingTheEditorRestoresTheOwnersPresetPage(page: Int) throws {
        _ = NSApplication.shared
        let view = SpaceThemeEditorView(theme: SpaceTheme(), presetPage: page, performHapticFeedback: {})
        let previous = try themeButton("Previous color presets", in: view)
        let next = try themeButton("Next color presets", in: view)
        #expect(previous.isEnabled == (page > 0))
        #expect(next.isEnabled == (page < 4))
    }
}

@Suite(.serialized)
struct SpaceThemeAppearanceTests {
    @MainActor private func withAppearance(_ body: (UserDefaults) throws -> Void) throws {
        _ = NSApplication.shared
        let initial = NSApp.appearance
        let name = "parc.appearance.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer {
            NSApp.appearance = initial
            defaults.removePersistentDomain(forName: name)
        }
        try body(defaults)
    }

    @Test(arguments: ["automatic", "light", "dark"])
    @MainActor func editorAppearanceControlsDelegateWithoutEditingTheSpace(value: String) throws {
        try withAppearance { defaults in
            let choice = try #require(AppAppearance(rawValue: value))
            AppAppearance.apply(choice == .dark ? .light : .dark, defaults: defaults)
            let theme = SpaceTheme.singleColor(try #require(ThemeColor(hex: "4C6688")))
            let editor = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
            var requested: AppAppearance?
            editor.onSetAppearance = { requested = $0; AppAppearance.apply($0, defaults: defaults) }
            editor.onCommit = { _ in Issue.record("Changing app appearance committed a theme") }
            editor.onPreview = { _ in Issue.record("Changing app appearance previewed a theme") }
            let button = try themeButton("\(choice.title) appearance", in: editor)
            _ = NSApp.sendAction(try #require(button.action), to: button.target, from: button)
            #expect(requested == choice && AppAppearance.current == choice)
            #expect(editor.theme == theme)
            #expect(button.accessibilityValue() as? Int == 1)
        }
    }

    @Test @MainActor func automaticAppearanceClearsAStaleSavedOverride() throws {
        try withAppearance { defaults in
            AppAppearance.apply(.dark, defaults: defaults)
            NSApp.appearance = nil
            #expect(!AppAppearance.apply(.automatic, defaults: defaults))
            #expect(defaults.string(forKey: "parc.appAppearance.v1") == nil)
        }
    }

    @Test @MainActor func cancellingReplayAppearanceRestoresTheSavedChoice() throws {
        try withAppearance { defaults in
            AppAppearance.apply(.dark, defaults: defaults)
            AppAppearance.preview(.light)
            #expect(AppAppearance.endPreview(.light, defaults: defaults))
            #expect(AppAppearance.current == .dark)
        }
    }

    @Test @MainActor func cancellingReplayAppearanceKeepsAnExternalChoice() throws {
        try withAppearance { defaults in
            AppAppearance.apply(.dark, defaults: defaults)
            AppAppearance.preview(.light)
            AppAppearance.apply(.automatic, defaults: defaults)
            #expect(!AppAppearance.endPreview(.light, defaults: defaults))
            #expect(AppAppearance.current == .automatic)
        }
    }
}

extension SpaceThemeInputTests {
    @Test(arguments: [(0.995, 0.5, 0.0), (0.5, 0.995, 0.25)])
    @MainActor func thePadMapsItsRightAndDownAxesToTheExpectedHue(pointAndHue: (Double, Double, Double)) throws {
        let view = editor()
        let pad = try editorControl("Theme color pad", in: view)
        let point = CGPoint(x: pad.bounds.width * pointAndHue.0, y: pad.bounds.height * pointAndHue.1)
        pad.mouseDown(with: try themeMouse(.leftMouseDown, in: pad, at: point))
        let primary = try #require(view.theme.primaryColor)
        #expect(abs(primary.hsl.hue - pointAndHue.2) < 0.000001)
        #expect(abs(primary.hsl.lightness - 0.97) < 0.000001)
        pad.mouseUp(with: try themeMouse(.leftMouseUp, in: pad, at: point))
    }

    @Test @MainActor func draggingALinkedColorKeepsTheOffsetFromItsHandle() throws {
        let primary = try #require(ThemeColor.hsl(hue: 0, saturation: 0.7, lightness: 0.5, colorSpace: .displayP3))
        var theme = SpaceTheme.singleColor(primary)
        theme.colorCount = 2
        theme.wheel = .complimentary
        let view = editor(theme: theme)
        let pad = try editorControl("Theme color pad", in: view)
        let expected = SpaceThemeEditorState(theme: theme)
        let position = expected.normalizedPosition(for: theme.colors[1])
        let center = CGPoint(x: (position.x + 1) * pad.bounds.midX, y: (position.y + 1) * pad.bounds.midY)
        let pointer = CGPoint(x: center.x + 3, y: center.y + 2)
        pad.mouseDown(with: try themeMouse(.leftMouseDown, in: pad, at: pointer))
        let translated = CGPoint(x: pointer.x + 12, y: pointer.y + 20)
        pad.mouseDragged(with: try themeMouse(.leftMouseDragged, in: pad, at: translated))
        expected.moveColor(x: (center.x + 12 - pad.bounds.midX) / pad.bounds.midX,
                           y: (center.y + 20 - pad.bounds.midY) / pad.bounds.midY)
        let selected = try #require(view.theme.primaryColor)
        let target = try #require(expected.theme.primaryColor)
        #expect(abs(selected.hsl.hue - target.hsl.hue) < 0.000001)
        #expect(abs(selected.hsl.lightness - target.hsl.lightness) < 0.000001)
        pad.mouseUp(with: try themeMouse(.leftMouseUp, in: pad, at: translated))
    }

    @Test @MainActor func aDialClickUsesItsClockwiseAngleInOneEdit() throws {
        let view = editor()
        let dial = try editorControl("Theme texture and noise", in: view)
        let right = CGPoint(x: dial.bounds.maxX - 2, y: dial.bounds.midY)
        var commits = 0
        view.onCommit = { _ in commits += 1 }
        dial.mouseDown(with: try themeMouse(.leftMouseDown, in: dial, at: right))
        dial.mouseUp(with: try themeMouse(.leftMouseUp, in: dial, at: right))
        #expect(view.theme.noise == 0.25)
        #expect(commits == 1)
    }

    @Test(arguments: [(0, 1, 1), (4, -1, 3)])
    @MainActor func changingPresetPagesPublishesTheWindowOwnedPage(example: (Int, Int, Int)) throws {
        _ = NSApplication.shared
        let view = SpaceThemeEditorView(theme: SpaceTheme(), presetPage: example.0, performHapticFeedback: {})
        var changes = [Int]()
        view.onPresetPageChange = { changes.append($0) }
        let button = try themeButton(example.1 > 0 ? "Next color presets" : "Previous color presets", in: view)
        _ = NSApp.sendAction(try #require(button.action), to: button.target, from: button)
        #expect(changes == [example.2])
    }

    @Test @MainActor func aReplacementThemeRejectsAnUnrecognizedRotation() throws {
        let view = editor()
        let noise = try editorControl("Theme texture and noise", in: view)
        noise.rotate(with: EditorGesture(in: noise, phase: .began, degrees: 0.5))
        var replacement = SpaceTheme()
        replacement.noise = 0.4
        view.synchronizeTheme(replacement)
        noise.rotate(with: EditorGesture(in: noise, phase: .changed, degrees: 90))
        noise.rotate(with: EditorGesture(in: noise, phase: .ended))
        #expect(view.theme == replacement)
    }

    @Test @MainActor func theEditorsLocalUndoRedoesACompletedColorChange() throws {
        let theme = SpaceTheme.singleColor(try #require(ThemeColor(hex: "4C6688")))
        let view = editor(theme: theme)
        let add = try themeButton("Add color", in: view)
        _ = NSApp.sendAction(try #require(add.action), to: add.target, from: add)
        let edited = view.theme
        view.undo(nil)
        #expect(view.theme == theme)
        view.redo(nil)
        #expect(view.theme == edited)
    }
}

extension SpaceThemeAppearanceTests {
    @Test @MainActor func explicitAppearanceUpdatesEveryOpenEditor() throws {
        try withAppearance { defaults in
            AppAppearance.apply(.light, defaults: defaults)
            let first = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
            let second = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
            AppAppearance.apply(.dark, defaults: defaults)
            let firstDark = try themeButton("Dark appearance", in: first)
            let secondDark = try themeButton("Dark appearance", in: second)
            #expect(firstDark.accessibilityValue() as? Int == 1)
            #expect(secondDark.accessibilityValue() as? Int == 1)
        }
    }

    @Test @MainActor func aRetiredEditorIsNotKeptAliveByItsAppearanceObservation() throws {
        try withAppearance { _ in
            weak var retired: SpaceThemeEditorView?
            autoreleasepool {
                let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: {})
                retired = editor
            }
            #expect(retired == nil)
        }
    }

    @Test @MainActor func undoInTheThemeEditorKeepsTheParentAppearance() throws {
        try withAppearance { defaults in
            let theme = SpaceTheme.singleColor(try #require(ThemeColor(hex: "4C6688")))
            let editor = SpaceThemeEditorView(theme: theme, performHapticFeedback: {})
            let add = try themeButton("Add color", in: editor)
            _ = NSApp.sendAction(try #require(add.action), to: add.target, from: add)
            AppAppearance.apply(.dark, defaults: defaults)
            editor.undo(nil)
            #expect(editor.theme == theme)
            #expect(AppAppearance.current == .dark)
        }
    }
}

extension SpaceThemeHapticTests {
    @Test @MainActor func cancelledPhysicalInputCannotPulseAfterAParentEdit() throws {
        _ = NSApplication.shared
        var replacement = SpaceTheme()
        replacement.noise = 0.35
        var pulses = 0
        let editor = SpaceThemeEditorView(theme: SpaceTheme(), performHapticFeedback: { pulses += 1 })
        editor.layoutSubtreeIfNeeded()
        let noise = try editorControl("Theme texture and noise", in: editor)
        noise.rotate(with: EditorGesture(in: noise, phase: .began, degrees: 45))
        let before = pulses
        editor.synchronizeTheme(replacement)
        noise.rotate(with: EditorGesture(in: noise, phase: .changed, degrees: 180))
        noise.rotate(with: EditorGesture(in: noise, phase: .ended))
        #expect(editor.theme == replacement)
        #expect(pulses == before)
    }

    @Test @MainActor func draggingTheNoiseDialAcrossSeveralDetentsPulsesOnce() throws {
        _ = NSApplication.shared
        var initial = SpaceTheme()
        initial.noise = 0.05
        var pulses = 0
        let editor = SpaceThemeEditorView(theme: initial, performHapticFeedback: { pulses += 1 })
        editor.layoutSubtreeIfNeeded()
        let noise = try editorControl("Theme texture and noise", in: editor)
        let top = NSPoint(x: noise.bounds.midX, y: 4)
        let bottom = NSPoint(x: noise.bounds.midX, y: noise.bounds.height - 4)
        noise.mouseDown(with: try themeMouse(.leftMouseDown, in: noise, at: top))
        noise.mouseDragged(with: try themeMouse(.leftMouseDragged, in: noise, at: bottom))
        noise.mouseUp(with: try themeMouse(.leftMouseUp, in: noise, at: bottom))
        #expect(pulses == 1)
    }
}
