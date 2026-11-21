#include "native_picker_lease.h"
#import "ParcNativeTest.h"
#include <memory>
#include <atomic>
#include <thread>
#include <vector>

@interface PickerLeaseTests : ParcNativeTestCase
@end

@implementation PickerLeaseTests {
  std::vector<intptr_t> _closed;
}

- (std::shared_ptr<parc::NativePickerLease>)lease {
  return std::make_shared<parc::NativePickerLease>([self](intptr_t id) { self->_closed.push_back(id); });
}

- (void)testReleasingACreatedPickerClosesIt {
  { auto lease = [self lease]; lease->Created(1); lease->Release(); }
  PARC_CHECK((_closed == std::vector<intptr_t>{1}));
}

- (void)testAPickerCreatedAfterReleaseClosesOnCreation {
  { auto lease = [self lease]; lease->Release(); lease->Created(2); }
  PARC_CHECK((_closed == std::vector<intptr_t>{2}));
}

- (void)testATransferredPickerStaysOpen {
  { auto lease = [self lease]; lease->Created(3); lease->Transfer(3); lease->Release(); }
  { auto lease = [self lease]; lease->Transfer(4); lease->Release(); lease->Created(4); }
  PARC_CHECK(_closed.empty());
}

- (void)testTransferringAnotherPickerStillClosesTheCreatedOne {
  { auto lease = [self lease]; lease->Created(5); lease->Transfer(6); lease->Release(); }
  { auto lease = [self lease]; lease->Transfer(7); lease->Release(); lease->Created(8); }
  PARC_CHECK((_closed == std::vector<intptr_t>{5, 8}));
}

- (void)testASecondReleaseClosesNothingMore {
  { auto lease = [self lease]; lease->Created(9); lease->Release(); lease->Release(); }
  PARC_CHECK((_closed == std::vector<intptr_t>{9}));
}

- (void)testCreationRacingReleaseClosesExactlyOnce {
  for (int i = 0; i < 500; ++i) {
    std::atomic<int> closes{0};
    std::atomic<bool> wrongPicker{false};
    auto lease = std::make_shared<parc::NativePickerLease>([&](intptr_t id) {
      if (id != 42) wrongPicker = true;
      ++closes;
    });
    std::thread created([lease] { lease->Created(42); });
    std::thread released([lease] { lease->Release(); });
    created.join();
    released.join();
    PARC_CHECK(!wrongPicker);
    PARC_CHECK(closes == 1);
  }
}

@end
