import Foundation

enum EaselControlMotion {
    static let hoverScale = 1.08
    static let cardHoverScale = 1.03
    static let pressedScale = 0.95
    static let cardPressedScale = 0.98
    static let ringHiddenScale = 1.3
    static let markerHiddenScale = 0.4
    static let hoverShadowOpacity = 0.2
    static let darkHoverShadowOpacity = 0.4

    static func scale(hovered: Bool, pressed: Bool, hover: Double = hoverScale, press: Double = pressedScale) -> Double {
        pressed ? press : hovered ? hover : 1
    }

    static func shadowOpacity(hovered: Bool, pressed: Bool, dark: Bool) -> Double {
        guard hovered, !pressed else { return 0 }
        return dark ? darkHoverShadowOpacity : hoverShadowOpacity
    }
}

enum EaselDigitRoll {
    enum Direction: Equatable {
        case up
        case down
    }

    struct Column: Equatable {
        var old: Character?
        var new: Character?
        var direction: Direction

        var isChanged: Bool { old != new }
    }

    static let rollDistance = 0.62
    static let reducedFade: TimeInterval = 0.15

    static func direction(from old: String, to new: String) -> Direction {
        value(of: new) < value(of: old) ? .down : .up
    }

    static func columns(from old: String, to new: String) -> [Column] {
        let direction = direction(from: old, to: new)
        let before = Array(old), after = Array(new)
        let count = max(before.count, after.count)
        return (0..<count).map { offset in
            let fromEnd = count - 1 - offset
            let oldIndex = before.count - 1 - fromEnd
            let newIndex = after.count - 1 - fromEnd
            return Column(old: before.indices.contains(oldIndex) ? before[oldIndex] : nil,
                          new: after.indices.contains(newIndex) ? after[newIndex] : nil,
                          direction: direction)
        }
    }

    static func changedColumns(from old: String, to new: String) -> [Int] {
        columns(from: old, to: new).enumerated().filter { $0.element.isChanged }.map(\.offset)
    }

    static func offsetBelowIsPositive(of direction: Direction, height: Double, entering: Bool) -> Double {
        let travel = height * rollDistance
        switch (direction, entering) {
        case (.up, true), (.down, false): return travel
        case (.up, false), (.down, true): return -travel
        }
    }

    private static func value(of text: String) -> Int {
        text.reduce(0) { total, character in
            guard let digit = character.wholeNumberValue else { return total }
            return total * 10 + digit
        }
    }
}

struct EaselPulseTrain: Equatable {
    static let count = 3
    static let duration: TimeInterval = 1.8
    static let peak = 0.55
    static let falloff = 0.72

    static var keyTimes: [Double] {
        var times: [Double] = [0]
        for index in 0..<count {
            let start = Double(index) / Double(count)
            times.append(start + 0.5 / Double(count) * 0.55)
            times.append(start + 1 / Double(count))
        }
        return times
    }

    static var values: [Double] {
        var values: [Double] = [0]
        for index in 0..<count {
            values.append(peak * pow(falloff, Double(index)))
            values.append(0)
        }
        return values
    }
}
