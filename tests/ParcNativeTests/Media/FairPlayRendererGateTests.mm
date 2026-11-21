#import "ParcNativeTest.h"
#include "fairplay_identity_policy.h"
#include "parc_safari_identity.h"

#include <vector>

@interface ParcNativeTests_FairPlayRendererGateTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_FairPlayRendererGateTests

- (void)testTheParserKeepsSupportedCodecsAndNormalizesWhitespace {
  const auto codecs = blink::ParcSafariMp2tParserCodecs(" , avc1.42E01E,\tmp4a.40.5, ac-3 ");
  PARC_CHECK(codecs && *codecs == "avc1.42E01E,mp4a.40.5");
}

- (void)testWhitespaceOnlyMeansAnEmptyParserList {
  const auto codecs = blink::ParcSafariMp2tParserCodecs(" \t\r\n");
  PARC_CHECK(codecs && codecs->empty());
}

- (void)testBareSeparatorsAreRejected {
  PARC_CHECK(!blink::ParcSafariMp2tParserCodecs(", ,"));
}

- (void)testOneInvalidCodecRejectsTheList {
  PARC_CHECK(!blink::ParcSafariMp2tParserCodecs("avc1.42E01E,invalid"));
}

- (void)testTheRendererRecognizesASafariMajorMinorVersion {
  PARC_CHECK(blink::IsParcSafariIdentityUserAgent(blink::String(parc::fairplay_identity::SafariUserAgent("27.2"))));
}

- (void)testTheRendererRecognizesASafariPatchVersion {
  PARC_CHECK(blink::IsParcSafariIdentityUserAgent(blink::String(parc::fairplay_identity::SafariUserAgent("26.0.1"))));
}

- (void)testChromeDoesNotAdvertiseSafariIdentity {
  PARC_CHECK(!blink::IsParcSafariIdentityUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36"));
}

- (void)testChromiumDoesNotAdvertiseSafariIdentity {
  PARC_CHECK(!blink::IsParcSafariIdentityUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chromium/144.0.0.0 Safari/537.36"));
}

- (void)testChromeForIOSDoesNotAdvertiseSafariIdentity {
  PARC_CHECK(!blink::IsParcSafariIdentityUserAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
      "AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/144.0.0.0 Version/18.0 "
      "Mobile/15E148 Safari/604.1"));
}

- (void)testFirefoxForIOSDoesNotAdvertiseSafariIdentity {
  PARC_CHECK(!blink::IsParcSafariIdentityUserAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
      "AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/140.0 Version/18.0 "
      "Mobile/15E148 Safari/605.1.15"));
}

- (void)testEdgeForIOSDoesNotAdvertiseSafariIdentity {
  PARC_CHECK(!blink::IsParcSafariIdentityUserAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
      "AppleWebKit/605.1.15 (KHTML, like Gecko) EdgiOS/140.0 Version/18.0 "
      "Mobile/15E148 Safari/605.1.15"));
}

- (void)testFirefoxDoesNotAdvertiseSafariIdentity {
  PARC_CHECK(!blink::IsParcSafariIdentityUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:140.0) Gecko/20100101 "
      "Firefox/140.0"));
}

- (void)testAnEmptyUserAgentDoesNotAdvertiseSafariIdentity {
  PARC_CHECK(!blink::IsParcSafariIdentityUserAgent(""));
}

- (void)testSinfMatchesTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(blink::IsParcSafariOnlyInitDataType("sinf"));
}

- (void)testSkdMatchesTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(blink::IsParcSafariOnlyInitDataType("skd"));
}

- (void)testMptsMatchesTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(blink::IsParcSafariOnlyInitDataType("mpts"));
}

- (void)testCencDoesNotMatchTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlyInitDataType("cenc"));
}

- (void)testKeyidsDoesNotMatchTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlyInitDataType("keyids"));
}

- (void)testWebmDoesNotMatchTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlyInitDataType("webm"));
}

- (void)testUppercaseSinfDoesNotMatchTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlyInitDataType("SINF"));
}

- (void)testMixedCaseSkdDoesNotMatchTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlyInitDataType("Skd"));
}

- (void)testPaddedSinfDoesNotMatchTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlyInitDataType("sinf "));
}

- (void)testUppercaseMptsDoesNotMatchTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlyInitDataType("MPTS"));
}

- (void)testMisspelledMptsDoesNotMatchTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlyInitDataType("mtps"));
}

- (void)testEmptyDoesNotMatchTheSafariOnlyInitDataTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlyInitDataType(""));
}

- (void)testCencMatchesTheSafariEncryptionSchemeRule {
  PARC_CHECK(blink::IsParcSafariEncryptionScheme("cenc"));
}

- (void)testCbcsMatchesTheSafariEncryptionSchemeRule {
  PARC_CHECK(blink::IsParcSafariEncryptionScheme("cbcs"));
}

- (void)testPatternCbcsDoesNotMatchTheSafariEncryptionSchemeRule {
  PARC_CHECK(!blink::IsParcSafariEncryptionScheme("cbcs-1-9"));
}

- (void)testEmptyDoesNotMatchTheSafariEncryptionSchemeRule {
  PARC_CHECK(!blink::IsParcSafariEncryptionScheme(""));
}

- (void)testUppercaseCbcsDoesNotMatchTheSafariEncryptionSchemeRule {
  PARC_CHECK(!blink::IsParcSafariEncryptionScheme("CBCS"));
}

- (void)testCensDoesNotMatchTheSafariEncryptionSchemeRule {
  PARC_CHECK(!blink::IsParcSafariEncryptionScheme("cens"));
}

- (void)testCbcOneDoesNotMatchTheSafariEncryptionSchemeRule {
  PARC_CHECK(!blink::IsParcSafariEncryptionScheme("cbc1"));
}

- (void)testTemporaryMatchesTheSafariSessionTypeRule {
  PARC_CHECK(blink::IsParcSafariSessionType("temporary"));
}

- (void)testUsageRecordMatchesTheSafariSessionTypeRule {
  PARC_CHECK(blink::IsParcSafariSessionType("persistent-usage-record"));
}

- (void)testLicenseMatchesTheSafariSessionTypeRule {
  PARC_CHECK(blink::IsParcSafariSessionType("persistent-license"));
}

- (void)testEmptyDoesNotMatchTheSafariSessionTypeRule {
  PARC_CHECK(!blink::IsParcSafariSessionType(""));
}

- (void)testCapitalizedTemporaryDoesNotMatchTheSafariSessionTypeRule {
  PARC_CHECK(!blink::IsParcSafariSessionType("Temporary"));
}

- (void)testPersistentDoesNotMatchTheSafariSessionTypeRule {
  PARC_CHECK(!blink::IsParcSafariSessionType("persistent"));
}

- (void)testPaddedLicenseDoesNotMatchTheSafariSessionTypeRule {
  PARC_CHECK(!blink::IsParcSafariSessionType("persistent-license "));
}

- (void)testBaseMatchesTheFairPlayKeySystemRule {
  PARC_CHECK(blink::IsParcFairPlayKeySystem("com.apple.fps"));
}

- (void)testVersionOneMatchesTheFairPlayKeySystemRule {
  PARC_CHECK(blink::IsParcFairPlayKeySystem("com.apple.fps.1_0"));
}

- (void)testVersionThreeMatchesTheFairPlayKeySystemRule {
  PARC_CHECK(blink::IsParcFairPlayKeySystem("com.apple.fps.3_0"));
}

- (void)testPrefixMatchesTheFairPlayKeySystemRule {
  PARC_CHECK(blink::IsParcFairPlayKeySystem("com.apple.fps."));
}

- (void)testSimilarPrefixDoesNotMatchTheFairPlayKeySystemRule {
  PARC_CHECK(!blink::IsParcFairPlayKeySystem("com.apple.fpsx"));
}

- (void)testUppercaseDoesNotMatchTheFairPlayKeySystemRule {
  PARC_CHECK(!blink::IsParcFairPlayKeySystem("COM.APPLE.FPS"));
}

- (void)testApplePrefixDoesNotMatchTheFairPlayKeySystemRule {
  PARC_CHECK(!blink::IsParcFairPlayKeySystem("com.apple"));
}

- (void)testClearKeyDoesNotMatchTheFairPlayKeySystemRule {
  PARC_CHECK(!blink::IsParcFairPlayKeySystem("org.w3c.clearkey"));
}

- (void)testEmptyDoesNotMatchTheFairPlayKeySystemRule {
  PARC_CHECK(!blink::IsParcFairPlayKeySystem(""));
}

- (void)testUsageRecordMatchesTheSafariOnlySessionTypeRule {
  PARC_CHECK(blink::IsParcSafariOnlySessionType("persistent-usage-record"));
}

- (void)testTemporaryDoesNotMatchTheSafariOnlySessionTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlySessionType("temporary"));
}

- (void)testPersistentLicenseDoesNotMatchTheSafariOnlySessionTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlySessionType("persistent-license"));
}

- (void)testMixedCaseDoesNotMatchTheSafariOnlySessionTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlySessionType("Persistent-Usage-Record"));
}

- (void)testPaddedDoesNotMatchTheSafariOnlySessionTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlySessionType("persistent-usage-record "));
}

- (void)testEmptyDoesNotMatchTheSafariOnlySessionTypeRule {
  PARC_CHECK(!blink::IsParcSafariOnlySessionType(""));
}

- (void)testMonoCanSpatialize {
  PARC_CHECK(blink::IsParcSafariSpatialAudioSupported(std::vector<uint32_t>{0x6d6f7374}, 1));
}

- (void)testStereoCanSpatialize {
  PARC_CHECK(blink::IsParcSafariSpatialAudioSupported(std::vector<uint32_t>{0x6d6f7374}, 2));
}

- (void)testZeroChannelsCannotSpatialize {
  PARC_CHECK(!blink::IsParcSafariSpatialAudioSupported(std::vector<uint32_t>{0x6d6f7374}, 0));
}

- (void)testMultichannelAudioCanSpatialize {
  PARC_CHECK(blink::IsParcSafariSpatialAudioSupported(std::vector<uint32_t>{0x6d6c7469}, 5.1));
}

- (void)testAMultichannelSourceDoesNotSpatializeStereo {
  PARC_CHECK(!blink::IsParcSafariSpatialAudioSupported(std::vector<uint32_t>{0x6d6c7469}, 2));
}

- (void)testBinauralAudioDoesNotSpatialize {
  PARC_CHECK(!blink::IsParcSafariSpatialAudioSupported(std::vector<uint32_t>{0x62696e68}, 6));
}

- (void)testAMissingLayoutCannotSpatialize {
  PARC_CHECK(!blink::IsParcSafariSpatialAudioSupported(std::vector<uint32_t>{}, 2));
}

@end
