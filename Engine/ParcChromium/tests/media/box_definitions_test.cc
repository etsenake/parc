// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/box_definitions_test.cc. The fixture is derived from
// Chromium's box_definitions_unittest.cc (Chromium Authors; BSD-style license in
// Chromium's LICENSE) and contains only Parc regressions.

#include "media/formats/mp4/box_definitions.h"

#include <stdint.h>

#include <memory>
#include <vector>

#include "media/base/mock_media_log.h"
#include "media/formats/mp4/box_reader.h"
#include "media/formats/mp4/parse_result.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media::mp4 {

using testing::StrictMock;

class ParcBoxDefinitionsTest : public testing::Test {
 public:
  ParcBoxDefinitionsTest() = default;

 protected:
  StrictMock<MockMediaLog> media_log_;
};

TEST_F(ParcBoxDefinitionsTest, ParcPCMConfiguration) {
  for (uint8_t endian : {0, 1}) {
    for (uint8_t bits : {16, 24, 32, 64}) {
      const uint8_t data[] = {0, 0, 0, 14, 'p', 'c', 'm', 'C',
                              0, 0, 0, 0, endian, bits};
      std::unique_ptr<BoxReader> reader(
          BoxReader::ReadConcatentatedBoxes(data, &media_log_));
      ASSERT_TRUE(reader->ScanChildren());
      PCMConfiguration pcm;
      ASSERT_TRUE(reader->ReadChild(&pcm));
      EXPECT_EQ(pcm.format_flags, endian);
      EXPECT_EQ(pcm.sample_size, bits);
    }
  }
}

TEST_F(ParcBoxDefinitionsTest, ParcPCMConfigurationRejectsVersionAndTruncation) {
  for (bool bad_version : {false, true}) {
    const std::vector<uint8_t> data = bad_version
        ? std::vector<uint8_t>{0,0,0,14,'p','c','m','C',1,0,0,0,1,16}
        : std::vector<uint8_t>{0,0,0,13,'p','c','m','C',0,0,0,0,1};
    std::unique_ptr<BoxReader> reader(
        BoxReader::ReadConcatentatedBoxes(data, &media_log_));
    ASSERT_TRUE(reader->ScanChildren());
    PCMConfiguration pcm;
    EXPECT_FALSE(reader->ReadChild(&pcm));
  }
}

}  // namespace media::mp4
