#import "ParcNativeTest.h"
#include "native_split_link_api.h"

using parc::ClassifyNativeSplit;
using parc::NativeSplitDecision;

@interface SplitLinkPolicyTests : ParcNativeTestCase
@end

@implementation SplitLinkPolicyTests

- (void)testManagedLinksWithoutAdmissionStayOrdinary {
  PARC_CHECK(ClassifyNativeSplit(true, false) == NativeSplitDecision::kOrdinary);
}

- (void)testAdmittedManagedLinksSplit {
  PARC_CHECK(ClassifyNativeSplit(true, true) == NativeSplitDecision::kAdmitted);
}

- (void)testUnmanagedLinksRemainUnmanagedWithoutAdmission {
  PARC_CHECK(ClassifyNativeSplit(false, false) == NativeSplitDecision::kUnmanaged);
}

- (void)testAdmissionCannotSplitAnUnmanagedLink {
  PARC_CHECK(ClassifyNativeSplit(false, true) == NativeSplitDecision::kUnmanaged);
}

@end
