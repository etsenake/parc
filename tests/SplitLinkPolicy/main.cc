#include "native_split_link_api.h"
#include <cassert>
#include <iostream>

int main() {
  using parc::ClassifyNativeSplit;
  using parc::NativeSplitDecision;
  assert(ClassifyNativeSplit(true, false) == NativeSplitDecision::kOrdinary);
  assert(ClassifyNativeSplit(true, true) == NativeSplitDecision::kAdmitted);
  assert(ClassifyNativeSplit(false, false) == NativeSplitDecision::kUnmanaged);
  assert(ClassifyNativeSplit(false, true) == NativeSplitDecision::kUnmanaged);
  std::cout << "Passed native split admission and ordinary fallback policy checks; no browser execution.\n";
}
