#import "ParcNativeTest.h"
#include "native_escape_state.h"

@interface PeekEscapeTests : ParcNativeTestCase
@end

using State = parc::NativeEscapeState;
using Status = State::Status;

static State AfterQuickRepeat() {
  State state;
  state.Complete(false, 10, 0.5);
  state.Complete(false, 11, 0.5);
  state.Complete(false, 11.5, 0.5);
  state.Complete(false, 11.6, 0.5);
  return state;
}

@implementation PeekEscapeTests {
  parc::NativeEscapeEvents _events;
}

- (void)testAFirstEscapeReportsConsumptionAndEditing {
  for (bool consumed : {false, true}) {
    for (bool editable : {false, true}) {
      State state;
      if (consumed) state.ConsumedRawKeyDown();
      auto first = state.Complete(editable, 10, 0.5);
      PARC_CHECK(first.status == (consumed ? Status::kConsuming : Status::kUnconsumed));
      PARC_CHECK(first.editable == editable);
      PARC_CHECK(first.prefers_confirmation() == (consumed || editable));
      PARC_CHECK(!first.repeated);
    }
  }
}

- (void)testASlowSecondEscapeMayHaveBeenConsumed {
  State state;
  state.Complete(false, 10, 0.5);
  auto slow = state.Complete(false, 11, 0.5);
  PARC_CHECK(slow.status == Status::kPossiblyConsumed && !slow.repeated);
}

- (void)testAQuickSecondEscapeIsAnUnconsumedRepeat {
  State state;
  state.Complete(false, 10, 0.5);
  state.Complete(false, 11, 0.5);
  auto repeat = state.Complete(false, 11.5, 0.5);
  PARC_CHECK(repeat.status == Status::kUnconsumed && repeat.repeated);
  PARC_CHECK(!repeat.prefers_confirmation());
  PARC_CHECK(state.Complete(false, 11.6, 0.5).status == Status::kUnconsumed);
}

- (void)testAConsumedKeyDownStartsAFreshEscape {
  State state = AfterQuickRepeat();
  state.ConsumedRawKeyDown();
  auto consumed = state.Complete(false, 12, 0.5);
  PARC_CHECK(consumed.status == Status::kConsuming && !consumed.repeated);
  PARC_CHECK(state.Complete(false, 12.1, 0.5).status == Status::kUnconsumed);
}

- (void)testResetForgetsTheLastEscape {
  State state = AfterQuickRepeat();
  state.ConsumedRawKeyDown();
  state.Complete(false, 12, 0.5);
  state.Complete(false, 12.1, 0.5);
  state.Reset();
  PARC_CHECK(!state.Complete(false, 12.2, 0.5).repeated);
}

- (void)testAnEventBeginsOnceAndAcknowledgesOnlyItsOwnKey {
  PARC_CHECK(_events.Begin({100, 53, 1, 0}));
  PARC_CHECK(!_events.Begin({100, 53, 1, 0}));
  PARC_CHECK(!_events.OwnsUnhandled(1, 53, 0));
  PARC_CHECK(!_events.Acknowledge(101, 53, false, false, 10, 0.5));
  PARC_CHECK(!_events.Acknowledge(100, 52, false, false, 10, 0.5));
  PARC_CHECK(_events.Acknowledge(100, 53, true, false, 10, 0.5).has_value());
  PARC_CHECK(!_events.Acknowledge(100, 53, false, false, 11, 0.5));
}

- (void)testAnAcknowledgedEventOwnsOnlyItsUnhandledKey {
  _events.Begin({100, 53, 1, 0});
  _events.Acknowledge(100, 53, true, false, 10, 0.5);
  PARC_CHECK(_events.OwnsUnhandled(1, 53, 0));
  PARC_CHECK(!_events.OwnsUnhandled(1, 53, 1));
  PARC_CHECK(!_events.OwnsUnhandled(2, 53, 0));
}

- (void)testEachEscapeIsTakenOnceWithItsOwnState {
  _events.Begin({100, 53, 1, 0});
  const auto first = _events.Acknowledge(100, 53, true, false, 10, 0.5);
  _events.Begin({200, 53, 2, 0});
  const auto second = _events.Acknowledge(200, 53, false, true, 11, 0.5);
  PARC_CHECK(second && second != first);
  PARC_CHECK(_events.Take(*first)->prefers_confirmation());
  PARC_CHECK(!_events.Take(*first));
  PARC_CHECK(!_events.Begin({100, 53, 1, 0}));
  PARC_CHECK(!_events.OwnsUnhandled(1, 53, 0));
  PARC_CHECK(_events.Take(*second)->editable);
  PARC_CHECK(!_events.Take(*second));
}

- (void)testInvalidationDropsThePendingEscapeForGood {
  _events.Begin({300, 53, 3, 0});
  const auto cancelled = _events.Acknowledge(300, 53, false, false, 12, 0.5);
  _events.Invalidate();
  PARC_CHECK(!_events.Take(*cancelled));
  PARC_CHECK(!_events.OwnsUnhandled(3, 53, 0));
  PARC_CHECK(!_events.Begin({300, 53, 3, 0}));
}

- (void)testAReplacementAfterInvalidationStartsFresh {
  _events.Begin({300, 53, 3, 0});
  const auto cancelled = _events.Acknowledge(300, 53, false, false, 12, 0.5);
  _events.Invalidate();
  _events.Begin({400, 53, 4, 0});
  const auto replacement = _events.Acknowledge(400, 53, false, false, 12.1, 0.5);
  PARC_CHECK(replacement && replacement != cancelled);
  PARC_CHECK(!_events.Take(*cancelled));
  auto reset = _events.Take(*replacement);
  PARC_CHECK(reset && reset->status == Status::kUnconsumed && !reset->repeated);
}

- (void)testAnIgnoredNativeEscapeSurvivesInvalidationForItsKeyOnly {
  _events.IgnoreNative(5, 53, 0);
  _events.Invalidate();
  PARC_CHECK(_events.IsIgnored(5, 53, 0));
  PARC_CHECK(!_events.IsIgnored(6, 53, 0));
  PARC_CHECK(!_events.IsIgnored(5, 52, 0));
  PARC_CHECK(!_events.IsIgnored(5, 53, 1));
}

- (void)testInvalidationBeforeAcknowledgementRefusesIt {
  _events.Begin({500, 53, 5, 0});
  _events.Invalidate();
  PARC_CHECK(!_events.Acknowledge(500, 53, true, true, 13, 0.5));
}

@end
