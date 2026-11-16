#include "native_picker_lease.h"
#include "../Support/TestFailure.h"
#include <memory>
#include <atomic>
#include <thread>
#include <vector>

int main() {
  std::vector<intptr_t> closed;
  auto make = [&] { return std::make_shared<parc::NativePickerLease>(
      [&](intptr_t id) { closed.push_back(id); }); };
  { auto lease = make(); lease->Created(1); lease->Release(); }
  PARC_EXPECT((closed == std::vector<intptr_t>{1}));
  { auto lease = make(); lease->Release(); lease->Created(2); }
  PARC_EXPECT((closed == std::vector<intptr_t>{1, 2}));
  { auto lease = make(); lease->Created(3); lease->Transfer(3); lease->Release(); }
  { auto lease = make(); lease->Transfer(4); lease->Release(); lease->Created(4); }
  PARC_EXPECT((closed == std::vector<intptr_t>{1, 2}));
  { auto lease = make(); lease->Created(5); lease->Transfer(6); lease->Release(); }
  { auto lease = make(); lease->Transfer(7); lease->Release(); lease->Created(8); }
  PARC_EXPECT((closed == std::vector<intptr_t>{1, 2, 5, 8}));
  { auto lease = make(); lease->Created(9); lease->Release(); lease->Release(); }
  PARC_EXPECT((closed == std::vector<intptr_t>{1, 2, 5, 8, 9}));
  for (int i = 0; i < 500; ++i) {
    std::atomic<int> closes{0};
    auto lease = std::make_shared<parc::NativePickerLease>(
        [&](intptr_t id) { PARC_EXPECT(id == 42); ++closes; });
    std::thread created([lease] { lease->Created(42); });
    std::thread released([lease] { lease->Release(); });
    created.join(); released.join();
    PARC_EXPECT(closes == 1);
  }
}
