#include <algorithm>
#include <cmath>
#include <cstdio>
#include <initializer_list>

#include "../Support/TestFailure.h"
#import "extension_popup_presenter.h"

static int assertions = 0;
#define EXPECT(x)        \
  do {                   \
    ++assertions;        \
    PARC_EXPECT(x);      \
  } while (0)

static bool Near(double a, double b) {
  return std::abs(a - b) < .001;
}

static void OpeningMotion() {
  PCExtensionPopupMotionFrame start = PCExtensionPopupOpeningMotion(0, NO);
  EXPECT(Near(start.alpha, 0) && Near(start.lift, 8) && !start.finished);
  PCExtensionPopupMotionFrame middle = PCExtensionPopupOpeningMotion(.1, NO);
  EXPECT(middle.alpha > .5 && middle.alpha < 1);
  EXPECT(middle.lift > 0 && middle.lift < 4 && !middle.finished);
  PCExtensionPopupMotionFrame end = PCExtensionPopupOpeningMotion(.2, NO);
  EXPECT(Near(end.alpha, 1) && Near(end.lift, 0) && end.finished);
  EXPECT(!PCExtensionPopupOpeningMotion(.19, NO).finished);
  PCExtensionPopupMotionFrame late = PCExtensionPopupOpeningMotion(5, NO);
  EXPECT(Near(late.alpha, 1) && Near(late.lift, 0) && late.finished);
  PCExtensionPopupMotionFrame broken = PCExtensionPopupOpeningMotion(NAN, NO);
  EXPECT(Near(broken.alpha, 1) && broken.finished);
  double alpha = -1, lift = 9;
  for (int step = 0; step <= 24; ++step) {
    PCExtensionPopupMotionFrame frame =
        PCExtensionPopupOpeningMotion(step / 120.0, NO);
    EXPECT(frame.alpha >= alpha && frame.lift <= lift);
    alpha = frame.alpha;
    lift = frame.lift;
  }
  for (double elapsed : {0.0, .05, .1, .2}) {
    PCExtensionPopupMotionFrame still =
        PCExtensionPopupOpeningMotion(elapsed, YES);
    EXPECT(Near(still.lift, 0));
    EXPECT(Near(still.alpha, PCExtensionPopupOpeningMotion(elapsed, NO).alpha));
  }
}

static void ClosingMotion() {
  PCExtensionPopupMotionFrame start =
      PCExtensionPopupClosingMotion(0, 1, 0, NO);
  EXPECT(Near(start.alpha, 1) && Near(start.lift, 0) && !start.finished);
  PCExtensionPopupMotionFrame end =
      PCExtensionPopupClosingMotion(.15, 1, 0, NO);
  EXPECT(Near(end.alpha, 0) && Near(end.lift, 4) && end.finished);
  EXPECT(!PCExtensionPopupClosingMotion(.14, 1, 0, NO).finished);
  EXPECT(PCExtensionPopupClosingMotion(.075, 1, 0, NO).alpha < .5);
  PCExtensionPopupMotionFrame interrupted =
      PCExtensionPopupClosingMotion(0, .4, 6, NO);
  EXPECT(Near(interrupted.alpha, .4) && Near(interrupted.lift, 6));
  EXPECT(Near(PCExtensionPopupClosingMotion(.15, .4, 6, NO).lift, 4));
  EXPECT(PCExtensionPopupClosingMotion(NAN, 1, 0, NO).finished);
  double alpha = 2;
  for (int step = 0; step <= 18; ++step) {
    PCExtensionPopupMotionFrame frame =
        PCExtensionPopupClosingMotion(step / 120.0, 1, 0, NO);
    EXPECT(frame.alpha <= alpha && frame.lift >= 0 && frame.lift <= 4);
    alpha = frame.alpha;
  }
  for (double elapsed : {0.0, .05, .15}) {
    PCExtensionPopupMotionFrame still =
        PCExtensionPopupClosingMotion(elapsed, 1, 0, YES);
    EXPECT(Near(still.lift, 0));
    EXPECT(Near(still.alpha,
                PCExtensionPopupClosingMotion(elapsed, 1, 0, NO).alpha));
  }
  EXPECT(Near(PCExtensionPopupClosingMotion(0, 3, 0, NO).alpha, 1));
}

static void RevealTiming() {
  const double shown = 100;
  EXPECT(Near(PCExtensionPopupRevealTime(shown, NAN, NAN), shown + .15));
  EXPECT(Near(PCExtensionPopupRevealTime(shown, NAN, shown + .01),
              shown + .15));
  EXPECT(Near(PCExtensionPopupRevealTime(shown, shown - 1, NAN),
              shown + .034));
  EXPECT(Near(PCExtensionPopupRevealTime(shown, shown + .05, NAN),
              shown + .084));
  EXPECT(Near(PCExtensionPopupRevealTime(shown, shown + .05, shown + .08),
              shown + .114));
  EXPECT(Near(PCExtensionPopupRevealTime(shown, shown + .05, shown - 2),
              shown + .084));
  EXPECT(Near(PCExtensionPopupRevealTime(shown, shown + .05, shown + .14),
              shown + .15));
  EXPECT(Near(PCExtensionPopupRevealTime(shown, shown + 1, NAN), shown + .15));
}

static bool Whole(CGFloat value) {
  return value == std::round(value);
}

static bool Inside(CGFloat value, CGFloat a, CGFloat b) {
  return value >= std::min(a, b) && value <= std::max(a, b);
}

static void ResizeMotion() {
  const NSRect from = NSMakeRect(400, 300, 300, 228);
  const NSRect grown = NSMakeRect(320, 120, 380, 408);
  PCExtensionPopupResizeFrame start = PCExtensionPopupResizeMotion(0, from, grown);
  EXPECT(NSEqualRects(start.frame, from) && !start.finished);
  EXPECT(!PCExtensionPopupResizeMotion(.17, from, grown).finished);
  PCExtensionPopupResizeFrame end = PCExtensionPopupResizeMotion(.18, from, grown);
  EXPECT(NSEqualRects(end.frame, grown) && end.finished);
  PCExtensionPopupResizeFrame late = PCExtensionPopupResizeMotion(5, from, grown);
  EXPECT(NSEqualRects(late.frame, grown) && late.finished);
  PCExtensionPopupResizeFrame broken =
      PCExtensionPopupResizeMotion(NAN, from, grown);
  EXPECT(NSEqualRects(broken.frame, grown) && broken.finished);
  PCExtensionPopupResizeFrame middle =
      PCExtensionPopupResizeMotion(.09, from, grown);
  EXPECT(NSHeight(middle.frame) > 228 + 180 * .8 &&
         NSHeight(middle.frame) < 408);
  const NSRect pairs[][2] = {{from, grown}, {grown, from}};
  for (const auto& pair : pairs) {
    const NSRect a = pair[0];
    const NSRect b = pair[1];
    CGFloat width = NSWidth(a), height = NSHeight(a);
    for (int step = 0; step <= 24; ++step) {
      const NSRect frame =
          PCExtensionPopupResizeMotion(step / 120.0, a, b).frame;
      EXPECT(NSMaxY(frame) == 528 && NSMaxX(frame) == 700);
      EXPECT(Whole(NSMinX(frame)) && Whole(NSMinY(frame)));
      EXPECT(Inside(NSWidth(frame), NSWidth(a), NSWidth(b)) &&
             Inside(NSHeight(frame), NSHeight(a), NSHeight(b)));
      EXPECT(NSWidth(b) > NSWidth(a) ? NSWidth(frame) >= width
                                     : NSWidth(frame) <= width);
      EXPECT(NSHeight(b) > NSHeight(a) ? NSHeight(frame) >= height
                                       : NSHeight(frame) <= height);
      width = NSWidth(frame);
      height = NSHeight(frame);
    }
  }
  const NSRect fractional = NSMakeRect(100.5, 200.25, 300, 200);
  const NSRect taller = NSMakeRect(100.5, 100.25, 300, 300);
  const NSRect flipped = NSMakeRect(100.5, 200.25, 300, 300);
  for (int step = 0; step <= 24; ++step) {
    const NSRect down =
        PCExtensionPopupResizeMotion(step / 120.0, fractional, taller).frame;
    EXPECT(NSMaxY(down) == 400.25 && NSMinX(down) == 100.5 &&
           NSWidth(down) == 300);
    const NSRect up =
        PCExtensionPopupResizeMotion(step / 120.0, fractional, flipped).frame;
    EXPECT(NSMinY(up) == 200.25 && Inside(NSHeight(up), 200, 300));
  }
  const NSRect above = NSMakeRect(400, 560, 300, 260);
  const NSRect moves[][2] = {
      {from, above},
      {above, from},
      {NSMakeRect(0, 0, 80, 51), NSMakeRect(9, 6, 70, 50)},
      {NSMakeRect(10.25, 0.75, 300.5, 200.75), NSMakeRect(40.5, 310, 260, 333.25)},
      {NSMakeRect(500, 20, 240, 400), NSMakeRect(380, 640.5, 330, 180.25)},
      {NSMakeRect(-900, -300.5, 320, 240), NSMakeRect(-1210.25, 120, 360, 180)},
  };
  for (const auto& move : moves) {
    const NSRect a = move[0];
    const NSRect b = move[1];
    NSRect previous = a;
    for (int step = 0; step <= 24; ++step) {
      const NSRect frame =
          PCExtensionPopupResizeMotion(step / 120.0, a, b).frame;
      EXPECT(Inside(NSMinX(frame), NSMinX(a), NSMinX(b)) &&
             Inside(NSMaxX(frame), NSMaxX(a), NSMaxX(b)) &&
             Inside(NSMinY(frame), NSMinY(a), NSMinY(b)) &&
             Inside(NSMaxY(frame), NSMaxY(a), NSMaxY(b)));
      EXPECT(NSWidth(frame) <= std::max(NSWidth(a), NSWidth(b)) &&
             NSHeight(frame) <= std::max(NSHeight(a), NSHeight(b)));
      EXPECT((NSMinX(frame) - NSMinX(previous)) * (NSMinX(b) - NSMinX(a)) >= 0 &&
             (NSMaxX(frame) - NSMaxX(previous)) * (NSMaxX(b) - NSMaxX(a)) >= 0 &&
             (NSMinY(frame) - NSMinY(previous)) * (NSMinY(b) - NSMinY(a)) >= 0 &&
             (NSMaxY(frame) - NSMaxY(previous)) * (NSMaxY(b) - NSMaxY(a)) >= 0);
      previous = frame;
    }
    EXPECT(NSEqualRects(PCExtensionPopupResizeMotion(.18, a, b).frame, b));
  }
}

static void ResizeRetarget() {
  const NSRect a = NSMakeRect(400, 300, 300, 228);
  const NSRect b = NSMakeRect(400, 100, 300, 428);
  const NSRect c = NSMakeRect(360, 200, 340, 328);
  const PCExtensionPopupResize idle = {NSZeroRect, a, NAN};
  const PCExtensionPopupResize first =
      PCExtensionPopupRetargetResize(idle, a, b, 10, NO);
  EXPECT(NSEqualRects(first.from, a) && NSEqualRects(first.to, b) &&
         Near(first.start, 10));
  const PCExtensionPopupResize same =
      PCExtensionPopupRetargetResize(first, c, b, 10.0625, NO);
  EXPECT(same.start == first.start && NSEqualRects(same.from, a));
  const NSRect visible = PCExtensionPopupResizeMotion(.0625, a, b).frame;
  EXPECT(!NSEqualRects(visible, a) && !NSEqualRects(visible, b));
  const PCExtensionPopupResize second =
      PCExtensionPopupRetargetResize(first, NSZeroRect, c, 10.0625, NO);
  EXPECT(NSEqualRects(second.from, visible) && NSEqualRects(second.to, c) &&
         Near(second.start, 10.0625));
  EXPECT(NSEqualRects(
      PCExtensionPopupResizeMotion(0, second.from, second.to).frame, visible));
  EXPECT(!PCExtensionPopupResizeMotion(.17, second.from, second.to).finished);
  EXPECT(NSEqualRects(
      PCExtensionPopupResizeMotion(.18, second.from, second.to).frame, c));
  const PCExtensionPopupResize instant =
      PCExtensionPopupRetargetResize(first, a, c, 10.0625, YES);
  EXPECT(NSEqualRects(instant.from, c) && NSEqualRects(instant.to, c) &&
         std::isnan(instant.start));
  const PCExtensionPopupResize still =
      PCExtensionPopupRetargetResize(idle, a, a, 10, NO);
  EXPECT(std::isnan(still.start) && NSEqualRects(still.to, a));
  const PCExtensionPopupResize after =
      PCExtensionPopupRetargetResize(first, a, c, 11, NO);
  EXPECT(NSEqualRects(after.from, b) && NSEqualRects(after.to, c));
  for (int bounce = 0; bounce < 2; ++bounce) {
    PCExtensionPopupResize state = idle;
    CGFloat tallest = NSHeight(a);
    NSRect previous = a;
    NSRect last = a;
    double changed = 0;
    for (int tick = 0; tick <= 60; ++tick) {
      const double now = 20 + tick / 120.0;
      if (tick < 24) {
        const CGFloat height =
            228 + 6 * (bounce && tick >= 12 ? 24 - tick : tick + 1);
        last = NSMakeRect(400, 528 - height, 300, height);
        state = PCExtensionPopupRetargetResize(state, a, last, now, NO);
        tallest = std::max(tallest, NSHeight(last));
        changed = now;
      }
      const PCExtensionPopupResizeFrame frame = PCExtensionPopupResizeMotion(
          now - state.start, state.from, state.to);
      EXPECT(NSMaxY(frame.frame) == 528 && NSWidth(frame.frame) == 300);
      EXPECT(std::abs(NSHeight(frame.frame) - NSHeight(previous)) <= 12);
      EXPECT(bounce || NSHeight(frame.frame) >= NSHeight(previous));
      EXPECT(NSHeight(frame.frame) <= tallest);
      EXPECT(frame.finished == (now - changed >= .18));
      previous = frame.frame;
    }
    EXPECT(NSEqualRects(previous, last));
  }
}

int main() {
  @autoreleasepool {
    ParcExitOnUncaughtExceptions();
    OpeningMotion();
    ClosingMotion();
    RevealTiming();
    ResizeMotion();
    ResizeRetarget();
    printf("NativeExtensionPopup motion: %d assertions passed in 5 groups\n",
           assertions);
  }
}
