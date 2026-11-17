// Copyright 2026 Parc contributors.
#include "../Support/TestFailure.h"

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

namespace {

bool Near(double a, double b) {
  return std::fabs(a - b) < 1e-9;
}

bool SameRect(const BackgroundPipRect& a, const BackgroundPipRect& b) {
  return Near(a.left, b.left) && Near(a.top, b.top) && Near(a.right, b.right) &&
         Near(a.bottom, b.bottom);
}

BackgroundPipRect Quartz(double x, double y, double width, double height) {
  return parc::BackgroundPipRectFromQuartz(x, y, width, height);
}

BackgroundPipHoldGate Away() {
  BackgroundPipHoldGate gate;
  gate.focus_away = true;
  gate.page_shown = true;
  gate.window_visible = true;
  return gate;
}

bool Holds(const BackgroundPipHoldGate& gate,
           const BackgroundPipRect& page,
           const std::vector<BackgroundPipRect>& screens,
           const Covers& covers) {
  return parc::ShouldHoldBackgroundPip(BackgroundPipHoldPass::kFocusLost,
                                       false, gate, page, screens, covers);
}

bool Recheck(bool held,
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

bool InKeyChain(bool app_active, const FakeWindow* key, const FakeWindow* window) {
  return parc::BackgroundPipWindowInActiveKeyChain(
      app_active, key, window, [](const FakeWindow* candidate) {
        return candidate->sheet_parent ? candidate->sheet_parent
                                       : candidate->parent;
      });
}

BackgroundPipHoldGate GateFor(bool app_active,
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

bool WatchRuns(bool gate_open, const std::vector<WatchPage>& pages) {
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

Covers FromRecords(const std::vector<BackgroundPipWindowRecord>& records) {
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

bool DecisionPending(bool window_gate_open, const std::vector<HostPage>& pages) {
  return parc::BackgroundPipHoldDecisionPending(
      window_gate_open, pages,
      [](const HostPage& page) { return !page.decided && page.shown; },
      [](const HostPage& page) { return page.can_enter; });
}

}

int main() {
  const std::vector<BackgroundPipRect> laptop{Quartz(0, 0, 1440, 900)};

  {
    PARC_EXPECT(SameRect(parc::BackgroundPipRectFromCocoa(0, 800, 100, 100, 900),
                         Quartz(0, 0, 100, 100)));
    PARC_EXPECT(SameRect(parc::BackgroundPipRectFromCocoa(20, 0, 100, 50, 900),
                         Quartz(20, 850, 100, 50)));
    PARC_EXPECT(SameRect(parc::BackgroundPipRectFromCocoa(-200, 900, 1920, 1080, 900),
                         Quartz(-200, -1080, 1920, 1080)));
  }

  {
    PARC_EXPECT(Near(parc::BackgroundPipUnionArea({}), 0));
    PARC_EXPECT(Near(parc::BackgroundPipUnionArea({Quartz(0, 0, 0, 10)}), 0));
    PARC_EXPECT(Near(parc::BackgroundPipUnionArea(
                         {Quartz(0, 0, 10, 10), Quartz(20, 20, 10, 10)}),
                     200));
    PARC_EXPECT(Near(parc::BackgroundPipUnionArea(
                         {Quartz(0, 0, 10, 10), Quartz(0, 0, 10, 10)}),
                     100));
    PARC_EXPECT(Near(parc::BackgroundPipUnionArea(
                         {Quartz(0, 0, 10, 10), Quartz(2, 2, 3, 3)}),
                     100));
    PARC_EXPECT(Near(parc::BackgroundPipUnionArea(
                         {Quartz(0, 0, 10, 10), Quartz(5, 5, 10, 10)}),
                     175));
    PARC_EXPECT(Near(parc::BackgroundPipUnionArea(
                         {Quartz(0, 0, 30, 10), Quartz(10, -10, 10, 30),
                          Quartz(0, 0, 30, 10)}),
                     500));
  }

  {
    const auto page = Quartz(0, 25, 720, 875);
    const Covers other_app{{Quartz(720, 25, 720, 875)}};
    PARC_EXPECT(Holds(Away(), page, laptop, other_app));
    const Covers overlapping_app{{Quartz(360, 25, 1080, 875)}};
    PARC_EXPECT(Holds(Away(), page, laptop, overlapping_app));
    const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};
    PARC_EXPECT(!Holds(Away(), page, laptop, mostly_over));
  }

  {
    const auto page = Quartz(100, 100, 100, 100);
    PARC_EXPECT(Holds(Away(), page, laptop, Covers{{Quartz(150, 0, 500, 500)}}));
    PARC_EXPECT(!Holds(Away(), page, laptop, Covers{{Quartz(149, 0, 500, 500)}}));
    PARC_EXPECT(Near(parc::BackgroundPipVisibleArea(
                         page, laptop, Covers{{Quartz(149, 0, 500, 500)}}),
                     4900));
    PARC_EXPECT(Holds(Away(), page, laptop, Covers{{Quartz(100, 150, 100, 50)}}));
    PARC_EXPECT(!Holds(Away(), page, laptop, Covers{{Quartz(100, 149, 100, 51)}}));
  }

  {
    const double primary = 900;
    const std::vector<BackgroundPipRect> displays{
        parc::BackgroundPipRectFromCocoa(0, 0, 1440, 900, primary),
        parc::BackgroundPipRectFromCocoa(1440, -180, 1920, 1080, primary)};
    const auto spanning =
        parc::BackgroundPipRectFromCocoa(1000, 100, 1000, 700, primary);
    PARC_EXPECT(Near(parc::BackgroundPipVisibleArea(spanning, displays, Covers{{}}),
                     700000));
    PARC_EXPECT(Holds(Away(), spanning, displays, Covers{{}}));
    PARC_EXPECT(!Holds(Away(), spanning, laptop, Covers{{}}));
    const auto hanging_low =
        parc::BackgroundPipRectFromCocoa(1000, -300, 400, 400, primary);
    PARC_EXPECT(!Holds(Away(), hanging_low, displays, Covers{{}}));
    const auto across_seam =
        parc::BackgroundPipRectFromCocoa(1340, -100, 200, 200, primary);
    PARC_EXPECT(Near(parc::BackgroundPipVisibleArea(across_seam, displays, Covers{{}}),
                     30000));
    PARC_EXPECT(Holds(Away(), across_seam, displays, Covers{{}}));
    const std::vector<BackgroundPipRect> mirrored{
        Quartz(0, 0, 1440, 900), Quartz(0, 0, 1440, 900)};
    PARC_EXPECT(Near(parc::BackgroundPipVisibleArea(
                         Quartz(1340, 0, 200, 100), mirrored, Covers{{}}),
                     10000));
    const auto half_off = Quartz(1000, 0, 880, 900);
    const Covers off_screen_cover{{Quartz(1440, 0, 500, 900)}};
    PARC_EXPECT(Near(parc::BackgroundPipVisibleArea(half_off, laptop, off_screen_cover),
                     396000));
    PARC_EXPECT(Holds(Away(), half_off, laptop, off_screen_cover));
  }

  {
    const auto page = Quartz(0, 0, 100, 100);
    const Covers overlapping{{Quartz(0, 0, 30, 100), Quartz(10, 0, 30, 100)}};
    PARC_EXPECT(Near(parc::BackgroundPipVisibleArea(page, laptop, overlapping), 6000));
    PARC_EXPECT(Holds(Away(), page, laptop, overlapping));
    const Covers stacked{{Quartz(0, 0, 40, 100), Quartz(0, 0, 40, 100),
                          Quartz(20, 0, 20, 100)}};
    PARC_EXPECT(Holds(Away(), page, laptop, stacked));
    const Covers crossing{{Quartz(0, 0, 100, 40), Quartz(0, 0, 40, 100)}};
    PARC_EXPECT(Near(parc::BackgroundPipVisibleArea(page, laptop, crossing), 3600));
    PARC_EXPECT(!Holds(Away(), page, laptop, crossing));
  }

  {
    const auto page = Quartz(0, 25, 1440, 875);
    PARC_EXPECT(Holds(Away(), page, laptop, Covers{{}}));
    const Covers late_cover{{Quartz(0, 0, 1440, 900)}};
    PARC_EXPECT(!Recheck(true, Away(), page, laptop, late_cover));
    PARC_EXPECT(Recheck(true, Away(), page, laptop, Covers{{}}));
    PARC_EXPECT(!Recheck(false, Away(), page, laptop, Covers{{}}));
  }

  {
    const auto page = Quartz(0, 25, 720, 875);
    const Covers clear{{}};
    auto gate = Away();
    PARC_EXPECT(parc::BackgroundPipHoldGateOpen(gate));
    gate.focus_away = false;
    PARC_EXPECT(!Holds(gate, page, laptop, clear));
    PARC_EXPECT(!Recheck(true, gate, page, laptop, clear));
    gate = Away();
    gate.page_shown = false;
    PARC_EXPECT(!Holds(gate, page, laptop, clear));
    gate = Away();
    gate.window_visible = false;
    PARC_EXPECT(!Holds(gate, page, laptop, clear));
    PARC_EXPECT(!Recheck(true, gate, page, laptop, clear));
    gate = Away();
    gate.displays_asleep = true;
    PARC_EXPECT(!Holds(gate, page, laptop, clear));
    gate = Away();
    gate.screen_locked = true;
    PARC_EXPECT(!Holds(gate, page, laptop, clear));
    PARC_EXPECT(!Recheck(true, gate, page, laptop, clear));
    gate = Away();
    gate.picture_in_picture_open = true;
    PARC_EXPECT(!Holds(gate, page, laptop, clear));
    PARC_EXPECT(!Holds(BackgroundPipHoldGate{}, page, laptop, clear));
    PARC_EXPECT(!Holds(Away(), Quartz(0, 0, 0, 0), laptop, clear));
    PARC_EXPECT(!Holds(Away(), page, {}, clear));
  }

  {
    const std::optional<std::vector<BackgroundPipWindowRecord>> failed;
    PARC_EXPECT(!parc::BackgroundPipCoveringWindows(failed));
    const auto page = Quartz(0, 25, 1440, 875);
    const Covers fallback = parc::BackgroundPipCoveringWindows(failed);
    PARC_EXPECT(Holds(Away(), page, laptop, fallback));
    PARC_EXPECT(!Holds(Away(), Quartz(1000, 25, 1440, 875), laptop, fallback));
    auto hidden = Away();
    hidden.window_visible = false;
    PARC_EXPECT(!Holds(hidden, page, laptop, fallback));

    const std::vector<BackgroundPipWindowRecord> missing_bounds{
        {0, 1.0, std::nullopt}};
    PARC_EXPECT(!parc::BackgroundPipCoveringWindows(missing_bounds));
    const std::vector<BackgroundPipWindowRecord> missing_layer{
        {std::nullopt, 1.0, Quartz(0, 0, 10, 10)}};
    PARC_EXPECT(!parc::BackgroundPipCoveringWindows(missing_layer));

    const std::vector<BackgroundPipWindowRecord> records{
        {24, 1.0, Quartz(0, 0, 1440, 25)},
        {20, 1.0, Quartz(0, 820, 1440, 80)},
        {25, 1.0, std::nullopt},
        {0, 0.0, Quartz(0, 0, 1440, 900)},
        {0, std::nullopt, Quartz(720, 25, 720, 875)},
        {0, 0.5, Quartz(0, 25, 100, 100)}};
    const auto covers = parc::BackgroundPipCoveringWindows(records);
    PARC_EXPECT(covers && covers->size() == 2);
    PARC_EXPECT(SameRect((*covers)[0], Quartz(720, 25, 720, 875)));
    PARC_EXPECT(SameRect((*covers)[1], Quartz(0, 25, 100, 100)));
    PARC_EXPECT(Holds(Away(), Quartz(0, 25, 720, 875), laptop, covers));
    PARC_EXPECT(!Holds(Away(), Quartz(0, 25, 1440, 875), laptop,
                       Covers{{Quartz(0, 25, 1440, 875)}}));
  }

  {
    const FakeWindow first;
    const FakeWindow second;
    const FakeWindow sheet{&first, nullptr};
    const FakeWindow child{nullptr, &first};
    const FakeWindow grandchild{nullptr, &child};
    const FakeWindow sheet_on_child{&child, nullptr};
    const FakeWindow other_app_panel;
    PARC_EXPECT(InKeyChain(true, &first, &first));
    PARC_EXPECT(!InKeyChain(true, &second, &first));
    PARC_EXPECT(InKeyChain(true, &sheet, &first));
    PARC_EXPECT(InKeyChain(true, &child, &first));
    PARC_EXPECT(InKeyChain(true, &grandchild, &first));
    PARC_EXPECT(InKeyChain(true, &sheet_on_child, &first));
    PARC_EXPECT(!InKeyChain(true, &sheet, &second));
    PARC_EXPECT(!InKeyChain(true, &other_app_panel, &first));
    PARC_EXPECT(!InKeyChain(true, nullptr, &first));
    PARC_EXPECT(!InKeyChain(false, &first, &first));
    PARC_EXPECT(!InKeyChain(false, &sheet, &first));
    PARC_EXPECT(!InKeyChain(true, &first, nullptr));

    const auto page = Quartz(0, 25, 720, 875);
    const Covers beside{{Quartz(720, 25, 720, 875)}};
    PARC_EXPECT(Holds(GateFor(false, &first, &first), page, laptop, beside));
    PARC_EXPECT(Holds(GateFor(true, &second, &first), page, laptop, beside));
    PARC_EXPECT(Holds(GateFor(true, nullptr, &first), page, laptop, beside));
    PARC_EXPECT(!Holds(GateFor(true, &first, &first), page, laptop, beside));
    PARC_EXPECT(!Holds(GateFor(true, &sheet, &first), page, laptop, beside));
    PARC_EXPECT(!Holds(GateFor(true, &child, &first), page, laptop, beside));
    PARC_EXPECT(!Recheck(true, GateFor(true, &sheet, &first), page, laptop, beside));
    PARC_EXPECT(parc::BackgroundPipHoldGateOpen(GateFor(true, &second, &first)));
    PARC_EXPECT(!parc::BackgroundPipHoldGateOpen(GateFor(true, &grandchild, &first)));
  }

  {
    using parc::BackgroundPipFocusTransition;
    PARC_EXPECT(BackgroundPipFocusTransition(false, true) ==
                BackgroundPipFocusChange::kLost);
    PARC_EXPECT(BackgroundPipFocusTransition(true, false) ==
                BackgroundPipFocusChange::kRegained);
    PARC_EXPECT(BackgroundPipFocusTransition(false, false) ==
                BackgroundPipFocusChange::kNone);
    PARC_EXPECT(BackgroundPipFocusTransition(true, true) ==
                BackgroundPipFocusChange::kNone);

    const FakeWindow first;
    const FakeWindow second;
    const FakeWindow sheet{&first, nullptr};
    const bool key_here = !InKeyChain(true, &first, &first);
    const bool other_parc_window = !InKeyChain(true, &second, &first);
    const bool parc_resigned = !InKeyChain(false, nullptr, &first);
    const bool sheet_key = !InKeyChain(true, &sheet, &first);
    PARC_EXPECT(BackgroundPipFocusTransition(key_here, parc_resigned) ==
                BackgroundPipFocusChange::kLost);
    PARC_EXPECT(BackgroundPipFocusTransition(key_here, other_parc_window) ==
                BackgroundPipFocusChange::kLost);
    PARC_EXPECT(BackgroundPipFocusTransition(other_parc_window, parc_resigned) ==
                BackgroundPipFocusChange::kNone);
    PARC_EXPECT(BackgroundPipFocusTransition(parc_resigned, other_parc_window) ==
                BackgroundPipFocusChange::kNone);
    PARC_EXPECT(BackgroundPipFocusTransition(key_here, sheet_key) ==
                BackgroundPipFocusChange::kNone);
    PARC_EXPECT(BackgroundPipFocusTransition(other_parc_window, key_here) ==
                BackgroundPipFocusChange::kRegained);

    PARC_EXPECT(parc::BackgroundPipFocusAwayOccludes(true, false));
    PARC_EXPECT(!parc::BackgroundPipFocusAwayOccludes(true, true));
    PARC_EXPECT(!parc::BackgroundPipFocusAwayOccludes(false, false));
    PARC_EXPECT(!parc::BackgroundPipFocusAwayOccludes(false, true));
  }

  {
    PARC_EXPECT(parc::kBackgroundPipHoldWatchIntervalMs == 500);
    PARC_EXPECT(parc::kBackgroundPipHoldReleaseAfterMs == 1000);
    const int64_t tick = parc::kBackgroundPipHoldWatchIntervalMs;
    const auto page = Quartz(0, 25, 720, 875);
    const Covers clear{{}};
    const Covers full{{Quartz(0, 0, 1440, 900)}};

    Watch watch;
    PARC_EXPECT(watch.Keep(Away(), page, laptop, clear, 0));
    PARC_EXPECT(!watch.below_half_since);
    PARC_EXPECT(watch.Keep(Away(), page, laptop, full, tick));
    PARC_EXPECT(watch.below_half_since && *watch.below_half_since == tick);
    PARC_EXPECT(watch.Keep(Away(), page, laptop, full, 2 * tick));
    PARC_EXPECT(!watch.Keep(Away(), page, laptop, full, 3 * tick));
    PARC_EXPECT(!watch.below_half_since);

    Watch exact;
    PARC_EXPECT(exact.Keep(Away(), page, laptop, full, 10000));
    PARC_EXPECT(exact.Keep(Away(), page, laptop, full, 10999));
    PARC_EXPECT(!exact.Keep(Away(), page, laptop, full, 11000));

    Watch reset;
    PARC_EXPECT(reset.Keep(Away(), page, laptop, full, 0));
    PARC_EXPECT(reset.Keep(Away(), page, laptop, full, tick));
    PARC_EXPECT(reset.Keep(Away(), page, laptop, clear, 2 * tick));
    PARC_EXPECT(!reset.below_half_since);
    PARC_EXPECT(reset.Keep(Away(), page, laptop, full, 3 * tick));
    PARC_EXPECT(reset.Keep(Away(), page, laptop, full, 4 * tick));
    PARC_EXPECT(!reset.Keep(Away(), page, laptop, full, 5 * tick));

    Watch at_half;
    const Covers half_over{{Quartz(360, 25, 1080, 875)}};
    PARC_EXPECT(at_half.Keep(Away(), page, laptop, full, 0));
    PARC_EXPECT(at_half.Keep(Away(), page, laptop, half_over, tick));
    PARC_EXPECT(!at_half.below_half_since);
    for (int64_t reading = 2; reading < 20; ++reading) {
      PARC_EXPECT(at_half.Keep(Away(), page, laptop, half_over, reading * tick));
    }

    int readings = 0;
    Watch cadence;
    int64_t now = 0;
    while (cadence.Keep(Away(), page, laptop, full, now)) {
      ++readings;
      now += tick;
    }
    PARC_EXPECT(readings == 2);
    PARC_EXPECT(now == parc::kBackgroundPipHoldReleaseAfterMs);
  }

  {
    PARC_EXPECT(!WatchRuns(true, {}));
    PARC_EXPECT(!WatchRuns(true, {{false, false}, {false, true}}));
    PARC_EXPECT(!WatchRuns(true, {{true, false}, {true, false}}));
    PARC_EXPECT(!WatchRuns(true, {{true, false}, {false, true}}));
    PARC_EXPECT(WatchRuns(true, {{true, false}, {true, true}}));
    PARC_EXPECT(!WatchRuns(false, {{true, true}}));
    int asked = 0;
    const std::vector<WatchPage> pages{{false, true}, {false, true}};
    PARC_EXPECT(!parc::BackgroundPipHoldWatchRuns(
        true, pages, [](const WatchPage& page) { return page.held; },
        [&](const WatchPage&) {
          ++asked;
          return true;
        }));
    PARC_EXPECT(asked == 0);
  }

  {
    const auto page = Quartz(0, 25, 720, 875);
    const Covers beside{{Quartz(720, 25, 720, 875)}};
    PARC_EXPECT(Holds(Away(), page, laptop, beside));
    const auto grown = FromRecords({{0, 1.0, Quartz(0, 0, 1440, 900)}});
    auto gate = Away();
    PARC_EXPECT(gate.window_visible);
    Watch watch;
    PARC_EXPECT(watch.Keep(gate, page, laptop, grown, 0));
    PARC_EXPECT(watch.Keep(gate, page, laptop, grown, 500));
    PARC_EXPECT(!watch.Keep(gate, page, laptop, grown, 1000));
    const auto translucent_grown =
        FromRecords({{0, 0.9, Quartz(0, 0, 1440, 900)}});
    Watch translucent;
    PARC_EXPECT(translucent.Keep(gate, page, laptop, translucent_grown, 0));
    PARC_EXPECT(!translucent.Keep(gate, page, laptop, translucent_grown, 1000));
    const auto floating_pip = FromRecords({{3, 1.0, Quartz(0, 25, 720, 875)}});
    Watch floating;
    for (int64_t now = 0; now <= 3000; now += 500) {
      PARC_EXPECT(floating.Keep(gate, page, laptop, floating_pip, now));
    }
    gate.window_visible = false;
    Watch hidden;
    PARC_EXPECT(!hidden.Keep(gate, page, laptop, Covers{{}}, 0));
  }

  {
    const FakeWindow first;
    const FakeWindow second;
    const auto page = Quartz(0, 25, 1440, 875);
    const auto gate = GateFor(true, &second, &first);
    const auto full_parc = FromRecords({{0, 1.0, Quartz(0, 0, 1440, 900)}});
    const auto half_parc = FromRecords({{0, 1.0, Quartz(720, 0, 720, 900)}});
    const auto most_parc = FromRecords({{0, 1.0, Quartz(719, 0, 721, 900)}});
    PARC_EXPECT(!Holds(gate, page, laptop, full_parc));
    PARC_EXPECT(Holds(gate, page, laptop, half_parc));
    PARC_EXPECT(!Holds(gate, page, laptop, most_parc));
    PARC_EXPECT(!Recheck(true, gate, page, laptop, full_parc));
    PARC_EXPECT(Recheck(true, gate, page, laptop, half_parc));
    Watch half;
    for (int64_t now = 0; now <= 5000; now += 500) {
      PARC_EXPECT(half.Keep(gate, page, laptop, half_parc, now));
    }
    Watch full;
    PARC_EXPECT(full.Keep(gate, page, laptop, half_parc, 0));
    PARC_EXPECT(full.Keep(gate, page, laptop, full_parc, 500));
    PARC_EXPECT(full.Keep(gate, page, laptop, full_parc, 1000));
    PARC_EXPECT(!full.Keep(gate, page, laptop, full_parc, 1500));
  }

  {
    const auto page = Quartz(0, 25, 720, 875);
    const Covers clear{{}};
    PARC_EXPECT(Holds(Away(), page, laptop, clear));
    Watch away;
    for (int64_t now = 0; now <= 5000; now += 500) {
      PARC_EXPECT(away.Keep(Away(), page, laptop, clear, now));
    }
    auto gate = Away();
    gate.picture_in_picture_open = true;
    PARC_EXPECT(!Holds(gate, page, laptop, clear));
    Watch open;
    PARC_EXPECT(!open.Keep(gate, page, laptop, clear, 0));
    gate = Away();
    gate.screen_locked = true;
    PARC_EXPECT(!Holds(gate, page, laptop, clear));
    Watch locked;
    PARC_EXPECT(!locked.Keep(gate, page, laptop, clear, 0));
    gate = Away();
    gate.displays_asleep = true;
    PARC_EXPECT(!Holds(gate, page, laptop, clear));
    Watch asleep;
    PARC_EXPECT(!asleep.Keep(gate, page, laptop, clear, 0));
    gate = Away();
    gate.page_shown = false;
    Watch hidden;
    PARC_EXPECT(!hidden.Keep(gate, page, laptop, clear, 0));
    Watch collapsed;
    PARC_EXPECT(collapsed.Keep(Away(), Quartz(0, 25, 0, 0), laptop, clear, 0));
    PARC_EXPECT(!collapsed.Keep(Away(), Quartz(0, 25, 0, 0), laptop, clear, 1000));
    Watch no_display;
    PARC_EXPECT(no_display.Keep(Away(), page, {}, clear, 0));
    PARC_EXPECT(!no_display.Keep(Away(), page, {}, clear, 1000));
    gate = Away();
    gate.focus_away = false;
    Watch back;
    back.below_half_since = 0;
    PARC_EXPECT(!back.Keep(gate, page, laptop, clear, 500));
    PARC_EXPECT(!back.below_half_since);
  }

  {
    PARC_EXPECT(parc::kBackgroundPipHoldRecheckDelayMs == 250);
    PARC_EXPECT(parc::BackgroundPipPageKept(true, true, false));
    PARC_EXPECT(parc::BackgroundPipPageKept(true, true, true));
    PARC_EXPECT(parc::BackgroundPipPageKept(false, false, true));
    PARC_EXPECT(!parc::BackgroundPipPageKept(false, false, false));
    PARC_EXPECT(!parc::BackgroundPipPageKept(false, true, true));
    PARC_EXPECT(parc::BackgroundPipHoldDecided(BackgroundPipHoldPass::kFocusLost,
                                               false, true));
    PARC_EXPECT(!parc::BackgroundPipHoldDecided(BackgroundPipHoldPass::kFocusLost,
                                                true, false));
    PARC_EXPECT(parc::BackgroundPipHoldDecided(
        BackgroundPipHoldPass::kBecameEligible, false, true));
    PARC_EXPECT(!parc::BackgroundPipHoldDecided(
        BackgroundPipHoldPass::kBecameEligible, false, false));
    PARC_EXPECT(parc::BackgroundPipHoldDecided(BackgroundPipHoldPass::kRecheck,
                                               true, false));
    PARC_EXPECT(!parc::BackgroundPipHoldDecided(BackgroundPipHoldPass::kRecheck,
                                                false, true));
    const auto yes = [] { return true; };
    const auto no = [] { return false; };
    PARC_EXPECT(parc::BackgroundPipHoldPassMeasures(
        BackgroundPipHoldPass::kFocusLost, false, false, true, no));
    PARC_EXPECT(parc::BackgroundPipHoldPassMeasures(
        BackgroundPipHoldPass::kFocusLost, true, true, true, no));
    PARC_EXPECT(parc::BackgroundPipHoldPassMeasures(
        BackgroundPipHoldPass::kRecheck, true, false, true, no));
    PARC_EXPECT(!parc::BackgroundPipHoldPassMeasures(
        BackgroundPipHoldPass::kRecheck, true, true, true, yes));
    PARC_EXPECT(!parc::BackgroundPipHoldPassMeasures(
        BackgroundPipHoldPass::kRecheck, false, false, false, yes));
    PARC_EXPECT(parc::BackgroundPipHoldPassMeasures(
        BackgroundPipHoldPass::kBecameEligible, false, false, false, yes));
    PARC_EXPECT(!parc::BackgroundPipHoldPassMeasures(
        BackgroundPipHoldPass::kBecameEligible, false, false, false, no));
    PARC_EXPECT(!parc::BackgroundPipHoldPassMeasures(
        BackgroundPipHoldPass::kBecameEligible, false, false, true, yes));
    PARC_EXPECT(!parc::BackgroundPipHoldPassMeasures(
        BackgroundPipHoldPass::kBecameEligible, true, false, true, yes));
  }

  {
    const FakeWindow first;
    const FakeWindow second;
    const bool away_at_attach = !InKeyChain(true, &second, &first);
    PARC_EXPECT(away_at_attach);
    PARC_EXPECT(parc::BackgroundPipFocusTransition(
                    away_at_attach, !InKeyChain(true, &second, &first)) ==
                BackgroundPipFocusChange::kNone);
    PARC_EXPECT(parc::BackgroundPipFocusTransition(
                    away_at_attach, !InKeyChain(false, nullptr, &first)) ==
                BackgroundPipFocusChange::kNone);
    PARC_EXPECT(parc::BackgroundPipFocusTransition(
                    !InKeyChain(false, nullptr, &first),
                    !InKeyChain(true, nullptr, &first)) ==
                BackgroundPipFocusChange::kNone);

    const auto gate = GateFor(true, &second, &first);
    const auto page = Quartz(0, 25, 1440, 875);
    const Covers clear{{}};
    HostPage video;
    PARC_EXPECT(!video.Occluded(gate));
    PARC_EXPECT(!DecisionPending(true, {video}));
    video.can_enter = true;
    PARC_EXPECT(!video.Occluded(gate));
    PARC_EXPECT(DecisionPending(true, {video}));
    PARC_EXPECT(!DecisionPending(false, {video}));
    video.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop, clear);
    PARC_EXPECT(video.held && video.decided);
    PARC_EXPECT(!video.Occluded(gate));
    PARC_EXPECT(!DecisionPending(true, {video}));
    PARC_EXPECT(WatchRuns(true, {{video.held, video.can_enter}}));
    video.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop, clear);
    PARC_EXPECT(video.held && !video.Occluded(gate));
    Watch watch;
    for (int64_t now = 0; now <= 5000; now += 500) {
      PARC_EXPECT(watch.Keep(gate, page, laptop, clear, now));
    }
    PARC_EXPECT(!video.Occluded(GateFor(false, nullptr, &first)));
    PARC_EXPECT(!video.Occluded(GateFor(true, &first, &first)));
  }

  {
    const FakeWindow first;
    const FakeWindow second;
    const auto gate = GateFor(true, &second, &first);
    const auto page = Quartz(0, 25, 720, 875);
    const Covers beside{{Quartz(720, 25, 720, 875)}};
    const Covers just_over_half{{Quartz(396, 25, 1044, 875)}};
    const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};

    HostPage half;
    half.can_enter = true;
    half.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
              just_over_half);
    PARC_EXPECT(half.held && half.decided && !half.Occluded(gate));
    HostPage clear_side;
    clear_side.can_enter = true;
    clear_side.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
                    beside);
    PARC_EXPECT(clear_side.held && !clear_side.Occluded(gate));

    HostPage under;
    under.can_enter = true;
    PARC_EXPECT(!under.Occluded(gate));
    under.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
               mostly_over);
    PARC_EXPECT(!under.held && under.decided);
    PARC_EXPECT(under.Occluded(gate));
    PARC_EXPECT(!DecisionPending(true, {under}));
    under.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
               beside);
    PARC_EXPECT(!under.held && under.Occluded(gate));
    PARC_EXPECT(under.eligibility_reads == 1);

    HostPage late;
    late.can_enter = true;
    late.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
              beside);
    PARC_EXPECT(late.held);
    late.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop, mostly_over);
    PARC_EXPECT(!late.held && late.decided && late.Occluded(gate));

    HostPage watched;
    watched.can_enter = true;
    watched.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
                 beside);
    Watch grace;
    PARC_EXPECT(grace.Keep(gate, page, laptop, mostly_over, 0));
    watched.releasing = grace.below_half_since.has_value();
    PARC_EXPECT(watched.releasing);
    HostPage newcomer;
    newcomer.can_enter = true;
    newcomer.Pass(BackgroundPipHoldPass::kBecameEligible, gate, page, laptop,
                  beside);
    PARC_EXPECT(newcomer.held);
    watched.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop,
                 mostly_over);
    newcomer.Pass(BackgroundPipHoldPass::kRecheck, gate, page, laptop,
                  mostly_over);
    PARC_EXPECT(watched.held && !watched.Occluded(gate));
    PARC_EXPECT(!newcomer.held && newcomer.Occluded(gate));
    PARC_EXPECT(grace.Keep(gate, page, laptop, mostly_over, 500));
    PARC_EXPECT(!grace.Keep(gate, page, laptop, mostly_over, 1000));
  }

  {
    const auto page = Quartz(0, 25, 720, 875);
    const Covers beside{{Quartz(720, 25, 720, 875)}};
    const Covers mostly_over{{Quartz(359, 25, 1081, 875)}};

    HostPage measured_paused;
    measured_paused.Pass(BackgroundPipHoldPass::kFocusLost, Away(), page,
                         laptop, mostly_over);
    PARC_EXPECT(measured_paused.decided && !measured_paused.held);
    PARC_EXPECT(measured_paused.eligibility_reads == 0);
    measured_paused.can_enter = true;
    PARC_EXPECT(!DecisionPending(true, {measured_paused}));
    measured_paused.Pass(BackgroundPipHoldPass::kBecameEligible, Away(), page,
                         laptop, beside);
    PARC_EXPECT(measured_paused.Occluded(Away()));

    HostPage background_tab;
    background_tab.shown = false;
    background_tab.Pass(BackgroundPipHoldPass::kFocusLost, Away(), page, laptop,
                        beside);
    PARC_EXPECT(!background_tab.decided && !background_tab.held);
    background_tab.can_enter = true;
    PARC_EXPECT(!DecisionPending(true, {background_tab}));
    background_tab.shown = true;
    PARC_EXPECT(!background_tab.Occluded(Away()));
    PARC_EXPECT(DecisionPending(true, {background_tab}));
    background_tab.Pass(BackgroundPipHoldPass::kBecameEligible, Away(), page,
                        laptop, beside);
    PARC_EXPECT(background_tab.held && !background_tab.Occluded(Away()));

    HostPage covered;
    covered.can_enter = true;
    auto hidden = Away();
    hidden.window_visible = false;
    PARC_EXPECT(covered.Occluded(hidden));
    covered.Pass(BackgroundPipHoldPass::kBecameEligible, hidden, page, laptop,
                 beside);
    PARC_EXPECT(!covered.decided && !covered.held);
    PARC_EXPECT(covered.Occluded(hidden));
    PARC_EXPECT(!covered.Occluded(Away()));
    PARC_EXPECT(DecisionPending(true, {covered}));
    covered.Pass(BackgroundPipHoldPass::kBecameEligible, Away(), page, laptop,
                 mostly_over);
    PARC_EXPECT(covered.decided && covered.Occluded(Away()));

    for (const auto closed : {&BackgroundPipHoldGate::displays_asleep,
                              &BackgroundPipHoldGate::screen_locked}) {
      auto gate = Away();
      gate.*closed = true;
      HostPage unmeasured;
      unmeasured.can_enter = true;
      PARC_EXPECT(unmeasured.Occluded(gate));
      unmeasured.Pass(BackgroundPipHoldPass::kFocusLost, gate, page, laptop,
                      beside);
      PARC_EXPECT(!unmeasured.decided && unmeasured.Occluded(gate));
    }

    HostPage untouched;
    untouched.can_enter = true;
    untouched.Pass(BackgroundPipHoldPass::kRecheck, Away(), page, laptop,
                   mostly_over);
    PARC_EXPECT(!untouched.decided && !untouched.Occluded(Away()));

    HostPage already_open;
    already_open.can_enter = true;
    already_open.picture_in_picture_open = true;
    PARC_EXPECT(already_open.Occluded(Away()));
    already_open.Pass(BackgroundPipHoldPass::kBecameEligible, Away(), page,
                      laptop, beside);
    PARC_EXPECT(already_open.decided && !already_open.held);
    already_open.picture_in_picture_open = false;
    PARC_EXPECT(already_open.Occluded(Away()));

    HostPage key_again = measured_paused;
    key_again.decided = false;
    auto back = Away();
    back.focus_away = false;
    PARC_EXPECT(!key_again.Occluded(back));
    key_again.Pass(BackgroundPipHoldPass::kFocusLost, Away(), page, laptop,
                   beside);
    PARC_EXPECT(key_again.held && key_again.decided);
  }

  {
    HostPage paused;
    HostPage decided;
    decided.decided = true;
    decided.can_enter = true;
    HostPage playing;
    playing.can_enter = true;
    PARC_EXPECT(!DecisionPending(true, {paused, decided}));
    PARC_EXPECT(DecisionPending(true, {paused, decided, playing}));
    playing.shown = false;
    PARC_EXPECT(!DecisionPending(true, {paused, decided, playing}));
  }

  return 0;
}
