#include "pane_compositor_policy.h"
#import "ParcNativeTest.h"

#include <cstdio>
#include <cstdlib>
#include <optional>
#include <vector>

#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
namespace {


using parc::ChoosePaneCompositor;
using parc::PaneCompositorChoice;
using parc::PaneCompositorSlot;
using parc::PaneCompositorSweep;
using parc::PaneHeldFrameFits;
using parc::PaneRect;
using parc::PaneRole;
using parc::PaneSize;
using parc::PlanPaneCompositorSweep;

constexpr PaneRect kWhole{0, 0, 1000, 800};
constexpr PaneRect kLeft{0, 0, 500, 800};
constexpr PaneRect kRight{500, 0, 500, 800};
constexpr PaneRect kInspected{0, 0, 600, 800};
constexpr PaneRect kTools{600, 0, 400, 800};
constexpr PaneRect kPeek{100, 80, 800, 640};

std::optional<PaneSize> SizeOf(std::optional<PaneRect> rect) {
  if (!rect) {
    return std::nullopt;
  }
  return PaneSize{rect->width, rect->height};
}

PaneCompositorSlot Slot(bool on_screen,
                        bool attached,
                        std::optional<PaneRect> rect,
                        uint64_t last_used,
                        bool marked = false,
                        PaneRole role = PaneRole::kPage) {
  PaneCompositorSlot slot;
  slot.on_screen = on_screen;
  slot.attached = attached;
  slot.rect = rect;
  slot.size = SizeOf(rect);
  slot.last_used = last_used;
  slot.marked = marked;
  slot.role = role;
  return slot;
}

bool Is(const std::optional<PaneCompositorChoice>& choice,
        size_t index,
        bool keeps_frame) {
  return choice && choice->index == index && choice->keeps_frame == keeps_frame;
}

std::optional<PaneCompositorChoice> Page(const std::vector<PaneCompositorSlot>& slots,
                                         std::optional<PaneRect> request) {
  return ChoosePaneCompositor(slots, PaneRole::kPage, request, SizeOf(request));
}

std::optional<PaneCompositorChoice> Tools(const std::vector<PaneCompositorSlot>& slots,
                                          std::optional<PaneRect> request) {
  return ChoosePaneCompositor(slots, PaneRole::kDevTools, request, SizeOf(request));
}

}

@interface PaneCompositorPolicyTests : ParcNativeTestCase
@end

@implementation PaneCompositorPolicyTests

- (void)testParkedPagesLeaveTheirFrameForTheirReplacement {
  const std::vector<PaneCompositorSlot> parked = {Slot(false, true, kWhole, 1)};
  Check(Is(Page(parked, kWhole), 0, true),
        "the page replacing a parked page takes its compositor and its frame");
}

- (void)testClosedPagesLeaveTheirFrameForTheirReplacement {
  const std::vector<PaneCompositorSlot> closed = {Slot(false, false, kWhole, 1)};
  Check(Is(Page(closed, kWhole), 0, true),
        "the page replacing a closed page in its pane keeps that pane's frame");
}

- (void)testSwitchingBackReusesThePane {
  const std::vector<PaneCompositorSlot> back = {Slot(false, true, kWhole, 2)};
  Check(Is(Page(back, kWhole), 0, true), "switching back takes the compositor again");
}

- (void)testTheTopBarDoesNotDisqualifyAnOtherwiseFittingFrame {
  const std::vector<PaneCompositorSlot> parked = {Slot(false, true, kWhole, 1)};
  Check(Is(Page(parked, PaneRect{0, 36, 1000, 764}), 0, true),
        "the same pane less its top bar keeps the frame");
}

- (void)testAnOffscreenFrameCanStillFit {
  PaneCompositorSlot elsewhere = Slot(false, true, PaneRect{-5000, -5000, 1000, 800}, 1);
  Check(Is(Page({elsewhere}, kWhole), 0, true),
        "a frame of the pane's size stays whatever place was recorded for it");
}

- (void)testAFrameWithNoRecordedPositionCanStillFit {
  PaneCompositorSlot elsewhere = Slot(false, true, PaneRect{-5000, -5000, 1000, 800}, 1);
  elsewhere.rect = std::nullopt;
  Check(Is(Page({elsewhere}, kWhole), 0, true),
        "a frame of the pane's size stays with no place recorded");
}

- (void)testAnOffscreenRequestUsesItsSize {
  const std::vector<PaneCompositorSlot> parked = {Slot(false, true, kWhole, 1)};
  Check(Is(ChoosePaneCompositor(parked, PaneRole::kPage, PaneRect{-5000, -5000, 1000, 800},
                                SizeOf(kWhole)),
           0, true),
        "a page whose place is not yet its pane's keeps the frame of its size");
}

- (void)testAnUnplacedRequestUsesItsSize {
  const std::vector<PaneCompositorSlot> parked = {Slot(false, true, kWhole, 1)};
  Check(Is(ChoosePaneCompositor(parked, PaneRole::kPage, std::nullopt, SizeOf(kWhole)), 0, true),
        "a page not yet in the window keeps the frame of its size");
}

- (void)testOnscreenCompositorsRemainWithTheirPage {
  const std::vector<PaneCompositorSlot> shown = {Slot(true, true, kWhole, 5)};
  Check(!Page(shown, kWhole), "a compositor on screen is never taken; a new one is made");
}

- (void)testAnEmptyWindowAllocatesItsFirstCompositor {
  Check(!Page({}, kWhole), "an empty window makes its first compositor");
}

- (void)testPeekCardsClearThePreviousPanesFrame {
  const std::vector<PaneCompositorSlot> peek = {Slot(true, true, kWhole, 5),
                                                Slot(false, false, kWhole, 1)};
  Check(Is(Page(peek, kPeek), 1, false), "a Peek card does not show a pane's last frame");
}

- (void)testTheLeftPaneKeepsTheLeftFrame {
  const std::vector<PaneCompositorSlot> split = {Slot(false, true, kLeft, 3),
                                                 Slot(false, true, kRight, 4)};
  Check(Is(Page(split, kLeft), 0, true), "the left pane keeps the left frame");
}

- (void)testTheRightPaneKeepsTheRightFrame {
  const std::vector<PaneCompositorSlot> split = {Slot(false, true, kLeft, 3),
                                                 Slot(false, true, kRight, 4)};
  Check(Is(Page(split, kRight), 1, true), "the right pane keeps the right frame");
}

- (void)testExpandingAcrossTheSplitClearsThePreviousFrame {
  const std::vector<PaneCompositorSlot> split = {Slot(false, true, kLeft, 3),
                                                 Slot(false, true, kRight, 4)};
  Check(Is(Page(split, kWhole), 1, false),
        "a page over a whole split shows neither half; the most recent is cleared");
}

- (void)testLocationBreaksTiesBetweenFittingFrames {
  const std::vector<PaneCompositorSlot> sides = {Slot(false, true, kRight, 5),
                                                 Slot(false, true, kLeft, 4)};
  Check(Is(Page(sides, kLeft), 1, true),
        "among frames of the pane's size the one last shown in the pane is taken");
}

- (void)testReusingADifferentSizeClearsItsFrame {
  const std::vector<PaneCompositorSlot> apart = {Slot(false, true, PaneRect{2000, 0, 10, 10}, 1)};
  Check(Is(Page(apart, kWhole), 0, false),
        "a compositor of another size is reused, cleared, rather than making a new one");
}

- (void)testWideningAnInspectedPageClearsTheFrame {
  const std::vector<PaneCompositorSlot> docked = {
      Slot(false, true, kInspected, 6),
      Slot(false, true, kTools, 7, false, PaneRole::kDevTools)};
  Check(Is(Page(docked, kWhole), 1, false),
        "a page wider than the inspected page it replaces starts cleared");
}

- (void)testAReopenedDockedTabKeepsItsInspectedFrame {
  const std::vector<PaneCompositorSlot> docked = {
      Slot(false, true, kInspected, 6),
      Slot(false, true, kTools, 7, false, PaneRole::kDevTools)};
  Check(Is(Page(docked, kInspected), 0, true),
        "returning to the docked tab keeps the inspected page's frame");
}

- (void)testReturningDevToolsKeepsItsFrame {
  const std::vector<PaneCompositorSlot> docked = {
      Slot(false, true, kInspected, 6),
      Slot(false, true, kTools, 7, false, PaneRole::kDevTools)};
  Check(Is(Tools(docked, kTools), 1, true), "returning DevTools keeps its own frame");
}

- (void)testAWholePageFrameCannotServeAsDevTools {
  const std::vector<PaneCompositorSlot> docked = {
      Slot(false, true, kInspected, 6),
      Slot(false, true, kTools, 7, false, PaneRole::kDevTools)};
  Check(Is(Tools(docked, kWhole), 1, false),
        "a page's frame is never shown as DevTools, nor the reverse");
}

- (void)testADevToolsSizedPageStillHasTheWrongRole {
  Check(Is(Tools({Slot(false, true, kTools, 1)}, kTools), 0, false),
        "a page's frame of the tools' size is not shown as DevTools");
}

- (void)testFitWinsOverRecencyAndAvailability {
  const std::vector<PaneCompositorSlot> mixed = {Slot(false, false, kLeft, 9),
                                                 Slot(false, true, kWhole, 1)};
  Check(Is(Page(mixed, kWhole), 1, true), "a fitting frame wins over a free or recent one");
}

- (void)testFreeCompositorsWinWhenBothFramesFit {
  const std::vector<PaneCompositorSlot> both = {Slot(false, true, kWhole, 9),
                                                Slot(false, false, kWhole, 2)};
  Check(Is(Page(both, kWhole), 1, true),
        "between fitting frames a free compositor wins over a hidden page's");
}

- (void)testFreeCompositorsWinWhenNeitherFrameFits {
  const std::vector<PaneCompositorSlot> neither = {Slot(false, true, kLeft, 9),
                                                   Slot(false, false, kRight, 2)};
  Check(Is(Page(neither, kWhole), 1, false),
        "between cleared ones a free compositor wins over a hidden page's");
}

- (void)testUndrawnCompositorsCompeteByRecency {
  const std::vector<PaneCompositorSlot> unsized = {Slot(false, true, std::nullopt, 7),
                                                   Slot(false, true, std::nullopt, 8)};
  Check(Is(Page(unsized, kWhole), 1, false),
        "a compositor that has drawn nothing fits nothing; the most recent is cleared");
}

- (void)testAnUnsizedPageCanReuseAClearedCompositor {
  const std::vector<PaneCompositorSlot> unsized = {Slot(false, true, std::nullopt, 7),
                                                   Slot(false, true, std::nullopt, 8)};
  Check(Is(Page(unsized, std::nullopt), 1, false),
        "a page of no size yet still reuses one, cleared");
}

- (void)testAnUnsizedPageCannotReuseAFrame {
  Check(Is(Page({Slot(false, true, kWhole, 7)}, std::nullopt), 0, false),
        "a page of no size yet never keeps a frame");
}

- (void)testIdenticalSizesFit {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  Check(PaneHeldFrameFits(whole, PaneRole::kPage, PaneSize{1000, 800}), "identical sizes fit");
}

- (void)testTheMinimumCoverageFits {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  Check(PaneHeldFrameFits(whole, PaneRole::kPage, PaneSize{1000, 720}),
        "90% of the held size fits");
}

- (void)testTooLittleOfTheHeldFrameFailsToFit {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  Check(!PaneHeldFrameFits(whole, PaneRole::kPage, PaneSize{1000, 719}),
        "less than 90% of the held size does not");
}

- (void)testTooLittleOfTheRequestedAreaFailsToFit {
  Check(!PaneHeldFrameFits(Slot(false, true, PaneRect{0, 0, 1000, 719}, 1), PaneRole::kPage,
                           PaneSize{1000, 800}),
        "a held size covering less than 90% of the request does not");
}

- (void)testEqualAreaWithTheWrongShapeFailsToFit {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  Check(!PaneHeldFrameFits(whole, PaneRole::kPage, PaneSize{1200, 667}),
        "the same area in another shape does not");
}

- (void)testFramesCannotChangeRoles {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  Check(!PaneHeldFrameFits(whole, PaneRole::kDevTools, PaneSize{1000, 800}), "another role does not");
}

- (void)testAMissingSizeCannotFit {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  Check(!PaneHeldFrameFits(whole, PaneRole::kPage, std::nullopt), "no request size does not");
}

- (void)testAnEmptySizeCannotFit {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  Check(!PaneHeldFrameFits(whole, PaneRole::kPage, PaneSize{0, 0}), "an empty size does not");
}

- (void)testAnUndrawnCompositorHasNoFrame {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  PaneCompositorSlot unsized = whole;
  unsized.size = std::nullopt;
  Check(!PaneHeldFrameFits(unsized, PaneRole::kPage, PaneSize{1000, 800}),
        "a compositor that has drawn nothing holds no frame");
}

- (void)testPositionDoesNotDetermineSizeFit {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  PaneCompositorSlot moved = whole;
  moved.rect = kPeek;
  Check(PaneHeldFrameFits(moved, PaneRole::kPage, PaneSize{1000, 800}),
        "the place last recorded does not decide");
}

- (void)testTheSecondSweepRetiresOlderIdleCompositors {
  std::vector<PaneCompositorSlot> slots = {Slot(true, true, kWhole, 5),
                                           Slot(false, true, kRight, 4),
                                           Slot(false, false, kLeft, 2)};
  auto plan = PlanPaneCompositorSweep(slots, true, 1);
  Check(plan[0] == PaneCompositorSweep::kKeep, "the shown compositor stays");
  Check(plan[1] == PaneCompositorSweep::kKeep, "the most recent idle one is the spare");
  Check(plan[2] == PaneCompositorSweep::kMark, "an older idle one is marked first");
  slots[2].marked = true;
  plan = PlanPaneCompositorSweep(slots, true, 1);
  Check(plan[2] == PaneCompositorSweep::kRetire, "and retired at the next sweep");
}

- (void)testClosingAWindowRemovesItsSpare {
  std::vector<PaneCompositorSlot> slots = {Slot(true, true, kWhole, 5),
                                           Slot(false, true, kRight, 4),
                                           Slot(false, false, kLeft, 2)};
  slots[2].marked = true;
  auto plan = PlanPaneCompositorSweep(slots, true, 0);
  Check(plan[1] == PaneCompositorSweep::kMark && plan[2] == PaneCompositorSweep::kRetire,
        "with no spare (window gone) every idle one goes");
}

- (void)testReturningOnscreenCancelsRetirement {
  std::vector<PaneCompositorSlot> slots = {Slot(true, true, kWhole, 5),
                                           Slot(false, true, kRight, 4),
                                           Slot(false, false, kLeft, 2)};
  slots[2].marked = true;
  slots[2].on_screen = true;
  auto plan = PlanPaneCompositorSweep(slots, true, 0);
  Check(plan[2] == PaneCompositorSweep::kKeep, "a compositor back on screen is kept");
}

- (void)testHiddenWindowsKeepTheirPagesAndOneFreeSpare {
  std::vector<PaneCompositorSlot> slots = {Slot(false, true, kLeft, 5, true),
                                           Slot(false, true, kRight, 4, true),
                                           Slot(false, false, kWhole, 3, true),
                                           Slot(false, false, kWhole, 2, true)};
  const auto plan = PlanPaneCompositorSweep(slots, false, 1);
  Check(plan[0] == PaneCompositorSweep::kKeep && plan[1] == PaneCompositorSweep::kKeep,
        "hidden pages of a hidden window keep their compositors");
  Check(plan[2] == PaneCompositorSweep::kKeep, "the most recent free one is the spare");
  Check(plan[3] == PaneCompositorSweep::kRetire, "older free ones are retired");
}

- (void)testShowingAWindowMakesHiddenPagesEligibleForRetirement {
  std::vector<PaneCompositorSlot> slots = {Slot(false, true, kLeft, 5, true),
                                           Slot(false, true, kRight, 4, true),
                                           Slot(false, false, kWhole, 3, true),
                                           Slot(false, false, kWhole, 2, true)};
  const auto visible = PlanPaneCompositorSweep(slots, true, 1);
  Check(visible[0] == PaneCompositorSweep::kKeep && visible[1] == PaneCompositorSweep::kRetire,
        "once the window is visible the hidden pages' compositors are idle too");
}

- (void)testTouchingPanesHaveNoOverlap {
  Check(parc::PaneOverlapArea(kLeft, kRight) == 0, "touching panes do not overlap");
}

- (void)testAContainedPaneOverlapsByItsArea {
  Check(parc::PaneOverlapArea(kWhole, kLeft) == 500 * 800, "contained pane overlaps by its area");
}

- (void)testOverlappingPanesUseTheirIntersection {
  Check(parc::PaneOverlapArea(PaneRect{-10, -10, 20, 20}, PaneRect{0, 0, 20, 20}) == 100,
        "partial overlap");
}

@end
