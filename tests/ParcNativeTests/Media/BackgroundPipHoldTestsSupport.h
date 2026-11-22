#pragma once

#import "ParcNativeTest.h"

#include <cmath>
#include <cstdint>
#include <optional>
#include <vector>

#include "native_background_picture_in_picture_hold.h"

using parc::BackgroundPipFocusChange;
using parc::BackgroundPipHoldGate;
using parc::BackgroundPipHoldPass;
using parc::BackgroundPipRect;
using parc::BackgroundPipWindowRecord;
using Covers = std::optional<std::vector<BackgroundPipRect>>;

namespace BackgroundPipHoldTestsSupport {

inline bool Near(double a, double b) {
  return std::fabs(a - b) < 1e-9;
}

inline bool SameRect(const BackgroundPipRect& a, const BackgroundPipRect& b) {
  return Near(a.left, b.left) && Near(a.top, b.top) && Near(a.right, b.right) &&
         Near(a.bottom, b.bottom);
}

inline BackgroundPipRect Quartz(double x, double y, double width, double height) {
  return parc::BackgroundPipRectFromQuartz(x, y, width, height);
}

inline BackgroundPipHoldGate Away() {
  BackgroundPipHoldGate gate;
  gate.focus_away = true;
  gate.page_shown = true;
  gate.window_visible = true;
  return gate;
}

inline bool Holds(const BackgroundPipHoldGate& gate,
           const BackgroundPipRect& page,
           const std::vector<BackgroundPipRect>& screens,
           const Covers& covers) {
  return parc::ShouldHoldBackgroundPip(BackgroundPipHoldPass::kFocusLost,
                                       false, gate, page, screens, covers);
}

inline bool Recheck(bool held,
             const BackgroundPipHoldGate& gate,
             const BackgroundPipRect& page,
             const std::vector<BackgroundPipRect>& screens,
             const Covers& covers) {
  return parc::ShouldHoldBackgroundPip(BackgroundPipHoldPass::kRecheck, held,
                                       gate, page, screens, covers);
}

struct FakeWindow {
  const FakeWindow* sheet_parent = nullptr;
  const FakeWindow* parent = nullptr;
};

inline bool InKeyChain(bool app_active, const FakeWindow* key, const FakeWindow* window) {
  return parc::BackgroundPipWindowInActiveKeyChain(
      app_active, key, window, [](const FakeWindow* candidate) {
        return candidate->sheet_parent ? candidate->sheet_parent
                                       : candidate->parent;
      });
}

inline BackgroundPipHoldGate GateFor(bool app_active,
                              const FakeWindow* key,
                              const FakeWindow* window) {
  auto gate = Away();
  gate.focus_away = !InKeyChain(app_active, key, window);
  return gate;
}

struct WatchPage {
  bool held = false;
  bool can_enter = false;
};

inline bool WatchRuns(bool gate_open, const std::vector<WatchPage>& pages) {
  return parc::BackgroundPipHoldWatchRuns(
      gate_open, pages, [](const WatchPage& page) { return page.held; },
      [](const WatchPage& page) { return page.can_enter; });
}

struct Watch {
  std::optional<int64_t> below_half_since;
  bool Keep(const BackgroundPipHoldGate& gate,
            const BackgroundPipRect& page,
            const std::vector<BackgroundPipRect>& screens,
            const Covers& covers,
            int64_t now_ms) {
    return parc::KeepBackgroundPipHold(below_half_since, gate, page, screens,
                                       covers, now_ms);
  }
};

inline Covers FromRecords(const std::vector<BackgroundPipWindowRecord>& records) {
  return parc::BackgroundPipCoveringWindows(records);
}

struct HostPage {
  bool held = false;
  bool decided = false;
  bool shown = true;
  bool can_enter = false;
  bool picture_in_picture_open = false;
  bool releasing = false;
  int eligibility_reads = 0;

  BackgroundPipHoldGate PageGate(BackgroundPipHoldGate window) const {
    window.page_shown = window.page_shown && shown;
    window.picture_in_picture_open =
        window.picture_in_picture_open || picture_in_picture_open;
    return window;
  }
  void Pass(BackgroundPipHoldPass pass,
            const BackgroundPipHoldGate& window,
            const BackgroundPipRect& page,
            const std::vector<BackgroundPipRect>& screens,
            const Covers& covers) {
    const auto can_enter_now = [this] {
      ++eligibility_reads;
      return can_enter;
    };
    if (!parc::BackgroundPipHoldPassMeasures(pass, held, releasing, decided,
                                             can_enter_now)) {
      return;
    }
    const bool window_gate_open = window.focus_away && window.window_visible &&
                                  !window.displays_asleep &&
                                  !window.screen_locked;
    const bool measured = window_gate_open && shown;
    held = measured && parc::ShouldHoldBackgroundPip(pass, held, PageGate(window),
                                                     page, screens, covers);
    decided = parc::BackgroundPipHoldDecided(pass, decided, measured);
  }
  bool Occluded(const BackgroundPipHoldGate& window) const {
    return parc::BackgroundPipFocusAwayOccludes(
        window.focus_away,
        parc::BackgroundPipPageKept(
            held, decided, parc::BackgroundPipHoldGateOpen(PageGate(window))));
  }
};

inline bool DecisionPending(bool window_gate_open, const std::vector<HostPage>& pages) {
  return parc::BackgroundPipHoldDecisionPending(
      window_gate_open, pages,
      [](const HostPage& page) { return !page.decided && page.shown; },
      [](const HostPage& page) { return page.can_enter; });
}

static const std::vector<BackgroundPipRect> laptop{Quartz(0, 0, 1440, 900)};

}
