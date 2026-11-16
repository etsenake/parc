import AppKit

@main
struct OnboardingWindowFrameTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        typealias Layout = OnboardingWindowFrameLayout
        let content = NSRect(x: 0, y: 0, width: OnboardingSetupLayout.size.width - OnboardingSetupLayout.instructionWidth,
                             height: OnboardingSetupLayout.size.height)
        let copy = Layout.copyFrame(in: content)
        precondition(content.contains(copy) && copy.size == Layout.copySize
            && copy.minX == copy.minX.rounded() && copy.minY == copy.minY.rounded(),
            "The window copy sits on whole points inside the setup content column")
        let bounds = NSRect(origin: .zero, size: copy.size)
        let hub = WindowFrameCrankPlacement.hub(in: bounds, dockedSidebarEdge: nil)
        precondition(hub == CGPoint(x: WindowFrameCrankPlacement.hubInset, y: WindowFrameCrankPlacement.hubInset)
            && WindowFrameCrankPlacement.fits(hub: hub, in: bounds)
            && copy.width >= 2 * WindowFrameCrankPlacement.hubInset && copy.height >= 2 * WindowFrameCrankPlacement.hubInset,
            "The crank sits at its real place with its whole swing and lights inside the copy")
        let side: CGFloat = 288
        let plain = Layout.crankFrame(in: bounds, side: side, flipped: false)
        let flipped = Layout.crankFrame(in: bounds, side: side, flipped: true)
        precondition(plain.midX == hub.x && plain.midY == hub.y
            && flipped.midX == hub.x && flipped.midY == bounds.maxY - hub.y,
            "The crank view centres on the hub in either coordinate direction")
        for (value, inset) in [(3, 3.0), (10, 10.0), (13, 13.0)] as [(Int, CGFloat)] {
            let card = Layout.pageCard(in: bounds, thickness: CGFloat(value))
            precondition(card == bounds.insetBy(dx: inset, dy: inset),
                         "The page card is inset by exactly \(value) points on every side")
            let bars = Layout.placeholderBars(in: card.size)
            precondition(!bars.isEmpty && bars.allSatisfy { NSRect(origin: .zero, size: card.size).contains($0) && $0.width > 0 },
                         "Placeholder content stays inside the page card at \(value) points")
        }
        precondition(Layout.pageCard(in: bounds, thickness: 1) == bounds.insetBy(dx: 2.6, dy: 2.6)
            && Layout.pageCard(in: bounds, thickness: 20) == bounds.insetBy(dx: 13.4, dy: 13.4),
            "The crank's give past 3 and 13 follows the same bounds as live windows")
        precondition(Layout.shudderValues == [0, 3.2, -2.8, 2, -1.4, 0.7, 0] && Layout.shudderDuration == 0.38
            && Layout.shudderValues.count == Layout.shudderKeyTimes.count,
            "The copy's page card shudders like the real window at the ends")
        print("Onboarding window frame step geometry checks passed")
    }
}
