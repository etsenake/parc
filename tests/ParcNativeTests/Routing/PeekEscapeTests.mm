#import "ParcNativeTest.h"
#include <iostream>
#include "native_escape_state.h"

@interface PeekEscapeTests : ParcNativeTestCase
@end

@implementation PeekEscapeTests

- (void)testEscapeStateAndEventOwnership {
  @autoreleasepool {
  using State = parc::NativeEscapeState;
  using Status = State::Status;
  auto expect = [&](bool condition) {
    PARC_CHECK(condition);
  };
  for (bool consumed : {false, true}) {
    for (bool editable : {false, true}) {
      State state;
      if (consumed)
        state.ConsumedRawKeyDown();
      auto first = state.Complete(editable, 10, 0.5);
      expect(first.status ==
             (consumed ? Status::kConsuming : Status::kUnconsumed));
      expect(first.editable == editable);
      expect(first.prefers_confirmation() == (consumed || editable));
      expect(!first.repeated);
    }
  }
  State state;
  state.Complete(false, 10, 0.5);
  auto slow = state.Complete(false, 11, 0.5);
  expect(slow.status == Status::kPossiblyConsumed && !slow.repeated);
  auto repeat = state.Complete(false, 11.5, 0.5);
  expect(repeat.status == Status::kUnconsumed && repeat.repeated);
  expect(!repeat.prefers_confirmation());
  expect(state.Complete(false, 11.6, 0.5).status == Status::kUnconsumed);
  state.ConsumedRawKeyDown();
  auto consumed = state.Complete(false, 12, 0.5);
  expect(consumed.status == Status::kConsuming && !consumed.repeated);
  expect(state.Complete(false, 12.1, 0.5).status == Status::kUnconsumed);
  state.Reset();
  expect(!state.Complete(false, 12.2, 0.5).repeated);

  parc::NativeEscapeEvents events;
  expect(events.Begin({100, 53, 1, 0}));
  expect(!events.Begin({100, 53, 1, 0}));
  expect(!events.OwnsUnhandled(1, 53, 0));
  expect(!events.Acknowledge(101, 53, false, false, 10, 0.5));
  expect(!events.Acknowledge(100, 52, false, false, 10, 0.5));
  const auto first = events.Acknowledge(100, 53, true, false, 10, 0.5);
  expect(first.has_value());
  expect(events.OwnsUnhandled(1, 53, 0));
  expect(!events.OwnsUnhandled(1, 53, 1));
  expect(!events.OwnsUnhandled(2, 53, 0));
  expect(!events.Acknowledge(100, 53, false, false, 11, 0.5));
  events.Begin({200, 53, 2, 0});
  const auto second = events.Acknowledge(200, 53, false, true, 11, 0.5);
  expect(second && second != first);
  expect(events.Take(*first)->prefers_confirmation());
  expect(!events.Take(*first));
  expect(!events.Begin({100, 53, 1, 0}));
  expect(!events.OwnsUnhandled(1, 53, 0));
  expect(events.Take(*second)->editable);
  expect(!events.Take(*second));
  events.Begin({300, 53, 3, 0});
  const auto cancelled = events.Acknowledge(300, 53, false, false, 12, 0.5);
  events.Invalidate();
  expect(!events.Take(*cancelled));
  expect(!events.OwnsUnhandled(3, 53, 0));
  expect(!events.Begin({300, 53, 3, 0}));
  events.Begin({400, 53, 4, 0});
  const auto replacement = events.Acknowledge(400, 53, false, false, 12.1, 0.5);
  expect(replacement && replacement != cancelled);
  expect(!events.Take(*cancelled));
  auto reset = events.Take(*replacement);
  expect(reset && reset->status == Status::kUnconsumed && !reset->repeated);
  events.IgnoreNative(5, 53, 0);
  events.Invalidate();
  expect(events.IsIgnored(5, 53, 0));
  expect(!events.IsIgnored(6, 53, 0));
  expect(!events.IsIgnored(5, 52, 0));
  expect(!events.IsIgnored(5, 53, 1));
  events.Begin({500, 53, 5, 0});
  events.Invalidate();
  expect(!events.Acknowledge(500, 53, true, true, 13, 0.5));
  }
}

@end
