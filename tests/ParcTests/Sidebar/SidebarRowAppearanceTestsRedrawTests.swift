import AppKit
import Testing
@testable import Parc
@testable import ParcKit

struct SidebarRowAppearanceTestsRedrawTests {
    private typealias Support = SidebarRowAppearanceTestsSupport

    @MainActor @Test func updateLayerRecordsTheBoundsItPainted() {
        let background = Support.highlighted()
        #expect(background.view.paintedBounds == background.view.bounds)
    }

    @MainActor @Test func aNoOpLayoutDoesNotRebuildUnchangedLayers() {
        let background = Support.highlighted()
        let painted = background.view.paintedBounds
        let shadow = background.layer.shadowPath
        background.view.layout()
        #expect(background.view.paintedBounds == painted)
        #expect(background.layer.shadowPath === shadow)
        #expect(background.layer.frame == background.view.layer!.bounds)
    }

    @MainActor @Test func unchangedAppearanceInputsDoNotRebuildLayers() {
        let background = Support.highlighted()
        let shadow = background.layer.shadowPath
        let painted = background.view.paintedBounds
        background.view.appearanceState = background.view.appearanceState
        background.view.dark = false
        background.view.ringColor = background.view.ringColor
        #expect(background.layer.shadowPath === shadow)
        #expect(background.view.paintedBounds == painted)
    }

    @MainActor @Test func movingTheUnflippedFillViewDoesNotRedraw() {
        let background = Support.highlighted()
        let painted = background.view.paintedBounds
        let shadow = background.layer.shadowPath
        background.view.frame.origin = NSPoint(x: 40, y: 18)
        background.view.layout()
        #expect(background.view.bounds.size == NSSize(width: 212, height: 35))
        #expect(background.view.paintedBounds == painted)
        #expect(background.layer.shadowPath === shadow)
    }

    @MainActor @Test func hoverFillStillPaintsFromAppearanceWithoutALayout() {
        let background = Support.highlighted()
        background.view.appearanceState = SidebarRowAppearance(hovered: true)
        #expect(Support.rgba(NSColor(cgColor: background.layer.backgroundColor!)!, .displayP3) == [0.055, 0.059, 0.063, 0.05])
        #expect(background.ring.isHidden)
        #expect(background.layer.opacity == 1)
    }

    @MainActor @Test func aFollowUpLayoutKeepsTheAppearanceThatAlreadyPainted() {
        let background = Support.highlighted()
        background.view.appearanceState = SidebarRowAppearance(hovered: true)
        background.view.layout()
        #expect(Support.rgba(NSColor(cgColor: background.layer.backgroundColor!)!, .displayP3) == [0.055, 0.059, 0.063, 0.05])
    }

    @MainActor @Test func aWidthChangeLeavesPaintedBoundsStaleUntilLayout() {
        let background = Support.highlighted()
        background.view.setFrameSize(NSSize(width: 180, height: 35))
        #expect(background.view.paintedBounds != background.view.bounds)
    }

    @MainActor @Test func aWidthChangeStillRefreshesFillAndRingFrames() {
        let background = Support.highlighted()
        background.view.setFrameSize(NSSize(width: 180, height: 35))
        background.view.layout()
        #expect(background.view.paintedBounds == background.view.bounds)
        #expect(background.layer.frame.size == NSSize(width: 180, height: 35))
        #expect(background.ring.frame.size == NSSize(width: 180, height: 35))
    }

    @MainActor @Test func aFollowUpLayoutAtTheNewSizeIsANoOp() {
        let background = Support.highlighted()
        background.view.setFrameSize(NSSize(width: 180, height: 35))
        background.view.layout()
        let sized = background.view.paintedBounds
        let shadow = background.layer.shadowPath
        background.view.layout()
        #expect(background.view.paintedBounds == sized)
        #expect(background.layer.shadowPath === shadow)
    }

    @MainActor @Test func aHeightChangeStillRefreshesTheShadowPathBounds() {
        let background = Support.highlighted()
        let before = background.layer.shadowPath
        background.view.setFrameSize(NSSize(width: 212, height: 36))
        background.view.layout()
        #expect(background.view.paintedBounds == background.view.bounds)
        #expect(background.layer.frame.size.height == 36)
        #expect(background.layer.shadowPath != nil)
        #expect(background.layer.shadowPath !== before)
    }

    @MainActor @Test func darkAppearanceStillPaintsTheHoverFill() {
        let background = Support.highlighted()
        background.view.appearanceState = SidebarRowAppearance(hovered: true)
        background.view.dark = true
        #expect(Support.rgba(NSColor(cgColor: background.layer.backgroundColor!)!, .displayP3) == [0.98, 0.984, 1, 0.1])
    }

    @MainActor @Test func ringColourDimmingAndHighlightStillUpdateTogether() {
        let background = Support.highlighted()
        background.view.ringColor = .white
        #expect(!background.ring.isHidden)
        #expect(background.ring.borderWidth == 2)
        #expect(background.layer.opacity == 0.5)
        #expect(Support.rgba(NSColor(cgColor: background.ring.borderColor!)!) == [1, 1, 1, 1])
        #expect(background.ring.opacity == 1)
    }

    @MainActor @Test func theSkipDoesNotClipTheSelectedShadowOrFlattenTranslucentFills() {
        let background = Support.highlighted()
        background.view.layout()
        #expect(!background.view.clipsToBounds)
        #expect(background.view.layer?.masksToBounds == false)
        #expect(background.view.layer?.allowsGroupOpacity == false)
        #expect(background.layer.masksToBounds == false)
    }
}
