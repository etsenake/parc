import Foundation

package enum SpaceThemeNoiseGesture {
    case slider, rotation, dialClick, scrollWheel, drag
}

package final class SpaceThemeEditorState {
    private struct Snapshot: Equatable {
        var theme: SpaceTheme
        var saturation: Double
        var lowerLightness: Double
        var upperLightness: Double

        package init(theme: SpaceTheme, saturation: Double, lowerLightness: Double, upperLightness: Double) {
            self.theme = theme
            self.saturation = saturation
            self.lowerLightness = lowerLightness
            self.upperLightness = upperLightness
        }
    }
    private var value: Snapshot
    private var gestureStart: Snapshot?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    package var theme: SpaceTheme { value.theme }
    package var isGestureInProgress: Bool { gestureStart != nil }
    package var canUndo: Bool { !undoStack.isEmpty }
    package var canRedo: Bool { !redoStack.isEmpty }
    package var canAddColor: Bool { theme.primaryColor != nil && theme.colorCount < 3 }
    package var canRemoveColor: Bool { theme.colorCount > 0 }
    package var lightnessRange: ClosedRange<Double> { value.lowerLightness...value.upperLightness }

    package init(theme: SpaceTheme) {
        precondition(theme.isValid)
        let hsl = theme.primaryColor?.hsl
        var lower = hsl.map { max($0.lightness - 0.25, 0.01) } ?? 0.01
        var upper = hsl.map { min($0.lightness + 0.25, 0.97) } ?? 0.97
        if let hsl, theme.appearance != .automatic {
            lower = min(theme.appearance == .light ? 0.575 : 0.01, hsl.lightness)
            upper = max(theme.appearance == .light ? 0.97 : 0.425, hsl.lightness)
        }
        value = Snapshot(theme: theme, saturation: hsl.map { max($0.saturation, 0.01) } ?? 1,
                         lowerLightness: lower, upperLightness: upper)
    }

    package func beginGesture() { if gestureStart == nil { gestureStart = value } }
    @discardableResult package func finishGesture() -> Bool {
        guard let initial = gestureStart else { return false }
        gestureStart = nil
        guard initial != value else { return false }
        undoStack.append(initial); redoStack.removeAll()
        return true
    }
    @discardableResult private func change(_ mutation: (inout Snapshot) -> Void) -> Bool {
        let old = value
        mutation(&value)
        guard value != old else { return false }
        if gestureStart == nil { undoStack.append(old); redoStack.removeAll() }
        return true
    }
    @discardableResult package func undo() -> Bool {
        finishGesture()
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(value); value = previous
        return true
    }
    @discardableResult package func redo() -> Bool {
        finishGesture()
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(value); value = next
        return true
    }

    @discardableResult package func moveColor(x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite else { return false }
        return change {
            let hue = (atan2(y, x) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
            let radius = min(1, max(0, hypot(x, y) / 0.99))
            let lightness = $0.lowerLightness + ($0.upperLightness - $0.lowerLightness) * radius
            $0.theme.primaryColor = ThemeColor.hsl(hue: hue, saturation: $0.saturation,
                                                   lightness: lightness, colorSpace: .displayP3)
            $0.theme.colorCount = max(1, $0.theme.colorCount)
        }
    }
    package func normalizedPosition(for color: ThemeColor) -> (x: Double, y: Double) {
        let hsl = color.hsl
        let radius = 0.99 * min(1, max(0, (hsl.lightness - value.lowerLightness) / (value.upperLightness - value.lowerLightness)))
        return (radius * cos(hsl.hue * 2 * .pi), radius * sin(hsl.hue * 2 * .pi))
    }
    @discardableResult package func addColor() -> Bool {
        guard canAddColor else { return false }
        return change { $0.theme.colorCount += 1 }
    }
    @discardableResult package func removeColor() -> Bool {
        guard canRemoveColor else { return false }
        return change {
            $0.theme.removeColor()
            if $0.theme.colorCount == 0 { Self.resetPad(&$0) }
        }
    }
    @discardableResult package func removeAllColors() -> Bool {
        change {
            $0.theme.primaryColor = nil; $0.theme.colorCount = 0
            $0.theme.noise = 0; $0.theme.texture = .grain; $0.theme.intensity = 0.8
            $0.theme.wheel = .complimentary
            Self.resetPad(&$0)
        }
    }
    private static func resetPad(_ state: inout Snapshot) {
        state.saturation = 1; state.lowerLightness = 0.01; state.upperLightness = 0.97
    }
    @discardableResult package func selectPreset(_ color: ThemeColor, colorCount: Int, wheel: SpaceTheme.Wheel) -> Bool {
        guard (1...3).contains(colorCount) else { return false }
        return change {
            $0.theme.primaryColor = color; $0.theme.colorCount = colorCount; $0.theme.wheel = wheel
            let hsl = color.hsl
            $0.saturation = max(hsl.saturation, 0.01)
            $0.lowerLightness = max(hsl.lightness - 0.25, 0.01)
            $0.upperLightness = min(hsl.lightness + 0.25, 0.97)
        }
    }
    @discardableResult package func setNoise(_ value: Double, gesture: SpaceThemeNoiseGesture) -> Bool {
        change { $0.theme.setNoise(value, rotating: gesture == .rotation) }
    }
    @discardableResult package func setIntensity(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        return change { $0.theme.intensity = min(1, max(0, value)) }
    }
    @discardableResult package func cycleTexture() -> Bool {
        change {
            if $0.theme.noise == 0 { $0.theme.noise = 0.8; return }
            let all = SpaceTheme.Texture.allCases
            let next = (all.firstIndex(of: $0.theme.texture)! + 1) % all.count
            $0.theme.texture = all[next]
            if next == 0 { $0.theme.noise = 0 }
        }
    }
}
