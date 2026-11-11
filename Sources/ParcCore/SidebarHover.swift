import CoreGraphics
import Foundation

enum SidebarHoverState: Int, Comparable {
    case none, inside, hasLingered, hasStopped
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum SidebarHoverRegion: CaseIterable {
    case window, sidebar, innerLeftEdge, outerLeftEdge, innerTopLeftEdge, trafficLight
    var fidelity: SidebarHoverState {
        switch self {
        case .window: .inside
        case .sidebar: .hasLingered
        case .innerLeftEdge, .outerLeftEdge, .innerTopLeftEdge, .trafficLight: .hasStopped
        }
    }
    var lingerRequirement: TimeInterval { self == .outerLeftEdge ? 0.16 : 0.15 }
}

struct SidebarHoverInfo: Equatable {
    private var states: [SidebarHoverRegion: SidebarHoverState] = [:]
    subscript(region: SidebarHoverRegion) -> SidebarHoverState {
        get { states[region] ?? .none }
        set { states[region] = newValue == .none ? nil : newValue }
    }
}

struct SidebarHoverTracking {
    static let stopDelay: TimeInterval = 0.08
    private(set) var info = SidebarHoverInfo()

    mutating func update(contains: (SidebarHoverRegion) -> Bool) -> [SidebarHoverRegion] {
        var entered: [SidebarHoverRegion] = []
        for region in SidebarHoverRegion.allCases {
            let inside = contains(region)
            if inside, info[region] == .none {
                info[region] = .inside
                if region.fidelity >= .hasLingered { entered.append(region) }
            } else if !inside, info[region] != .none {
                info[region] = .none
            }
        }
        return entered
    }
    mutating func linger(_ region: SidebarHoverRegion) -> Bool {
        guard info[region] == .inside, region.fidelity >= .hasLingered else { return false }
        info[region] = .hasLingered
        return true
    }
    mutating func stop() -> Bool {
        var changed = false
        for region in SidebarHoverRegion.allCases where region.fidelity == .hasStopped
            && (info[region] == .inside || info[region] == .hasLingered) {
            info[region] = .hasStopped; changed = true
        }
        return changed
    }
    var needsStopPromotion: Bool {
        SidebarHoverRegion.allCases.contains { region in
            region.fidelity == .hasStopped
                && (info[region] == .inside || info[region] == .hasLingered)
        }
    }
    mutating func reset() { info = SidebarHoverInfo() }
}

enum SidebarHoverZones {
    enum Presentation { case locked, floating, hidden }
    static let contentInset = 10.0
    static let toolbarAllowance = 16.0
    static let outerEdgeWidth = 50.0
    static let expandedOuterEdgeWidth = 250.0
    static let topLeftWidth = 40.0
    static let trafficLightReach = 90.0
    static let floatingSidebarReach = 80.0
    static let trafficLightClearance = 50.0
    static let minimumTrafficLightHeight = 10.0

    static func rects(size: CGSize, presentation: Presentation, sidebarWidth: Double, showingToolbar: Bool,
                      trafficLightHeight: Double, info: SidebarHoverInfo) -> [SidebarHoverRegion: CGRect] {
        let height = Double(size.height), inset = contentInset
        let edgeHeight = max(0, height - (showingToolbar ? toolbarAllowance : 0))
        let inWindow = info[.window] != .none
        let innerLeft = !inWindow || info[.innerLeftEdge] != .none
            ? CGRect(x: -2 * inset, y: 0, width: 3.5 * inset, height: edgeHeight)
            : CGRect(x: 0, y: 0, width: 0.6 * inset, height: edgeHeight)
        let outer = inWindow || info[.outerLeftEdge] != .none ? expandedOuterEdgeWidth : outerEdgeWidth
        let topLeft = inWindow
            ? CGRect(x: 0, y: height - 2 * inset, width: topLeftWidth, height: 3.5 * inset)
            : CGRect(x: 0, y: height - 1.6 * inset, width: topLeftWidth, height: 0.6 * inset)
        let sidebar: Double = switch presentation {
        case .locked: sidebarWidth
        case .floating: sidebarWidth + floatingSidebarReach
        case .hidden: 0
        }
        return [.window: CGRect(x: 0, y: 0, width: Double(size.width), height: height),
                .sidebar: CGRect(x: 0, y: 0, width: sidebar, height: height),
                .innerLeftEdge: innerLeft,
                .outerLeftEdge: CGRect(x: -outer, y: 0, width: outer, height: edgeHeight),
                .innerTopLeftEdge: topLeft,
                .trafficLight: CGRect(x: -outerEdgeWidth, y: height, width: outerEdgeWidth + trafficLightReach,
                                      height: trafficLightHeight)]
    }
    static func trafficLightHeight(windowMaxY: Double, screenHeight: Double, menuBarHeight: Double) -> Double {
        let height = min(windowMaxY + trafficLightClearance, screenHeight - menuBarHeight) - windowMaxY
        return height <= minimumTrafficLightHeight ? 0 : height
    }
}

enum SidebarHoverActivation {
    static func isActive(wasActive: Bool, info: SidebarHoverInfo, fullscreen: Bool, includesTopLeft: Bool) -> Bool {
        let threshold: SidebarHoverState = wasActive ? .inside : fullscreen ? .hasStopped : .hasLingered
        var zones: [SidebarHoverRegion] = [.sidebar, .outerLeftEdge, .innerLeftEdge]
        if includesTopLeft { zones += [.trafficLight, .innerTopLeftEdge] }
        return zones.contains { info[$0] >= threshold }
    }
}

enum SidebarHoverPresentationRule {
    enum Action: Equatable { case keep, reveal, dismiss }
    struct Decision: Equatable {
        var isActive: Bool
        var action: Action
    }
    static func decide(stored: Bool, presentation: SidebarHoverZones.Presentation, info: SidebarHoverInfo,
                       fullscreen: Bool, includesTopLeft: Bool, isKeyWindow: Bool,
                       ownerDefers: Bool, interactionDefers: Bool) -> Decision {
        let active = SidebarHoverActivation.isActive(wasActive: stored && presentation == .floating, info: info,
                                                     fullscreen: fullscreen, includesTopLeft: includesTopLeft)
        switch presentation {
        case .locked:
            return Decision(isActive: false, action: .keep)
        case .hidden:
            return active && isKeyWindow ? Decision(isActive: true, action: .reveal) : Decision(isActive: false, action: .keep)
        case .floating:
            if active || ownerDefers || isKeyWindow && interactionDefers { return Decision(isActive: true, action: .keep) }
            return Decision(isActive: false, action: .dismiss)
        }
    }
}
