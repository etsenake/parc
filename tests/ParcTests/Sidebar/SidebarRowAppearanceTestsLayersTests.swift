import AppKit
import Testing
@testable import Parc

struct SidebarRowAppearanceTestsLayersTests {
    private typealias Support = SidebarRowAppearanceTestsSupport
    private typealias Background = Support.Background

    @MainActor @Test func theFillViewKeepsAppKitsUnflippedShadowDirection() {
        #expect(!Background().view.isFlipped)
    }

    @MainActor @Test func theFillNeverTakesRowInput() {
        #expect(Background().view.hitTest(NSPoint(x: 20, y: 20)) == nil)
    }

    @MainActor @Test func theFillAddsNoAccessibilityElement() {
        #expect(!Background().view.isAccessibilityElement())
    }

    @MainActor @Test func theSelectedShadowIsNotClippedToTheFill() {
        let view = Background().view
        #expect(!view.clipsToBounds)
        #expect(view.layer?.masksToBounds == false)
    }

    @MainActor @Test func translucentFillsCompositeOntoTheThemeNotAnOffscreenBacking() {
        #expect(Background().view.layer?.allowsGroupOpacity == false)
    }

    @MainActor @Test func theFillAndRingAreSiblingLayers() {
        let background = Background().painted()
        #expect(background.layer.superlayer === background.view.layer)
        #expect(background.ring.superlayer === background.view.layer)
    }

    @MainActor @Test func anIdleRowIsClear() {
        let background = Background().painted()
        #expect(background.layer.backgroundColor == nil)
        #expect(background.view.layer!.backgroundColor == nil)
    }

    @MainActor @Test func theFillHasContinuousTwelvePointCorners() {
        let layer = Background().painted().layer
        #expect(layer.cornerRadius == 12)
        #expect(layer.cornerCurve == .continuous)
    }

    @MainActor @Test func theFillCoversTheVisibleRow() {
        let background = Background().painted()
        #expect(background.layer.frame == background.view.layer!.bounds)
    }

    @MainActor @Test func atRestThereIsNoRingOrDimming() {
        let background = Background().painted()
        #expect(background.ring.isHidden)
        #expect(background.layer.opacity == 1)
    }

    @MainActor @Test func theShadowHasItsRecoveredGeometry() {
        let layer = Background().painted().layer
        #expect(layer.shadowRadius == 1)
        #expect(layer.shadowOffset == CGSize(width: 0, height: -1))
        #expect(layer.shadowOpacity == 1)
    }

    @MainActor @Test func updateLayerKeepsTheHostAndFillUnclipped() {
        let background = Background().painted()
        #expect(background.layer.masksToBounds == false)
        #expect(background.view.layer?.masksToBounds == false)
    }

    @MainActor @Test func thereIsNoShadowWithoutTheCurrentItem() {
        #expect(NSColor(cgColor: Background().painted().layer.shadowColor!)!.alphaComponent == 0)
    }

    @MainActor @Test func theCurrentFillWinsOverHover() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(current: true, hovered: true)
        background.view.updateLayer()
        #expect(Support.rgba(NSColor(cgColor: background.layer.backgroundColor!)!) == [1, 1, 1, 0.85])
    }

    @MainActor @Test func theCurrentRowCastsItsShadow() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(current: true, hovered: true)
        background.view.updateLayer()
        #expect(Support.rgba(NSColor(cgColor: background.layer.shadowColor!)!) == [0, 0, 0, 0.2])
    }

    @MainActor @Test func aDarkCurrentRowHasNoShadow() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(current: true, hovered: true)
        background.view.dark = true
        background.view.updateLayer()
        #expect(NSColor(cgColor: background.layer.shadowColor!)!.alphaComponent == 0)
    }

    @MainActor @Test func multiSelectionWinsOverHover() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(multiSelected: true, hovered: true)
        background.view.updateLayer()
        #expect(Support.rgba(NSColor(cgColor: background.layer.backgroundColor!)!) == [0, 0, 0, 0.1])
    }

    @MainActor @Test func aNarrowCompactRowKeepsAValidShadowPath() {
        let background = Background()
        background.view.frame = NSRect(x: 0, y: 0, width: 10, height: 35)
        background.view.updateLayer()
        #expect(background.layer.shadowPath != nil)
    }

    @MainActor @Test func aSelectedSplitChildIsAPill() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(splitChild: true, splitGroupSelected: true)
        background.view.frame = NSRect(x: 0, y: 3, width: 90, height: 28)
        background.view.updateLayer()
        #expect(background.layer.cornerRadius == 8)
        #expect(Support.rgba(NSColor(cgColor: background.layer.backgroundColor!)!) == [0, 0, 0, 0.07])
        #expect(NSColor(cgColor: background.layer.shadowColor!)!.alphaComponent == 0)
    }

    @MainActor @Test func aHighlightedRowDrawsTheTwoPointContinuousRing() {
        let ring = Support.highlighted().ring
        #expect(!ring.isHidden)
        #expect(ring.borderWidth == 2)
        #expect(ring.cornerRadius == 12)
        #expect(ring.cornerCurve == .continuous)
    }

    @MainActor @Test func theRingSharesTheFillFrame() {
        let background = Support.highlighted()
        #expect(background.ring.frame == background.view.layer!.bounds)
    }

    @MainActor @Test func theRingUsesTheSuppliedContrastColour() {
        #expect(Support.rgba(NSColor(cgColor: Support.highlighted().ring.borderColor!)!) == [0, 0, 0, 1])
    }

    @MainActor @Test func dimmingHalvesTheFillAndShadowButNotTheRing() {
        let background = Support.highlighted()
        #expect(background.layer.opacity == 0.5)
        #expect(background.ring.opacity == 1)
    }

    @MainActor @Test func aDimmedCurrentRowKeepsItsFillColour() {
        #expect(Support.rgba(NSColor(cgColor: Support.highlighted().layer.backgroundColor!)!) == [1, 1, 1, 0.85])
    }
}
