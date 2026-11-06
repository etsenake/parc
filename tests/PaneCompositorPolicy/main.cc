#include "pane_compositor_policy.h"

#include <cstdio>
#include <cstdlib>
#include <optional>
#include <vector>

namespace {

unsigned checks = 0;

void Check(bool condition, const char* message) {
  ++checks;
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}

using parc::ChoosePaneCompositor;
using parc::PaneCompositorChoice;
using parc::PaneCompositorSlot;
using parc::PaneCompositorSweep;
using parc::PaneHeldFrameFits;
using parc::PaneRect;
using parc::PaneRole;
using parc::PlanPaneCompositorSweep;

constexpr PaneRect kWhole{0, 0, 1000, 800};
constexpr PaneRect kLeft{0, 0, 500, 800};
constexpr PaneRect kRight{500, 0, 500, 800};
// Docked DevTools on the right narrows the inspected page to 600 points.
constexpr PaneRect kInspected{0, 0, 600, 800};
constexpr PaneRect kTools{600, 0, 400, 800};
constexpr PaneRect kPeek{100, 80, 800, 640};

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
  return ChoosePaneCompositor(slots, PaneRole::kPage, request);
}

void TabSwitchInOnePane() {
  // Tab A was shown in the pane; the shell parked it and shows tab B there.
  // A's hidden page keeps its compositor until B takes it.
  const std::vector<PaneCompositorSlot> parked = {Slot(false, true, kWhole, 1)};
  Check(Is(Page(parked, kWhole), 0, true),
        "the page replacing a parked page takes its compositor and its frame");
  // Tab A was closed: its compositor is free and still holds A's last frame
  // in the same place.
  const std::vector<PaneCompositorSlot> closed = {Slot(false, false, kWhole, 1)};
  Check(Is(Page(closed, kWhole), 0, true),
        "the page replacing a closed page in its pane keeps that pane's frame");
  const std::vector<PaneCompositorSlot> back = {Slot(false, true, kWhole, 2)};
  Check(Is(Page(back, kWhole), 0, true), "switching back takes the compositor again");
  // A few points of difference (a top bar appearing) is still the same pane.
  Check(Is(Page(parked, PaneRect{0, 36, 1000, 764}), 0, true),
        "the same pane less its top bar keeps the frame");
}

void OnScreenIsNeverTaken() {
  const std::vector<PaneCompositorSlot> shown = {Slot(true, true, kWhole, 5)};
  Check(!Page(shown, kWhole), "a compositor on screen is never taken; a new one is made");
  Check(!Page({}, kWhole), "an empty window makes its first compositor");
}

void AnotherPanesFrameIsCleared() {
  // Peek opens over a shown page; the only free compositor last showed a
  // whole pane, so the Peek card takes it cleared, not that pane's frame.
  const std::vector<PaneCompositorSlot> peek = {Slot(true, true, kWhole, 5),
                                                Slot(false, false, kWhole, 1)};
  Check(Is(Page(peek, kPeek), 1, false), "a Peek card does not show a pane's last frame");
  // Split A|B switches to split C|D: each side keeps its own side's frame.
  const std::vector<PaneCompositorSlot> split = {Slot(false, true, kLeft, 3),
                                                 Slot(false, true, kRight, 4)};
  Check(Is(Page(split, kLeft), 0, true), "the left pane keeps the left frame");
  Check(Is(Page(split, kRight), 1, true), "the right pane keeps the right frame");
  // A|B closes to one page: neither half is that page's pane.
  Check(Is(Page(split, kWhole), 1, false),
        "a page over a whole split shows neither half; the most recent is cleared");
  const std::vector<PaneCompositorSlot> half = {Slot(true, true, kLeft, 5),
                                                Slot(false, true, kRight, 4)};
  Check(Is(Page(half, kLeft), 1, false),
        "a page never shows the frame of the pane beside it");
  // A page far from where the frame was drawn.
  const std::vector<PaneCompositorSlot> apart = {Slot(false, true, PaneRect{2000, 0, 10, 10}, 1)};
  Check(Is(Page(apart, kWhole), 0, false),
        "a compositor from elsewhere is reused, cleared, rather than making a new one");
  // Leaving a tab with docked DevTools: the narrowed page's frame is not the
  // whole pane's, and the tools' frame is not a page's.
  const std::vector<PaneCompositorSlot> docked = {
      Slot(false, true, kInspected, 6),
      Slot(false, true, kTools, 7, false, PaneRole::kDevTools)};
  // Neither fits; the most recent is taken cleared, which leaves the
  // inspected page's frame for the return.
  Check(Is(Page(docked, kWhole), 1, false),
        "a page wider than the inspected page it replaces starts cleared");
  Check(Is(Page(docked, kInspected), 0, true),
        "returning to the docked tab keeps the inspected page's frame");
  Check(Is(ChoosePaneCompositor(docked, PaneRole::kDevTools, kTools), 1, true),
        "returning DevTools keeps its own frame");
  Check(Is(ChoosePaneCompositor(docked, PaneRole::kDevTools, kWhole), 1, false),
        "a page's frame is never shown as DevTools, nor the reverse");
}

void Preferences() {
  // A fitting compositor wins over a free or more recent one that doesn't.
  const std::vector<PaneCompositorSlot> mixed = {Slot(false, false, kLeft, 9),
                                                 Slot(false, true, kWhole, 1)};
  Check(Is(Page(mixed, kWhole), 1, true), "a fitting frame wins over a free or recent one");
  const std::vector<PaneCompositorSlot> both = {Slot(false, true, kWhole, 9),
                                                Slot(false, false, kWhole, 2)};
  Check(Is(Page(both, kWhole), 1, true),
        "between fitting frames a free compositor wins over a hidden page's");
  const std::vector<PaneCompositorSlot> neither = {Slot(false, true, kLeft, 9),
                                                   Slot(false, false, kRight, 2)};
  Check(Is(Page(neither, kWhole), 1, false),
        "between cleared ones a free compositor wins over a hidden page's");
  const std::vector<PaneCompositorSlot> unplaced = {Slot(false, true, std::nullopt, 7),
                                                    Slot(false, true, std::nullopt, 8)};
  Check(Is(Page(unplaced, kWhole), 1, false),
        "without a last place nothing fits and the most recent is cleared");
  Check(Is(Page(unplaced, std::nullopt), 1, false),
        "a page with no window place still reuses one, cleared");
}

void FitRule() {
  const PaneCompositorSlot whole = Slot(false, true, kWhole, 1);
  Check(PaneHeldFrameFits(whole, PaneRole::kPage, kWhole), "identical places fit");
  Check(PaneHeldFrameFits(whole, PaneRole::kPage, PaneRect{0, 0, 1000, 720}),
        "90% of the held place fits");
  Check(!PaneHeldFrameFits(whole, PaneRole::kPage, PaneRect{0, 0, 1000, 719}),
        "less than 90% of the held place does not");
  Check(!PaneHeldFrameFits(Slot(false, true, PaneRect{0, 0, 1000, 719}, 1), PaneRole::kPage, kWhole),
        "a held place covering less than 90% of the request does not");
  Check(!PaneHeldFrameFits(whole, PaneRole::kDevTools, kWhole), "another role does not");
  Check(!PaneHeldFrameFits(whole, PaneRole::kPage, std::nullopt), "no request place does not");
  Check(!PaneHeldFrameFits(whole, PaneRole::kPage, PaneRect{0, 0, 0, 0}), "an empty place does not");
}

void SweepRetiresIdleCompositorsAtTheSecondSweep() {
  // Split closed: the right compositor holds a hidden page in a visible window.
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
  plan = PlanPaneCompositorSweep(slots, true, 0);
  Check(plan[1] == PaneCompositorSweep::kMark && plan[2] == PaneCompositorSweep::kRetire,
        "with no spare (window gone) every idle one goes");
  // A marked compositor that is on screen again is kept and its mark cleared
  // by the caller.
  slots[2].on_screen = true;
  plan = PlanPaneCompositorSweep(slots, true, 0);
  Check(plan[2] == PaneCompositorSweep::kKeep, "a compositor back on screen is kept");
}

void HiddenWindowsKeepTheirPages() {
  // A minimized window: every page is hidden but keeps its compositor, so the
  // restored window shows them at once. Free ones still go.
  std::vector<PaneCompositorSlot> slots = {Slot(false, true, kLeft, 5, true),
                                           Slot(false, true, kRight, 4, true),
                                           Slot(false, false, kWhole, 3, true),
                                           Slot(false, false, kWhole, 2, true)};
  const auto plan = PlanPaneCompositorSweep(slots, false, 1);
  Check(plan[0] == PaneCompositorSweep::kKeep && plan[1] == PaneCompositorSweep::kKeep,
        "hidden pages of a hidden window keep their compositors");
  Check(plan[2] == PaneCompositorSweep::kKeep, "the most recent free one is the spare");
  Check(plan[3] == PaneCompositorSweep::kRetire, "older free ones are retired");
  const auto visible = PlanPaneCompositorSweep(slots, true, 1);
  Check(visible[0] == PaneCompositorSweep::kKeep && visible[1] == PaneCompositorSweep::kRetire,
        "once the window is visible the hidden pages' compositors are idle too");
}

void Overlap() {
  Check(parc::PaneOverlapArea(kLeft, kRight) == 0, "touching panes do not overlap");
  Check(parc::PaneOverlapArea(kWhole, kLeft) == 500 * 800, "contained pane overlaps by its area");
  Check(parc::PaneOverlapArea(PaneRect{-10, -10, 20, 20}, PaneRect{0, 0, 20, 20}) == 100,
        "partial overlap");
}

}  // namespace

int main() {
  TabSwitchInOnePane();
  OnScreenIsNeverTaken();
  AnotherPanesFrameIsCleared();
  Preferences();
  FitRule();
  SweepRetiresIdleCompositorsAtTheSecondSweep();
  HiddenWindowsKeepTheirPages();
  Overlap();
  std::printf("PASS: %u pane compositor hand-off, held-frame and sweep checks\n", checks);
  return 0;
}
