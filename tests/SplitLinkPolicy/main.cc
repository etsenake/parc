#include "native_split_link_api.h"
#include "../Support/TestFailure.h"
#include <iostream>

int main() {
  using parc::ClassifyNativeSplit;
  using parc::NativeSplitDecision;
  PARC_EXPECT(ClassifyNativeSplit(true, false) == NativeSplitDecision::kOrdinary);
  PARC_EXPECT(ClassifyNativeSplit(true, true) == NativeSplitDecision::kAdmitted);
  PARC_EXPECT(ClassifyNativeSplit(false, false) == NativeSplitDecision::kUnmanaged);
  PARC_EXPECT(ClassifyNativeSplit(false, true) == NativeSplitDecision::kUnmanaged);
  std::cout << "Passed native split admission and ordinary fallback policy checks; no browser execution.\n";
}
