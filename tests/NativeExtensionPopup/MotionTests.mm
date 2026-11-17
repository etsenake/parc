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

int main() {
  @autoreleasepool {
    ParcExitOnUncaughtExceptions();
    OpeningMotion();
    ClosingMotion();
    RevealTiming();
    printf("NativeExtensionPopup motion: %d assertions passed in 3 groups\n",
           assertions);
  }
}
