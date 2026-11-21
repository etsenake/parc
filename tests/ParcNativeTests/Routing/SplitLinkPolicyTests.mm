#import "ParcNativeTest.h"
#include "native_split_link_api.h"

using parc::ClassifyNativeSplit;
using parc::NativeSplitDecision;

@interface SplitLinkPolicyTests : ParcNativeTestCase
@end

@implementation SplitLinkPolicyTests

- (void)testAManagedLinkSplitsOnlyWhenAdmitted {
  PARC_CHECK(ClassifyNativeSplit(true, false) == NativeSplitDecision::kOrdinary);
  PARC_CHECK(ClassifyNativeSplit(true, true) == NativeSplitDecision::kAdmitted);
}

- (void)testAnUnmanagedLinkIsNeverSplit {
  PARC_CHECK(ClassifyNativeSplit(false, false) == NativeSplitDecision::kUnmanaged);
  PARC_CHECK(ClassifyNativeSplit(false, true) == NativeSplitDecision::kUnmanaged);
}

@end
