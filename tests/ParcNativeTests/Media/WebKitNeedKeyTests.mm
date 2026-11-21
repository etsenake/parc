#import "ParcNativeTest.h"
#include "parc_webkit_skd_init_data.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

namespace {


#define Check(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)

}

@interface WebKitNeedKeyTests : ParcNativeTestCase
@end

@implementation WebKitNeedKeyTests

- (void)testAnAsciiUriIsALengthThenUtf16 {
    const std::vector<uint8_t> data = blink::ParcWebKitSkdInitData(u"skd://k");
    const std::vector<uint8_t> expected = {14, 0, 0, 0, 's', 0, 'k', 0, 'd', 0, ':', 0,
                                           '/', 0, '/', 0, 'k', 0};
    Check(data == expected, "an ASCII URI: length 14, then UTF-16LE");
}

- (void)testAnEmptyUriIsAZeroLength {
    const std::vector<uint8_t> data = blink::ParcWebKitSkdInitData(u"");
    Check(data == std::vector<uint8_t>({0, 0, 0, 0}), "an empty URI is a zero length");
}

- (void)testNonAsciiUrisCountCodeUnitsLittleEndian {
    const std::u16string uri = u"skd://é\U0001F511";
    const std::vector<uint8_t> data = blink::ParcWebKitSkdInitData(uri);
    Check(uri.size() == 9 && data.size() == 4 + 18, "code units, not characters");
    Check(data[0] == 18 && data[1] == 0 && data[2] == 0 && data[3] == 0, "the byte length");
    Check(data[16] == 0xe9 && data[17] == 0x00, "U+00E9 little-endian");
    Check(data[18] == 0x3d && data[19] == 0xd8 && data[20] == 0x11 && data[21] == 0xdd,
          "U+1F511 as its surrogate pair, each unit little-endian");
}

- (void)testALongUriHasAMultiByteLength {
    const std::u16string uri(300, u'a');
    const std::vector<uint8_t> data = blink::ParcWebKitSkdInitData(uri);
    Check(data[0] == (600 & 0xff) && data[1] == (600 >> 8) && data[2] == 0 && data[3] == 0,
          "a 600-byte length, little-endian");
    Check(data.size() == 604 && data[4] == 'a' && data[5] == 0 && data[603] == 0,
          "every unit follows");
}

@end
