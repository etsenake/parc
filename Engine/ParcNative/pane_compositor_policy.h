// Copyright 2026 Parc contributors.
// Which window pane compositor a page about to be shown takes, whether it may
// keep showing the frame it holds, and which idle ones a sweep retires. No
// AppKit or Chromium dependency, so the hand-off bookkeeping is checked by
// tests/PaneCompositorPolicy without a browser.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_PANE_COMPOSITOR_POLICY_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_PANE_COMPOSITOR_POLICY_H_

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <tuple>
#include <vector>

namespace parc {

// Window coordinates.
struct PaneRect {
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;
};

// What a compositor displays: a page, or a docked DevTools frontend beside
// one. A held frame is only ever shown again in the same role.
enum class PaneRole { kPage, kDevTools };

struct PaneCompositorSlot {
  // Its display view is in a window with no hidden ancestor: the page it
  // displays is on screen and no other page may take it.
  bool on_screen = false;
  // It displays a page, shown or hidden, rather than sitting free.
  bool attached = false;
  // It was idle at the previous sweep.
  bool marked = false;
  // The role of the page it last displayed.
  PaneRole role = PaneRole::kPage;
  // Where it was last on screen.
  std::optional<PaneRect> rect;
  // Larger is more recent: the last time its page was attached or hidden.
  uint64_t last_used = 0;
};

// The share of each place the other must cover for a held frame to be shown
// in the new one: the same pane, give or take a few points of chrome.
inline constexpr double kHeldFrameOverlap = 0.9;

inline double PaneOverlapArea(const PaneRect& a, const PaneRect& b) {
  const double width =
      std::min(a.x + a.width, b.x + b.width) - std::max(a.x, b.x);
  const double height =
      std::min(a.y + a.height, b.y + b.height) - std::max(a.y, b.y);
  return width > 0 && height > 0 ? width * height : 0;
}

// Whether a page in `role` at `request` may show the frame `slot` holds until
// its own arrives: the same role, and the two places cover at least
// kHeldFrameOverlap of each other. Otherwise the frame is another pane's (the
// other side of a split, a Peek card, the half a docked DevTools left) and is
// cleared first.
inline bool PaneHeldFrameFits(const PaneCompositorSlot& slot,
                              PaneRole role,
                              const std::optional<PaneRect>& request) {
  if (slot.role != role || !slot.rect || !request) {
    return false;
  }
  const double held = slot.rect->width * slot.rect->height;
  const double wanted = request->width * request->height;
  if (held <= 0 || wanted <= 0) {
    return false;
  }
  const double overlap = PaneOverlapArea(*slot.rect, *request);
  return overlap >= kHeldFrameOverlap * held &&
         overlap >= kHeldFrameOverlap * wanted;
}

struct PaneCompositorChoice {
  size_t index = 0;
  // False: clear the held frame before the page is placed.
  bool keeps_frame = false;
};

// The compositor a page about to be shown in `role` at `request` takes, or
// nullopt to create one. Any compositor off screen qualifies; reusing one
// spares building a compositor and its GPU surface. Prefers one whose held
// frame fits the page (the same pane's last frame), the largest overlap
// among those, then a free one over one holding a hidden page, then the most
// recently used.
inline std::optional<PaneCompositorChoice> ChoosePaneCompositor(
    const std::vector<PaneCompositorSlot>& slots,
    PaneRole role,
    const std::optional<PaneRect>& request) {
  std::optional<PaneCompositorChoice> best;
  std::tuple<bool, double, bool, uint64_t> best_key;
  for (size_t index = 0; index < slots.size(); ++index) {
    const PaneCompositorSlot& slot = slots[index];
    if (slot.on_screen) {
      continue;
    }
    const bool fits = PaneHeldFrameFits(slot, role, request);
    const double area = fits ? PaneOverlapArea(*slot.rect, *request) : 0;
    const auto key = std::make_tuple(fits, area, !slot.attached, slot.last_used);
    if (!best || key > best_key) {
      best = PaneCompositorChoice{index, fits};
      best_key = key;
    }
  }
  return best;
}

enum class PaneCompositorSweep { kKeep, kMark, kRetire };

// One decision per slot. Idle compositors are off screen and either free or,
// when `retire_hidden_pages`, holding a hidden page. The `spare` most
// recently used idle ones stay for the next switch; the rest are marked at
// their first idle sweep and retired at the next, so one that went idle just
// before a sweep survives the hand-off that follows. Without
// `retire_hidden_pages` (a minimized or hidden window) hidden pages keep
// their compositors, so the restored window shows them at once.
inline std::vector<PaneCompositorSweep> PlanPaneCompositorSweep(
    const std::vector<PaneCompositorSlot>& slots,
    bool retire_hidden_pages,
    size_t spare) {
  std::vector<PaneCompositorSweep> plan(slots.size(),
                                        PaneCompositorSweep::kKeep);
  std::vector<size_t> idle;
  for (size_t index = 0; index < slots.size(); ++index) {
    const PaneCompositorSlot& slot = slots[index];
    if (!slot.on_screen && (!slot.attached || retire_hidden_pages)) {
      idle.push_back(index);
    }
  }
  std::stable_sort(idle.begin(), idle.end(), [&](size_t a, size_t b) {
    return slots[a].last_used > slots[b].last_used;
  });
  for (size_t rank = spare; rank < idle.size(); ++rank) {
    plan[idle[rank]] = slots[idle[rank]].marked ? PaneCompositorSweep::kRetire
                                                : PaneCompositorSweep::kMark;
  }
  return plan;
}

}  // namespace parc

#endif  // CEF_LIBCEF_BROWSER_PARC_NATIVE_PANE_COMPOSITOR_POLICY_H_
