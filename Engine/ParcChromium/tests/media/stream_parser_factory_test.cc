// Copyright 2026 Parc contributors.
// Installed at //media/parc_tests/stream_parser_factory_test.cc. The fixture is derived from
// Chromium's stream_parser_factory_unittest.cc (Chromium Authors; BSD-style license in
// Chromium's LICENSE) and contains only Parc regressions.

#include "media/filters/stream_parser_factory.h"

#include <string>
#include <vector>

#include "media/base/media_util.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media {

// Parc: AVStreamDataParser's answers for Ogg (canParseExtendedMIMEType).
TEST(ParcStreamParserFactoryTest, ParcSafariOgg) {
  using Codecs = std::vector<std::string>;
  EXPECT_TRUE(StreamParserFactory::ParcIsOggType("audio/ogg"));
  EXPECT_TRUE(StreamParserFactory::ParcIsOggType("application/ogg"));
  EXPECT_FALSE(StreamParserFactory::ParcIsOggType("video/ogg"));

  for (const Codecs& codecs :
       {Codecs{}, Codecs{"opus"}, Codecs{"vorbis"}, Codecs{"flac"},
        Codecs{"opus", "vorbis"}}) {
    EXPECT_TRUE(StreamParserFactory::ParcSafariTakesOgg("audio/ogg", codecs));
    EXPECT_TRUE(StreamParserFactory::ParcCreateOggParser("audio/ogg", codecs));
  }
  EXPECT_TRUE(StreamParserFactory::ParcSafariTakesOgg("application/ogg", {}));
  for (const Codecs& codecs :
       {Codecs{"Opus"}, Codecs{"fLaC"}, Codecs{"speex"}, Codecs{"opus", "vp8"}}) {
    EXPECT_FALSE(StreamParserFactory::ParcSafariTakesOgg("audio/ogg", codecs));
    EXPECT_FALSE(
        StreamParserFactory::ParcCreateOggParser("audio/ogg", codecs));
  }
  EXPECT_FALSE(StreamParserFactory::ParcSafariTakesOgg("application/ogg",
                                                       Codecs{"opus"}));
  EXPECT_FALSE(StreamParserFactory::ParcSafariTakesOgg("video/ogg", {}));

  // Chromium's own answer, which Chrome-identity pages get, is unchanged.
  const Codecs opus = {"opus"};
  NullMediaLog media_log;
  EXPECT_EQ(StreamParserFactory::IsTypeSupported("audio/ogg", opus),
            SupportsType::kNotSupported);
  EXPECT_FALSE(StreamParserFactory::Create("audio/ogg", opus, &media_log));
}

}  // namespace media
