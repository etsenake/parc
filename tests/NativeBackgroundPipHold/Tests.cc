// Copyright 2026 Parc contributors.
#include "../Support/TestFailure.h"

#include <cmath>
#include <optional>
#include <vector>

#include "native_background_picture_in_picture_hold.h"

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
  gate.app_active = false;
  gate.page_shown = true;
  gate.window_visible = true;
  return gate;
}

bool Holds(const BackgroundPipHoldGate& gate,
           const BackgroundPipRect& page,
           const std::vector<BackgroundPipRect>& screens,
           const Covers& covers) {
  return parc::ShouldHoldBackgroundPip(BackgroundPipHoldPass::kResign, false,
                                       gate, page, screens, covers);
}

bool Recheck(bool held,
             const BackgroundPipHoldGate& gate,
             const BackgroundPipRect& page,
             const std::vector<BackgroundPipRect>& screens,
             const Covers& covers) {
  return parc::ShouldHoldBackgroundPip(BackgroundPipHoldPass::kRecheck, held,
                                       gate, page, screens, covers);
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
    gate.app_active = true;
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

  return 0;
}
