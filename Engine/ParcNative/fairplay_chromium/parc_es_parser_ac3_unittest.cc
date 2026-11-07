// Installed by the reviewed overlay at
// //media/formats/mp2t/parc_es_parser_ac3_unittest.cc (media_unittests).

#include "media/formats/mp2t/parc_es_parser_ac3.h"

#include <stdint.h>

#include <optional>
#include <vector>

#include "base/functional/bind.h"
#include "base/time/time.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/channel_layout.h"
#include "media/base/media_util.h"
#include "media/base/stream_parser_buffer.h"
#include "media/formats/mp2t/es_parser_test_base.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace media::mp2t {
namespace {

// Writes the leading fields of a syncframe, most significant bit first.
class BitWriter {
 public:
  void Write(uint32_t value, int bits) {
    for (int bit = bits - 1; bit >= 0; --bit) {
      if (used_ % 8 == 0) {
        bytes_.push_back(0);
      }
      bytes_.back() |= ((value >> bit) & 1) << (7 - used_ % 8);
      ++used_;
    }
  }
  std::vector<uint8_t> Finish(size_t size) {
    bytes_.resize(size);
    return bytes_;
  }

 private:
  std::vector<uint8_t> bytes_;
  int used_ = 0;
};

// An E-AC-3 syncframe of six blocks at 48 kHz whose bsi() ends after chanmap,
// padded to `size` bytes.
std::vector<uint8_t> Eac3Syncframe(int strmtyp,
                                   int acmod,
                                   int lfeon,
                                   std::optional<uint16_t> chanmap,
                                   size_t size) {
  BitWriter writer;
  writer.Write(0x0B77, 16);
  writer.Write(strmtyp, 2);
  writer.Write(0, 3);  // substreamid
  writer.Write(size / 2 - 1, 11);
  writer.Write(0, 2);  // fscod: 48 kHz
  writer.Write(3, 2);  // numblkscod: six blocks
  writer.Write(acmod, 3);
  writer.Write(lfeon, 1);
  writer.Write(16, 5);  // bsid
  writer.Write(0, 5);   // dialnorm
  writer.Write(0, 1);   // compre
  if (strmtyp == 1) {
    writer.Write(chanmap.has_value(), 1);
    if (chanmap) {
      writer.Write(*chanmap, 16);
    }
  }
  return writer.Finish(size);
}

class ParcEsParserAc3Test : public EsParserTestBase, public testing::Test {
 protected:
  bool Process(bool eac3, const std::vector<Packet>& pes_packets) {
    ParcEsParserAc3 es_parser(
        eac3,
        base::BindRepeating(&ParcEsParserAc3Test::OnAudioConfig,
                            base::Unretained(this)),
        base::BindRepeating(&ParcEsParserAc3Test::OnBuffer,
                            base::Unretained(this)),
        &media_log_);
    return ProcessPesPackets(&es_parser, pes_packets, false);
  }

  void OnAudioConfig(const AudioDecoderConfig& config) {
    config_ = config;
    NewAudioConfig(config);
  }

  void OnBuffer(scoped_refptr<StreamParserBuffer> buffer) {
    buffer_sizes_.push_back(buffer->size());
    EXPECT_TRUE(buffer->is_key_frame());
    EmitBuffer(std::move(buffer));
  }

  NullMediaLog media_log_;
  AudioDecoderConfig config_;
  std::vector<size_t> buffer_sizes_;
};

TEST_F(ParcEsParserAc3Test, Ac3SyncframesAcrossPesPackets) {
  LoadStream("bear.ac3");
  std::vector<Packet> pes_packets = GenerateFixedSizePesPacket(512);
  pes_packets.front().pts = base::Seconds(10);

  EXPECT_TRUE(Process(/*eac3=*/false, pes_packets));
  EXPECT_EQ(config_count_, 1u);
  EXPECT_EQ(buffer_count_, 30u);
  EXPECT_EQ(buffer_sizes_.front(), 834u);
  EXPECT_EQ(config_.codec(), AudioCodec::kAC3);
  EXPECT_EQ(config_.samples_per_second(), 44100);
  EXPECT_EQ(config_.channel_layout(), CHANNEL_LAYOUT_STEREO);
  EXPECT_TRUE(config_.extra_data().empty());
  EXPECT_FALSE(config_.is_encrypted());
  // 1536 samples at 44.1 kHz per syncframe.
  EXPECT_TRUE(buffer_timestamps_.starts_with("(10000) (10034) (10069)"));
}

TEST_F(ParcEsParserAc3Test, Eac3Syncframes) {
  LoadStream("bear.eac3");
  std::vector<Packet> pes_packets = GenerateFixedSizePesPacket(512);
  pes_packets.front().pts = base::Seconds(10);

  EXPECT_TRUE(Process(/*eac3=*/true, pes_packets));
  EXPECT_EQ(config_count_, 1u);
  EXPECT_EQ(buffer_count_, 30u);
  EXPECT_EQ(buffer_sizes_.front(), 870u);
  EXPECT_EQ(config_.codec(), AudioCodec::kEAC3);
  EXPECT_EQ(config_.samples_per_second(), 44100);
  EXPECT_EQ(config_.channel_layout(), CHANNEL_LAYOUT_STEREO);
}

TEST_F(ParcEsParserAc3Test, ParsesOnlyItsOwnCodec) {
  LoadStream("bear.eac3");
  std::vector<Packet> pes_packets = GenerateFixedSizePesPacket(512);
  pes_packets.front().pts = base::Seconds(10);

  EXPECT_TRUE(Process(/*eac3=*/false, pes_packets));
  EXPECT_EQ(config_count_, 0u);
  EXPECT_EQ(buffer_count_, 0u);
}

// ETSI TS 102 366 annex E: an E-AC-3 stream whose independent substream 0
// is AC-3.
TEST_F(ParcEsParserAc3Test, Eac3StreamOfAc3Cores) {
  LoadStream("bear.ac3");
  std::vector<Packet> pes_packets = GenerateFixedSizePesPacket(512);
  pes_packets.front().pts = base::Seconds(10);

  EXPECT_TRUE(Process(/*eac3=*/true, pes_packets));
  EXPECT_EQ(config_count_, 1u);
  EXPECT_EQ(buffer_count_, 30u);
  EXPECT_EQ(config_.codec(), AudioCodec::kEAC3);
  EXPECT_EQ(config_.samples_per_second(), 44100);
  EXPECT_EQ(config_.channel_layout(), CHANNEL_LAYOUT_STEREO);
}

TEST_F(ParcEsParserAc3Test, SkipsBytesBeforeTheFirstSyncframe) {
  LoadStream("bear.ac3");
  // A sync word whose syncframe isn't followed by another.
  const std::vector<uint8_t> junk = {0x00, 0x0B, 0x77, 0x00, 0x00, 0x14,
                                     0x40, 0x40, 0x00, 0x00, 0x00, 0x00,
                                     0x00, 0x00, 0x00, 0x00};
  stream_.insert(stream_.begin(), junk.begin(), junk.end());
  std::vector<Packet> pes_packets = GenerateFixedSizePesPacket(512);
  pes_packets.front().pts = base::Seconds(10);

  EXPECT_TRUE(Process(/*eac3=*/false, pes_packets));
  EXPECT_EQ(buffer_count_, 30u);
  EXPECT_EQ(buffer_sizes_.front(), 834u);
}

TEST_F(ParcEsParserAc3Test, Eac3DependentSubstreamsJoinTheirAccessUnit) {
  // 5.1 independent substreams, each followed by a dependent substream
  // carrying the Lrs/Rrs pair (chanmap bit 6): 7.1, as 'dec3' with that
  // chan_loc reads in MP4.
  for (int i = 0; i < 4; ++i) {
    const std::vector<uint8_t> independent =
        Eac3Syncframe(/*strmtyp=*/0, /*acmod=*/7, /*lfeon=*/1, std::nullopt,
                      256);
    const std::vector<uint8_t> dependent =
        Eac3Syncframe(/*strmtyp=*/1, /*acmod=*/2, /*lfeon=*/0, 0x8000 >> 6,
                      128);
    stream_.insert(stream_.end(), independent.begin(), independent.end());
    stream_.insert(stream_.end(), dependent.begin(), dependent.end());
  }
  std::vector<Packet> pes_packets(1);
  pes_packets.front().size = stream_.size();
  pes_packets.front().pts = base::Seconds(1);

  EXPECT_TRUE(Process(/*eac3=*/true, pes_packets));
  EXPECT_EQ(config_count_, 1u);
  EXPECT_EQ(buffer_sizes_, std::vector<size_t>(4, 384u));
  EXPECT_EQ(config_.channel_layout(), CHANNEL_LAYOUT_7_1);
  EXPECT_EQ(config_.samples_per_second(), 48000);
  EXPECT_EQ(buffer_timestamps_, "(1000) (1032) (1064) (1096)");
}

TEST_F(ParcEsParserAc3Test, Eac3ExtensionInNextPacketWaitsForNextFrame) {
  const auto core = Eac3Syncframe(0, 7, 1, std::nullopt, 256);
  const auto extension = Eac3Syncframe(1, 2, 0, 0x8000 >> 6, 128);
  ParcEsParserAc3 parser(
      true,
      base::BindRepeating(&ParcEsParserAc3Test_Eac3ExtensionInNextPacketWaitsForNextFrame_Test::OnAudioConfig,
                          base::Unretained(this)),
      base::BindRepeating(&ParcEsParserAc3Test_Eac3ExtensionInNextPacketWaitsForNextFrame_Test::OnBuffer,
                          base::Unretained(this)), &media_log_);
  EXPECT_TRUE(parser.Parse(core, base::Seconds(1), kNoDecodeTimestamp));
  EXPECT_TRUE(buffer_sizes_.empty());
  EXPECT_TRUE(parser.Parse(extension, kNoTimestamp, kNoDecodeTimestamp));
  EXPECT_TRUE(buffer_sizes_.empty());
  EXPECT_TRUE(parser.Parse(core, kNoTimestamp, kNoDecodeTimestamp));
  EXPECT_EQ(buffer_sizes_, std::vector<size_t>({384}));
  EXPECT_EQ(config_.channel_layout(), CHANNEL_LAYOUT_7_1);
  EXPECT_TRUE(parser.Parse(extension, kNoTimestamp, kNoDecodeTimestamp));
  parser.Flush();
  EXPECT_EQ(buffer_sizes_, std::vector<size_t>({384, 384}));
  EXPECT_EQ(config_count_, 1u);
}

TEST_F(ParcEsParserAc3Test, Eac3DependentChanmapLfe2AndLtsRts) {
  // Lrs/Rrs (chanmap bit 6) with LFE2 (bit 14) is chan_loc LRS_RRS | LFE2,
  // which matches no single location, as in mp4::EAC3: 5.1. With Lts/Rts
  // (bit 13), which chan_loc can't name, it stays LRS_RRS: 7.1.
  for (uint16_t chanmap : {uint16_t{0x8000 >> 14}, uint16_t{0x8000 >> 13}}) {
    stream_.clear();
    buffer_sizes_.clear();
    config_count_ = 0;
    const std::vector<uint8_t> independent =
        Eac3Syncframe(/*strmtyp=*/0, /*acmod=*/7, /*lfeon=*/1, std::nullopt,
                      256);
    const std::vector<uint8_t> dependent = Eac3Syncframe(
        /*strmtyp=*/1, /*acmod=*/2, /*lfeon=*/0,
        static_cast<uint16_t>(chanmap | (0x8000 >> 6)), 128);
    stream_.insert(stream_.end(), independent.begin(), independent.end());
    stream_.insert(stream_.end(), dependent.begin(), dependent.end());
    std::vector<Packet> pes_packets(1);
    pes_packets.front().size = stream_.size();
    pes_packets.front().pts = base::Seconds(1);

    EXPECT_TRUE(Process(/*eac3=*/true, pes_packets));
    EXPECT_EQ(config_.channel_layout(), chanmap == (0x8000 >> 14)
                                            ? CHANNEL_LAYOUT_5_1
                                            : CHANNEL_LAYOUT_7_1)
        << chanmap;
  }
}

}  // namespace
}  // namespace media::mp2t
