import Foundation

package enum EaselFloatingBar {
    package static let bottomMargin = 16.0
    package static let sideMargin = 12.0
    package static let clearance = 8.0
    package static let chipGap = 10.0
    package static let entranceRise = 12.0
    package static let dimmedOpacity = 0.35
    package static let hoverLift = 1.5
    package static let maximumCoverFraction = 0.5

    package static func frame(containerWidth: Double, containerHeight: Double, preferredWidth: Double, height: Double,
                      top: Double) -> EaselRect {
        guard [containerWidth, containerHeight, preferredWidth, height, top].allSatisfy(\.isFinite) else {
            return EaselRect(x: 0, y: 0, width: 0, height: 0)
        }
        let width = max(0, min(containerWidth - 2 * sideMargin, preferredWidth))
        let y = max(top, containerHeight - bottomMargin - height)
        return EaselRect(x: ((containerWidth - width) / 2).rounded(), y: y.rounded(), width: width, height: height)
    }

    package static func coveredBottom(containerHeight: Double, bar: EaselRect) -> Double {
        guard containerHeight.isFinite, bar.y.isFinite, bar.width > 0, bar.height > 0 else { return 0 }
        return max(0, (containerHeight - bar.y + clearance).rounded())
    }

    package static func cover(_ coveredBottom: Double, viewportHeight: Double) -> Double {
        guard coveredBottom.isFinite, viewportHeight.isFinite, coveredBottom > 0, viewportHeight > 0 else { return 0 }
        return min(coveredBottom, viewportHeight * maximumCoverFraction)
    }

    package static func viewport(width: Double, height: Double, coveredBottom: Double) -> (width: Double, height: Double) {
        (width, height - cover(coveredBottom, viewportHeight: height))
    }

    package static func uncovered(_ visible: EaselRect, coveredBottom: Double, magnification: Double) -> EaselRect {
        guard magnification.isFinite, magnification > 0 else { return visible }
        let cut = cover(coveredBottom, viewportHeight: visible.height * magnification) / magnification
        return EaselRect(x: visible.x, y: visible.y, width: visible.width, height: visible.height - cut)
    }

    package static func clipCentre(showing centre: EaselPoint, coveredBottom: Double, viewportHeight: Double,
                           magnification: Double) -> EaselPoint {
        guard magnification.isFinite, magnification > 0 else { return centre }
        let cut = cover(coveredBottom, viewportHeight: viewportHeight)
        return EaselPoint(x: centre.x, y: centre.y + cut / (2 * magnification))
    }

    package static func chipFrame(width: Double, height: Double, containerWidth: Double, bar: EaselRect, top: Double) -> EaselRect {
        EaselRect(x: ((containerWidth - width) / 2).rounded(), y: max(top, bar.y - chipGap - height).rounded(),
                  width: width, height: height)
    }

    package static func pillFrame(button: EaselRect, inset: Double = 0) -> EaselRect {
        EaselRect(x: button.x + inset, y: button.y + inset, width: max(0, button.width - 2 * inset),
                  height: max(0, button.height - 2 * inset))
    }
}

package enum EaselToolFlourish: Equatable {
    case hop, tilt, wiggle, thump, pop, open

    package struct Frame: Equatable {
        package var dx = 0.0
        package var dy = 0.0
        package var rotation = 0.0
        package var scaleX = 1.0
        package var scaleY = 1.0
        package init(dx: Double = 0.0, dy: Double = 0.0, rotation: Double = 0.0, scaleX: Double = 1.0, scaleY: Double = 1.0) {
            self.dx = dx
            self.dy = dy
            self.rotation = rotation
            self.scaleX = scaleX
            self.scaleY = scaleY
        }

        package static let rest = Frame()

        package var isRest: Bool {
            abs(dx) < 1e-9 && abs(dy) < 1e-9 && abs(rotation) < 1e-9 && abs(scaleX - 1) < 1e-9 && abs(scaleY - 1) < 1e-9
        }
    }

    package static func flourish(for tool: EaselTool) -> EaselToolFlourish? {
        switch tool {
        case .select: return nil
        case .hand: return .open
        case .sticky: return .hop
        case .marker, .highlighter, .washi: return .tilt
        case .eraser: return .wiggle
        case .stamp: return .thump
        case .rectangle, .ellipse, .elbowConnector, .curvedConnector, .straightConnector, .text, .section, .table, .codeBlock:
            return .pop
        }
    }

    private var spring: (response: Double, damping: Double) {
        switch self {
        case .hop: return (0.36, 0.5)
        case .tilt: return (0.4, 0.42)
        case .wiggle: return (0.12, 0.16)
        case .thump: return (0.3, 0.45)
        case .pop: return (0.4, 0.7)
        case .open: return (0.34, 0.5)
        }
    }

    package var duration: Double {
        switch self {
        case .hop, .tilt, .wiggle, .open: return 0.42
        case .thump: return 0.4
        case .pop: return 0.36
        }
    }

    package static func kick(at time: Double, response: Double, damping: Double) -> Double {
        guard time > 0, response > 0, damping > 0, damping < 1 else { return 0 }
        let omega = 2 * Double.pi / response
        let damped = omega * (1 - damping * damping).squareRoot()
        let decay = damping * omega
        let peakTime = atan(damped / decay) / damped
        let peak = exp(-decay * peakTime) * sin(damped * peakTime)
        guard peak > 0 else { return 0 }
        return exp(-decay * time) * sin(damped * time) / peak
    }

    package func frame(at time: Double) -> Frame {
        guard time > 0, time < duration else { return .rest }
        let taper = 1 - pow(time / duration, 3)
        let k = Self.kick(at: time, response: spring.response, damping: spring.damping) * taper
        var frame = Frame()
        switch self {
        case .hop:
            frame.dy = -4 * k
            frame.scaleY = 1 + 0.06 * k
            frame.scaleX = 1 - 0.03 * k
        case .tilt:
            frame.rotation = -14 * k
        case .wiggle:
            frame.rotation = 11 * k
        case .thump:
            frame.scaleX = 1 + 0.18 * k
            frame.scaleY = 1 - 0.22 * k
            frame.dy = 1.5 * k
        case .pop:
            frame.scaleX = 1 + 0.2 * k
            frame.scaleY = frame.scaleX
        case .open:
            frame.scaleX = 1 + 0.14 * k
            frame.scaleY = frame.scaleX
            frame.rotation = -10 * k
        }
        return frame
    }

    package func frames(rate: Double = 60) -> [Frame] {
        guard rate > 0 else { return [.rest, .rest] }
        let count = max(2, Int((duration * rate).rounded(.up)) + 1)
        return (0..<count).map { index in
            index == count - 1 ? .rest : frame(at: duration * Double(index) / Double(count - 1))
        }
    }
}
