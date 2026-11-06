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

// Points.
struct PaneSize {
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
  // Where its display view was last on screen. Ranks candidates only: a
  // page's place can be stale when it is taken, as its view may be parked
  // or not yet laid out, so no place is ever trusted to decide the frame.
  std::optional<PaneRect> rect;
  // The size its frame is drawn at: its root layer's bounds, in points.
  std::optional<PaneSize> size;
  // Larger is more recent: the last time its page was attached or hidden.
  uint64_t last_used = 0;
};

// The share of each size the other must cover for a held frame to be shown
// in the new one: the same pane, give or take a few points of chrome.
inline constexpr double kHeldFrameOverlap = 0.9;

inline double PaneOverlapArea(const PaneRect& a, const PaneRect& b) {
  const double width =
      std::min(a.x + a.width, b.x + b.width) - std::max(a.x, b.x);
  const double height =
      std::min(a.y + a.height, b.y + b.height) - std::max(a.y, b.y);
  return width > 0 && height > 0 ? width * height : 0;
}

// Whether a page in `role` of `request` size may show the frame `slot` holds
// until its own arrives: the same role, and the held frame's size and the
// page's covering at least kHeldFrameOverlap of each other, so a top bar
// coming or going still counts. A frame of another size is another pane's
// (the other side of a split, a Peek card, the half a docked DevTools left)
// and is cleared first. Sizes decide, not places: the frame is drawn at the
// size the compositor's layer has now, while the places recorded for a page
// leaving the screen and one about to be shown can differ for the same pane
// (the shell parks pages, and lays the incoming one out after the hand-off),
// and clearing on that difference emptied the pane on ordinary tab switches.
inline bool PaneHeldFrameFits(const PaneCompositorSlot& slot,
                              PaneRole role,
                              const std::optional<PaneSize>& request) {
  if (slot.role != role || !slot.size || !request) {
    return false;
  }
  const double held = slot.size->width * slot.size->height;
  const double wanted = request->width * request->height;
  if (held <= 0 || wanted <= 0) {
    return false;
  }
  const double shared = std::min(slot.size->width, request->width) *
                        std::min(slot.size->height, request->height);
  return shared >= kHeldFrameOverlap * held &&
         shared >= kHeldFrameOverlap * wanted;
}

struct PaneCompositorChoice {
  size_t index = 0;
  // False: clear the held frame before the page is placed.
  bool keeps_frame = false;
};

// The compositor a page about to be shown in `role`, of `request_size` and
// at `request` when known, takes, or nullopt to create one. Any compositor
// off screen qualifies; reusing one spares building a compositor and its GPU
// surface. Prefers one whose held frame fits the page, the one last on
// screen overlapping the page most among those (each side of a split keeps
// its own side), then a free one over one holding a hidden page, then the
// most recently used.
inline std::optional<PaneCompositorChoice> ChoosePaneCompositor(
    const std::vector<PaneCompositorSlot>& slots,
    PaneRole role,
    const std::optional<PaneRect>& request,
    const std::optional<PaneSize>& request_size) {
  std::optional<PaneCompositorChoice> best;
  std::tuple<bool, double, bool, uint64_t> best_key;
  for (size_t index = 0; index < slots.size(); ++index) {
    const PaneCompositorSlot& slot = slots[index];
    if (slot.on_screen) {
      continue;
    }
    const bool fits = PaneHeldFrameFits(slot, role, request_size);
    const double area = fits && slot.rect && request
                            ? PaneOverlapArea(*slot.rect, *request)
                            : 0;
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
