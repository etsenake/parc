// Installed by the reviewed overlay at
// //media/formats/mp2t/parc_es_parser_ac3.cc (media, macOS).

#include "media/formats/mp2t/parc_es_parser_ac3.h"

#include <array>
#include <utility>

#include "base/logging.h"
#include "base/numerics/safe_conversions.h"
#include "media/base/audio_timestamp_helper.h"
#include "media/base/bit_reader.h"
#include "media/base/channel_layout.h"
#include "media/base/media_util.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/timestamp_constants.h"
#include "media/formats/common/offset_byte_queue.h"
#include "media/formats/mp2t/mp2t_common.h"
#include "media/formats/mp4/ac3_constants.h"

namespace media::mp2t {

namespace {

// Enough for every header field read below (ETSI TS 102 366 4.3.2 and
// E.1.2.2, up to an E-AC-3 dependent substream's chanmap).
constexpr size_t kHeaderSize = 12;

constexpr std::array<int, 3> kSampleRates = {48000, 44100, 32000};
constexpr std::array<int, 3> kReducedSampleRates = {24000, 22050, 16000};
constexpr std::array<int, 4> kBlocksPerSyncframe = {1, 2, 3, 6};
// Nominal bit rates in kbit/s by frmsizecod / 2 (ETSI TS 102 366 table 4.13).
constexpr std::array<int, 19> kBitRates = {
    32,  40,  48,  56,  64,  80,  96,  112, 128, 160,
    192, 224, 256, 320, 384, 448, 512, 576, 640};

bool StartsWithSyncWord(base::span<const uint8_t> data) {
  return data.size() >= 2 && data[0] == 0x0B && data[1] == 0x77;
}

}  // namespace

ParcEsParserAc3::ParcEsParserAc3(bool eac3,
                                 const NewAudioConfigCB& new_audio_config_cb,
                                 EmitBufferCB emit_buffer_cb,
                                 MediaLog* media_log)
    : eac3_(eac3),
      media_log_(MediaLog::CloneSafely(media_log)),
      new_audio_config_cb_(new_audio_config_cb),
      emit_buffer_cb_(std::move(emit_buffer_cb)) {
  DCHECK(media_log_);
}

ParcEsParserAc3::~ParcEsParserAc3() = default;

void ParcEsParserAc3::Flush() {}

void ParcEsParserAc3::ResetInternal() {
  last_audio_decoder_config_ = AudioDecoderConfig();
}

std::optional<ParcEsParserAc3::Syncframe> ParcEsParserAc3::ReadSyncframe(
    base::span<const uint8_t> data) const {
  if (data.size() < kHeaderSize || !StartsWithSyncWord(data)) {
    return std::nullopt;
  }
  // bsid is the sixth byte's top five bits in both syncframes.
  const uint8_t bsid = data[5] >> 3;
  BitReader reader(data.first(kHeaderSize));
  Syncframe frame;
  uint8_t fscod;
  if (bsid <= 8) {
    // AC-3 syncinfo() and bsi() up to lfeon. In an E-AC-3 stream, the AC-3
    // core that independent substream 0 may be (ETSI TS 102 366 annex E).
    uint8_t frmsizecod;
    if (!reader.SkipBits(32) || !reader.ReadBits(2, &fscod) ||
        !reader.ReadBits(6, &frmsizecod) || !reader.SkipBits(5 + 3) ||
        !reader.ReadBits(3, &frame.acmod)) {
      return std::nullopt;
    }
    if (fscod >= kSampleRates.size() || frmsizecod >= 2 * kBitRates.size()) {
      return std::nullopt;
    }
    const int bit_rate = kBitRates[frmsizecod / 2];
    frame.sample_rate = kSampleRates[fscod];
    // Table 4.13's 16-bit words per syncframe: 2, 320/147 (rounded down, one
    // more for odd codes) or 3 per kbit/s at 48, 44.1 and 32 kHz.
    frame.size = 2 * (fscod == 0   ? 2 * bit_rate
                      : fscod == 1 ? bit_rate * 320 / 147 + (frmsizecod & 1)
                                   : 3 * bit_rate);
    frame.sample_count = 6 * 256;
    const bool cmixlev = (frame.acmod & 1) && frame.acmod != 1;
    const bool surmixlev = frame.acmod & 4;
    const bool dsurmod = frame.acmod == 2;
    if (!reader.SkipBits(2 * (cmixlev + surmixlev + dsurmod)) ||
        !reader.ReadBits(1, &frame.lfeon)) {
      return std::nullopt;
    }
    return frame;
  }
  if (!eac3_ || bsid < 11 || bsid > 16) {
    return std::nullopt;
  }
  // E-AC-3 bsi() up to chanmap.
  uint8_t strmtyp, substreamid, numblkscod;
  uint16_t frmsiz;
  if (!reader.SkipBits(16) || !reader.ReadBits(2, &strmtyp) ||
      !reader.ReadBits(3, &substreamid) || !reader.ReadBits(11, &frmsiz) ||
      !reader.ReadBits(2, &fscod) || !reader.ReadBits(2, &numblkscod) ||
      !reader.ReadBits(3, &frame.acmod) || !reader.ReadBits(1, &frame.lfeon) ||
      !reader.SkipBits(5)) {
    return std::nullopt;
  }
  if (strmtyp == 3) {
    return std::nullopt;
  }
  if (fscod == 3) {
    // numblkscod is fscod2, the reduced rates of six-block syncframes.
    if (numblkscod >= kReducedSampleRates.size()) {
      return std::nullopt;
    }
    frame.sample_rate = kReducedSampleRates[numblkscod];
    numblkscod = 3;
  } else {
    frame.sample_rate = kSampleRates[fscod];
  }
  frame.size = 2 * (frmsiz + 1u);
  if (frame.size < kHeaderSize) {
    return std::nullopt;
  }
  frame.sample_count = 256 * kBlocksPerSyncframe[numblkscod];
  frame.starts_access_unit = strmtyp != 1 && substreamid == 0;
  if (strmtyp != 1) {
    return frame;
  }
  bool compre, chanmape;
  if (!reader.SkipBits(5) || !reader.ReadFlag(&compre) ||
      !reader.SkipBits(compre ? 8 : 0)) {
    return std::nullopt;
  }
  if (frame.acmod == 0) {
    bool compr2e;
    if (!reader.SkipBits(5) || !reader.ReadFlag(&compr2e) ||
        !reader.SkipBits(compr2e ? 8 : 0)) {
      return std::nullopt;
    }
  }
  if (!reader.ReadFlag(&chanmape)) {
    return std::nullopt;
  }
  uint16_t chanmap = 0;
  if (chanmape && !reader.ReadBits(16, &chanmap)) {
    return std::nullopt;
  }
  // chan_loc's bits 0 to 7 are chanmap's 5 to 12 and its bit 8 (LFE2) is
  // chanmap's 14, chanmap counting from its first (most significant) bit
  // (ETSI TS 102 366 table E.1.4 and F.6.2.13); chan_loc has no Lts/Rts.
  for (int bit = 0; bit < 8; ++bit) {
    if (chanmap & (0x8000 >> (bit + 5))) {
      frame.chan_loc |= 1 << bit;
    }
  }
  if (chanmap & (0x8000 >> 14)) {
    frame.chan_loc |= EC3DependentSubstreamChannelLocation::LFE2;
  }
  return frame;
}

bool ParcEsParserAc3::ParseFromEsQueue() {
  while (true) {
    base::span<const uint8_t> es = es_queue_->Data();
    size_t offset = 0;
    std::optional<Syncframe> first;
    for (; offset + kHeaderSize <= es.size(); ++offset) {
      first = ReadSyncframe(es.subspan(offset));
      if (first && first->starts_access_unit) {
        break;
      }
      first.reset();
    }
    es_queue_->Pop(base::checked_cast<int>(offset));
    if (!first) {
      return true;
    }
    es = es_queue_->Data();
    if (es.size() < first->size) {
      // Resumes when the rest of the syncframe arrives.
      return true;
    }

    size_t access_unit_size = first->size;
    std::vector<Syncframe> dependents;
    while (std::optional<Syncframe> next =
               ReadSyncframe(es.subspan(access_unit_size))) {
      if (next->starts_access_unit) {
        break;
      }
      if (es.size() < access_unit_size + next->size) {
        return true;
      }
      dependents.push_back(*next);
      access_unit_size += next->size;
    }
    // An E-AC-3 access unit may go on in syncframes whose header hasn't
    // arrived. PES packets reach this parser whole, so the queue ending with
    // the syncframe ends the access unit.
    if (eac3_ && access_unit_size < es.size() &&
        es.size() < access_unit_size + kHeaderSize) {
      return true;
    }
    // As EsParserMpeg1Audio: a sync word not followed by another one where
    // its syncframe ends was payload that looked like one.
    if (access_unit_size + 2 <= es.size() &&
        !StartsWithSyncWord(es.subspan(access_unit_size))) {
      LIMITED_MEDIA_LOG(DEBUG, media_log_, parse_error_limit_, 5)
          << "Invalid AC-3 syncframe";
      es_queue_->Pop(1);
      continue;
    }

    if (!UpdateAudioConfiguration(*first, dependents)) {
      return false;
    }

    const TimingDesc timing = GetTimingDescriptor(es_queue_->head());
    if (timing.pts != kNoTimestamp) {
      audio_timestamp_helper_->SetBaseTimestamp(timing.pts);
    }
    if (audio_timestamp_helper_->base_timestamp()) {
      scoped_refptr<StreamParserBuffer> buffer = StreamParserBuffer::CopyFrom(
          es.first(access_unit_size), /*is_key_frame=*/true,
          DemuxerStream::AUDIO, kMp2tAudioTrackId);
      buffer->set_timestamp(audio_timestamp_helper_->GetTimestamp());
      buffer->set_duration(
          audio_timestamp_helper_->GetFrameDuration(first->sample_count));
      emit_buffer_cb_.Run(buffer);
      audio_timestamp_helper_->AddFrames(first->sample_count);
    } else {
      DVLOG(1) << "Skipping AC-3 access unit with unknown timestamp";
    }
    es_queue_->Pop(base::checked_cast<int>(access_unit_size));
  }
}

bool ParcEsParserAc3::UpdateAudioConfiguration(
    const Syncframe& first,
    const std::vector<Syncframe>& dependents) {
  ChannelLayout channel_layout =
      kAC3AudioCodingModeTable[first.lfeon][first.acmod];
  // As mp4::EAC3::Parse() reads the same locations from 'dec3'.
  uint16_t chan_loc = 0;
  for (const Syncframe& dependent : dependents) {
    chan_loc |= dependent.chan_loc;
  }
  if (first.acmod == kAC3AudioCodingModeSize - 1) {
    if (chan_loc == EC3DependentSubstreamChannelLocation::LRS_RRS) {
      channel_layout =
          first.lfeon == 0 ? CHANNEL_LAYOUT_7_0 : CHANNEL_LAYOUT_7_1;
    } else if (chan_loc == EC3DependentSubstreamChannelLocation::LC_RC) {
      channel_layout =
          first.lfeon == 0 ? CHANNEL_LAYOUT_7_0_FRONT : CHANNEL_LAYOUT_7_1_WIDE;
    } else if (chan_loc == EC3DependentSubstreamChannelLocation::CS) {
      channel_layout =
          first.lfeon == 0 ? CHANNEL_LAYOUT_6_0 : CHANNEL_LAYOUT_6_1;
    }
  }

  // As MP4StreamParser's 'ac-3' and 'ec-3' configurations.
  AudioDecoderConfig audio_decoder_config(
      eac3_ ? AudioCodec::kEAC3 : AudioCodec::kAC3, kSampleFormatS16,
      ChannelLayoutConfig::FromLayout(channel_layout), first.sample_rate,
      EmptyExtraData(), EncryptionScheme::kUnencrypted);
  if (!audio_decoder_config.IsValidConfig()) {
    DVLOG(1) << "Invalid config: "
             << audio_decoder_config.AsHumanReadableString();
    return false;
  }

  if (!audio_decoder_config.Matches(last_audio_decoder_config_)) {
    if (audio_timestamp_helper_ && audio_timestamp_helper_->base_timestamp()) {
      const base::TimeDelta base_timestamp =
          audio_timestamp_helper_->GetTimestamp();
      audio_timestamp_helper_ =
          std::make_unique<AudioTimestampHelper>(first.sample_rate);
      audio_timestamp_helper_->SetBaseTimestamp(base_timestamp);
    } else {
      audio_timestamp_helper_ =
          std::make_unique<AudioTimestampHelper>(first.sample_rate);
    }
    last_audio_decoder_config_ = audio_decoder_config;
    new_audio_config_cb_.Run(audio_decoder_config);
  }
  return true;
}

}  // namespace media::mp2t
