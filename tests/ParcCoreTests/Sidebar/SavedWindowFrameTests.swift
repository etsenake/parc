import Foundation
import Testing
@testable import ParcCore

struct SavedWindowFrameTests {
    func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> SavedWindowFrame {
        SavedWindowFrame(x: x, y: y, width: width, height: height)!
    }

    let minimum = CGSize(width: 760, height: 540)
    let laptop = CGRect(x: 0, y: 90, width: 1512, height: 858)
    let external = CGRect(x: 1512, y: -200, width: 2560, height: 1415)
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
    var onLaptop: SavedWindowFrame { frame(100, 150, 1000, 700) }
    var onExternal: SavedWindowFrame { frame(2200, 100, 1400, 900) }

    @Test func onlyFiniteFramesWithARealSizeAreSavedAndKeepTheirExactPositionAndSize() {
        #expect(SavedWindowFrame(CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)) == nil
              && SavedWindowFrame(CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)) == nil
              && SavedWindowFrame(CGRect(x: 0, y: 0, width: 0, height: 10)) == nil
              && SavedWindowFrame(x: 0, y: 0, width: 10, height: -1) == nil
              && SavedWindowFrame(x: 1e308, y: 1e308, width: 1e308, height: 1e308) == nil
              && SavedWindowFrame(x: 0, y: -2e7, width: 800, height: 600) == nil,
              "only finite frames with a real size and desktop-sized numbers are saved")
        #expect(SavedWindowFrame(CGRect(x: -40.5, y: 12, width: 900, height: 700))?.rect
              == CGRect(x: -40.5, y: 12, width: 900, height: 700), "a frame keeps its exact position and size")
    }

    @Test func aFrameThatStillFitsItsScreenComesBackUntouched() {
        let onLaptop = frame(100, 150, 1000, 700)
        #expect(onLaptop.placed(minimumSize: minimum, screens: [laptop, external]) == onLaptop.rect,
              "a frame that still fits its screen comes back untouched")
        let onLeft = frame(-1800, 100, 1200, 800)
        #expect(onLeft.placed(minimumSize: minimum, screens: [laptop, left]) == onLeft.rect,
              "a display left of the main one keeps its negative position")
    }

    @Test func aWindowFromAnUnpluggedOrShrunkDisplayMovesOntoTheNearestScreenAndFitsIt() {
        let onExternal = frame(2200, 100, 1400, 900)
        #expect(onExternal.placed(minimumSize: minimum, screens: [laptop]) == CGRect(x: 112, y: 90, width: 1400, height: 858),
              "a window from an unplugged display moves onto the nearest remaining screen and fits it")
        #expect(onExternal.placed(minimumSize: minimum, screens: [laptop, external]) == onExternal.rect,
              "the same window stays put while its display is connected")

        let shrunk = CGRect(x: 1512, y: -200, width: 1280, height: 700)
        #expect(onExternal.placed(minimumSize: minimum, screens: [laptop, shrunk]) == CGRect(x: 1512, y: -200, width: 1280, height: 700),
              "a display that got smaller shrinks the window to its visible area")
    }

    @Test func aStraddlingWindowSettlesOnTheDisplayHoldingMostOfIt() {
        let straddling = frame(1200, 300, 1000, 600)
        #expect(straddling.placed(minimumSize: minimum, screens: [laptop, external]) == CGRect(x: 1512, y: 300, width: 1000, height: 600),
              "a window straddling two displays settles on the one holding most of it")
        let mostlyLaptop = frame(900, 300, 1000, 600)
        #expect(mostlyLaptop.placed(minimumSize: minimum, screens: [laptop, external]) == CGRect(x: 512, y: 300, width: 1000, height: 600),
              "and moves the shortest way back onto that display")
    }

    @Test func aWindowAboveTheVisibleAreaIsMovedDownAndAFullScreenFrameFitsIt() {
        let underMenuBar = frame(200, 600, 900, 700)
        #expect(underMenuBar.placed(minimumSize: minimum, screens: [laptop]) == CGRect(x: 200, y: 248, width: 900, height: 700),
              "a window poking above the visible area is moved down below the menu bar")
        let fullScreenSized = frame(0, 0, 1512, 982)
        #expect(fullScreenSized.placed(minimumSize: minimum, screens: [laptop]) == laptop,
              "a screen-sized frame fits the visible area, clear of the menu bar and Dock")
    }

    @Test func aTinyFrameGrowsToTheMinimumAndATinyScreenStillHoldsTheWindow() {
        let tiny = frame(300, 400, 400, 300)
        #expect(tiny.placed(minimumSize: minimum, screens: [laptop]) == CGRect(x: 300, y: 160, width: 760, height: 540),
              "a frame below the window's minimum grows to it, keeping its top-left corner")
        let tinyScreen = CGRect(x: 0, y: 0, width: 640, height: 480)
        #expect(onLaptop.placed(minimumSize: minimum, screens: [tinyScreen]) == tinyScreen,
              "a screen smaller than the minimum still gets the whole window on screen")
    }

    @Test func aFarAwayFrameGoesToTheClosestScreen() {
        let farAway = frame(9000, 9000, 800, 600)
        #expect(farAway.placed(minimumSize: minimum, screens: [laptop, external]) == CGRect(x: 3272, y: 615, width: 800, height: 600),
              "a frame far from every screen goes to the closest one")
        let belowLeft = frame(-3000, -3000, 800, 600)
        #expect(belowLeft.placed(minimumSize: minimum, screens: [laptop, left]) == CGRect(x: -1920, y: 0, width: 800, height: 600),
              "including below and left of the screens")
    }

    @Test func withoutAUsableScreenTheCallerKeepsItsOwnPlacementAndEmptyScreensAreIgnored() {
        #expect(onLaptop.placed(minimumSize: minimum, screens: []) == nil
              && onLaptop.placed(minimumSize: minimum, screens: [.zero, CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)]) == nil,
              "without a usable screen the caller keeps its own placement")
        #expect(onExternal.placed(minimumSize: minimum, screens: [.zero, laptop]) == CGRect(x: 112, y: 90, width: 1400, height: 858),
              "empty screens are ignored")

    }
}
