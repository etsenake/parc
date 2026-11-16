import AppKit

@main struct SidebarRowAppearanceTests {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func rgba(_ color: NSColor, _ space: NSColorSpace = .sRGB) -> [CGFloat] {
            let c = color.usingColorSpace(space)!
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
        }

        for bits in 0..<16 {
            let state = SidebarRowAppearance(current: bits & 1 != 0, contentVisible: bits & 2 != 0,
                                             multiSelected: bits & 4 != 0, hovered: bits & 8 != 0)
            let expected: SidebarRowAppearance.Fill? = bits & 1 != 0 ? .current : bits & 2 != 0 ? .contentVisible
                : bits & 4 != 0 ? .multiSelected : bits & 8 != 0 ? .hovered : nil
            check(state.fill == expected, "Fill precedence \(bits)")
            check(state.showsShadow == (bits & 1 != 0), "Only the current row casts the selected shadow \(bits)")
            var dragged = state; dragged.keyDragged = true
            check(dragged.fill == .current && dragged.showsShadow == (bits & 1 != 0),
                  "The key dragged item takes the current fill but not its shadow \(bits)")
            var child = state; child.splitChild = true
            check(child.fill == nil && !child.showsShadow, "A split child ignores row selection and hover \(bits)")
            child.splitGroupSelected = true
            check(child.fill == .splitChild && !child.showsShadow, "A selected split's child shows its own background \(bits)")
        }
        check(rgba(SidebarRowAppearance.color(.splitChild, dark: false)) == [0, 0, 0, 0.07], "TabCellChildBackground light")
        check(rgba(SidebarRowAppearance.color(.splitChild, dark: true)) == [1, 1, 1, 0.07], "TabCellChildBackground dark")
        let wide = NSRect(x: 0, y: 0, width: 90, height: 28), thin = NSRect(x: 0, y: 0, width: 10, height: 28)
        check(SidebarRowAppearance().cornerRadius(in: wide) == 12, "Row corners stay 12")
        check(SidebarRowAppearance(splitChild: true).cornerRadius(in: wide) == 8
              && SidebarRowAppearance(splitChild: true).cornerRadius(in: thin) == 5, "Split child rounds by min(width / 2, 8)")

        check(rgba(SidebarRowAppearance.color(.current, dark: false)) == [1, 1, 1, 0.85], "Current light")
        check(rgba(SidebarRowAppearance.color(.current, dark: true), .displayP3) == [0.98, 0.984, 1, 0.2], "Current dark")
        check(rgba(SidebarRowAppearance.color(.contentVisible, dark: false)) == [1, 1, 1, 0.7], "Content visible light")
        check(rgba(SidebarRowAppearance.color(.contentVisible, dark: true), .displayP3) == [0.98, 0.984, 1, 0.15], "Content visible dark")
        check(rgba(SidebarRowAppearance.color(.multiSelected, dark: false)) == [0, 0, 0, 0.1], "Multi-selected light")
        check(rgba(SidebarRowAppearance.color(.multiSelected, dark: true), .displayP3) == [0.98, 0.984, 1, 0.1], "Multi-selected dark")
        check(rgba(SidebarRowAppearance.color(.hovered, dark: false), .displayP3) == [0.055, 0.059, 0.063, 0.05], "Hovered light")
        check(rgba(SidebarRowAppearance.color(.hovered, dark: true), .displayP3) == [0.98, 0.984, 1, 0.1], "Hovered dark")
        check(rgba(SidebarRowAppearance.shadowColor(dark: false)) == [0, 0, 0, 0.2], "Selected shadow light")
        check(SidebarRowAppearance.shadowColor(dark: true).alphaComponent == 0, "Selected shadow is clear in dark")
        check(rgba(SidebarRowAppearance.controlFill(pressed: false, dark: false)) == [0, 0, 0, 0.071], "GrayA4 light")
        check(rgba(SidebarRowAppearance.controlFill(pressed: true, dark: false)) == [0, 0, 0, 0.09], "GrayA5 light")
        check(rgba(SidebarRowAppearance.controlFill(pressed: false, dark: true)) == [1, 1, 1, 0.077], "GrayA4 dark")
        check(rgba(SidebarRowAppearance.controlFill(pressed: true, dark: true)) == [1, 1, 1, 0.103], "GrayA5 dark")

        let row = NSRect(x: 0, y: 0, width: 212, height: 36)
        check(SidebarRowAppearance.iconSlotFrame(in: row) == NSRect(x: 6, y: 6, width: 24, height: 24), "Icon slot")
        check(SidebarRowAppearance.iconFrame(in: row) == NSRect(x: 10, y: 10, width: 16, height: 16), "Centered favicon")
        let parcRow = NSRect(x: 0, y: 0, width: 212, height: 35)
        check(SidebarRowAppearance.iconFrame(in: parcRow).origin == NSPoint(x: 10, y: 9), "Pixel-aligned favicon in a 35-point row")
        check(SidebarRowAppearance.iconSlotFrame(in: row).maxX + 6 == SidebarRowAppearance.titleInset, "Title follows slot spacing")
        let label = NSTextField(labelWithString: "Title"); label.font = .systemFont(ofSize: SidebarRowAppearance.titleFontSize)
        check(SidebarRowAppearance.titleTextPadding == 2 && label.alignmentRectInsets.left == SidebarRowAppearance.titleTextPadding
              && label.alignmentRectInsets.right == SidebarRowAppearance.titleTextPadding,
              "A stacked label's alignment rect sits 2 points inside each edge of its frame")

        check(SidebarRowAppearance.slashFrame(in: row) == NSRect(x: 30, y: 10, width: 4, height: 15), "Slash geometry")
        check(SidebarRowAppearance.resetRegionFrame(in: row) == NSRect(x: 0, y: 0, width: 30, height: 36), "Icon region ends at the slash")
        check(SidebarRowAppearance.resetTitleInset == 38, "Resettable title starts after slash and its spacing")
        check(SidebarRowAppearance.closeFrame(in: row) == NSRect(x: 182, y: 6, width: 24, height: 24), "Close geometry")
        check(SidebarRowAppearance.titleTrailingEdge(in: row, closeVisible: true) == 180, "Title stops before visible Close")
        check(SidebarRowAppearance.titleTrailingEdge(in: row, closeVisible: false) == 202, "Title widens while Close is hidden")
        let hoveredSpan = SidebarRowAppearance.titleLabelSpan(resettable: false, trailing: SidebarRowAppearance.titleTrailingEdge(in: row, closeVisible: true))
        check(hoveredSpan.minX == 34 && hoveredSpan.minX + hoveredSpan.width == SidebarRowAppearance.closeFrame(in: row).minX,
              "A hovered title's text runs from 36 to 2 before Close; its frame ends at Close")
        let idleSpan = SidebarRowAppearance.titleLabelSpan(resettable: false, trailing: SidebarRowAppearance.titleTrailingEdge(in: row, closeVisible: false))
        check(idleSpan.minX == 34 && idleSpan.minX + idleSpan.width == 204, "An idle title's text runs to 10 inside the row")
        let resetSpan = SidebarRowAppearance.titleLabelSpan(resettable: true, trailing: 202)
        check(resetSpan.minX == SidebarRowAppearance.resetTitleInset - 2 && resetSpan.minX + resetSpan.width == 204,
              "A resettable row's title text starts at 38, after the slash")
        check(SidebarRowAppearance.titleLabelSpan(resettable: false, trailing: 20).width == 0, "A row too narrow for a title gives it no width")
        check(SidebarRowAppearance.subtitleLift == 7 && SidebarRowAppearance.subtitleDuration == 0.1
              && SidebarRowAppearance.subtitleTextAlpha == 0.5, "Hover subtitle motion and color")
        check(SidebarRowAppearance.resetSubtitle == "Back to Pinned URL", "Reset hover subtitle text")
        check(SidebarRowAppearance.separateSubtitle == "Separate From Pinned Tab", "Separate hover subtitle text")
        check(SidebarRowAppearance.subtitleFontSize == 11, "Subtitle uses an 11-point system font")

        func child(_ width: CGFloat, recording: Bool = false, hovered: Bool = false, close: Bool = true)
            -> SidebarRowAppearance.SplitChildLayout {
            SidebarRowAppearance.splitChildLayout(in: NSRect(x: 0, y: 0, width: width, height: 35), titleHeight: 17,
                                                  recording: recording, closeAvailable: close, groupHovered: hovered)
        }
        let idle = child(100)
        check(idle.cell == NSRect(x: 0, y: 3, width: 100, height: 28), "28-point child centered in the row")
        check(idle.iconSlot == NSRect(x: 2, y: 5, width: 24, height: 24) && idle.indicator == nil, "Icon slot 2 points in")
        check(!idle.showsClose && idle.title == NSRect(x: 32, y: 8, width: 66, height: 17),
              "Title 6 after the slot, to the 2-point trailing inset")
        let hovered = child(100, hovered: true)
        check(hovered.showsClose && hovered.close == NSRect(x: 74, y: 5, width: 24, height: 24), "Close 2 inside the edge")
        check(hovered.title?.width == 40, "Title ends 2 before a visible Close")
        check(!child(100, hovered: true, close: false).showsClose, "No Close without a close command")
        let recording = child(100, recording: true)
        check(recording.indicator == NSRect(x: 2, y: 10, width: 14, height: 14) && recording.iconSlot.minX == 16
              && recording.title?.minX == 46, "Recording indicator precedes the icon")
        check(child(41, recording: true).indicator == nil && child(42, recording: true).indicator != nil,
              "The indicator needs room for itself, the slot and both insets")
        let narrow = child(28, recording: true, hovered: true)
        check(narrow.iconSlot == NSRect(x: 0, y: 5, width: 28, height: 24) && narrow.title == nil && !narrow.showsClose
              && narrow.indicator == nil, "A child no wider than its slot centers only the icon")
        check(child(50, hovered: true).showsClose && !child(49, hovered: true).showsClose, "Close must clear the icon")
        check(child(54).title == nil && child(55).title?.width == 21, "Titles need more than 20 points")

        let all: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let leading: CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        check(SidebarRowAppearance().splitsResetRegions && SidebarRowAppearance().resetRegionCorners == all, "Idle row splits regions")
        for state in [SidebarRowAppearance(current: true), SidebarRowAppearance(contentVisible: true),
                      SidebarRowAppearance(multiSelected: true), SidebarRowAppearance(hovered: true),
                      SidebarRowAppearance(highlighted: true)] {
            check(!state.splitsResetRegions && state.resetRegionCorners == leading, "Filled or ringed row keeps only the icon region")
        }
        check(SidebarRowAppearance(highlighted: true).fill == nil, "Highlight is a ring, not a fill")
        check(SidebarRowAppearance(dimmed: true).fill == nil, "Dimming adds no fill")
        check(rgba(SidebarRowAppearance.regionFill(pressed: true, dark: false), .displayP3) == [0.055, 0.059, 0.063, 0.065], "Pressed light")
        check(rgba(SidebarRowAppearance.regionFill(pressed: true, dark: true), .displayP3) == [0.98, 0.984, 1, 0.065], "Pressed dark")
        check(rgba(SidebarRowAppearance.regionFill(pressed: false, dark: false), .displayP3) == [0.055, 0.059, 0.063, 0.05], "Region hover light")
        check(rgba(SidebarRowAppearance.slashColor(dark: false), .displayP3) == [0, 0, 0, 0.3], "TabCellSlash light")
        check(rgba(SidebarRowAppearance.slashColor(dark: true), .displayP3) == [1, 1, 1, 0.3], "TabCellSlash dark")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        window.contentView!.addSubview(host)
        let background = SidebarRowBackgroundView(frame: NSRect(x: 8, y: 10, width: 212, height: 35))
        host.addSubview(background)
        check(!background.isFlipped, "Fill view keeps AppKit's unflipped shadow direction")
        check(background.hitTest(NSPoint(x: 20, y: 20)) == nil, "Fill never takes row input")
        check(!background.isAccessibilityElement(), "Fill adds no accessibility element")
        check(!background.clipsToBounds && background.layer?.masksToBounds == false,
              "Selected shadow is not clipped to the 36-point fill")
        check(background.layer?.allowsGroupOpacity == false,
              "Translucent current/hover fills composite onto the theme, not an offscreen backing")
        background.updateLayer()
        let layer = background.fillLayer, ring = background.ringLayer
        check(layer.superlayer === background.layer && ring.superlayer === background.layer, "Fill and ring are sibling layers")
        check(layer.backgroundColor == nil && background.layer!.backgroundColor == nil, "Idle row is clear")
        check(layer.cornerRadius == 12 && layer.cornerCurve == .continuous, "Continuous 12-point corners")
        check(layer.frame == background.layer!.bounds, "Fill covers the visible row")
        check(ring.isHidden && layer.opacity == 1, "No ring or dimming at rest")
        check(layer.shadowRadius == 1 && layer.shadowOffset == CGSize(width: 0, height: -1) && layer.shadowOpacity == 1,
              "Recovered shadow geometry")
        check(layer.masksToBounds == false && background.layer?.masksToBounds == false,
              "updateLayer keeps the host and fill unclipped")
        check(NSColor(cgColor: layer.shadowColor!)!.alphaComponent == 0, "No shadow without the current item")
        background.appearanceState = SidebarRowAppearance(current: true, hovered: true)
        background.updateLayer()
        check(NSColor(cgColor: layer.backgroundColor!).map { rgba($0) } == [1, 1, 1, 0.85], "Current fill wins over hover")
        check(NSColor(cgColor: layer.shadowColor!).map { rgba($0) } == [0, 0, 0, 0.2], "Current row shadow")
        background.dark = true; background.updateLayer()
        check(NSColor(cgColor: layer.shadowColor!)!.alphaComponent == 0, "Dark current row has no shadow")
        background.appearanceState = SidebarRowAppearance(multiSelected: true, hovered: true)
        background.dark = false; background.updateLayer()
        check(NSColor(cgColor: layer.backgroundColor!).map { rgba($0) } == [0, 0, 0, 0.1], "Multi-selection wins over hover")
        background.frame = NSRect(x: 0, y: 0, width: 10, height: 35)
        background.updateLayer()
        check(layer.shadowPath != nil, "Narrow compact row keeps a valid shadow path")
        background.appearanceState = SidebarRowAppearance(splitChild: true, splitGroupSelected: true)
        background.frame = NSRect(x: 0, y: 3, width: 90, height: 28)
        background.updateLayer()
        check(layer.cornerRadius == 8 && NSColor(cgColor: layer.backgroundColor!).map { rgba($0) } == [0, 0, 0, 0.07]
              && NSColor(cgColor: layer.shadowColor!)!.alphaComponent == 0, "Selected split child pill")
        background.frame = NSRect(x: 8, y: 10, width: 212, height: 35)
        background.ringColor = .black
        background.appearanceState = SidebarRowAppearance(current: true, highlighted: true, dimmed: true)
        background.updateLayer()
        check(!ring.isHidden && ring.borderWidth == 2 && ring.cornerRadius == 12 && ring.cornerCurve == .continuous,
              "Highlighted row draws the 2-point continuous ring")
        check(ring.frame == background.layer!.bounds, "Ring shares the fill frame")
        check(NSColor(cgColor: ring.borderColor!).map { rgba($0) } == [0, 0, 0, 1], "Ring uses the supplied contrast color")
        check(layer.opacity == 0.5 && ring.opacity == 1, "shouldDim halves the fill and shadow but not the ring")
        check(NSColor(cgColor: layer.backgroundColor!).map { rgba($0) } == [1, 1, 1, 0.85], "Dimmed current row keeps its fill color")

        check(background.paintedBounds == background.bounds, "updateLayer records the bounds it painted")
        let painted = background.paintedBounds
        let shadow = layer.shadowPath
        background.layout()
        check(background.paintedBounds == painted && layer.shadowPath === shadow && layer.frame == background.layer!.bounds,
              "No-op layout does not rebuild unchanged fill and ring layers")
        let pending = background.appearanceState
        let pendingRing = background.ringColor
        background.appearanceState = pending
        background.dark = false
        background.ringColor = pendingRing
        check(layer.shadowPath === shadow && background.paintedBounds == painted,
              "Unchanged appearance inputs do not rebuild layers")
        background.frame.origin = NSPoint(x: 40, y: 18)
        background.layout()
        check(background.bounds.size == NSSize(width: 212, height: 35) && background.paintedBounds == painted
              && layer.shadowPath === shadow, "Moving the unflipped fill view does not redraw")
        background.appearanceState = SidebarRowAppearance(hovered: true)
        check(NSColor(cgColor: layer.backgroundColor!).map { rgba($0, .displayP3) } == [0.055, 0.059, 0.063, 0.05]
              && ring.isHidden && layer.opacity == 1, "Hover fill still paints from appearance without a layout")
        background.layout()
        check(NSColor(cgColor: layer.backgroundColor!).map { rgba($0, .displayP3) } == [0.055, 0.059, 0.063, 0.05],
              "A follow-up layout keeps the appearance that already painted")
        background.setFrameSize(NSSize(width: 180, height: 35))
        check(background.paintedBounds != background.bounds, "A width change leaves painted bounds stale until layout")
        background.layout()
        check(background.paintedBounds == background.bounds
              && layer.frame.size == NSSize(width: 180, height: 35) && ring.frame.size == NSSize(width: 180, height: 35),
              "A width change still refreshes fill and ring frames")
        let sized = background.paintedBounds
        let sizedShadow = layer.shadowPath
        background.layout()
        check(background.paintedBounds == sized && layer.shadowPath === sizedShadow,
              "A follow-up layout at the new size is a no-op")
        background.setFrameSize(NSSize(width: 180, height: 36))
        background.layout()
        check(background.paintedBounds == background.bounds && layer.frame.size.height == 36 && layer.shadowPath != nil
              && layer.shadowPath !== sizedShadow, "A height change still refreshes the shadow path bounds")
        background.dark = true
        check(NSColor(cgColor: layer.backgroundColor!).map { rgba($0, .displayP3) } == [0.98, 0.984, 1, 0.1],
              "Dark appearance still paints the hover fill")
        background.appearanceState = SidebarRowAppearance(current: true, highlighted: true, dimmed: true)
        background.ringColor = .white
        check(!ring.isHidden && ring.borderWidth == 2 && layer.opacity == 0.5
              && NSColor(cgColor: ring.borderColor!).map { rgba($0) } == [1, 1, 1, 1],
              "Ring color, dimming and highlight still update together")
        check(layer.opacity == 0.5 && ring.opacity == 1, "Dimming still does not fade the ring")
        check(!background.clipsToBounds && background.layer?.masksToBounds == false
              && background.layer?.allowsGroupOpacity == false && layer.masksToBounds == false,
              "Skip does not clip the selected shadow or flatten translucent fills")

        print("SidebarRowAppearanceTests: \(checks) checks passed")
    }
}

private final class FlippedHost: NSView {
    override var isFlipped: Bool { true }
}
