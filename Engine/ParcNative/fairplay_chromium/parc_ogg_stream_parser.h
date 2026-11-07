// Installed by the reviewed overlay at
// //media/formats/ogg/parc_ogg_stream_parser.h (media). Media Source parser
// for Ogg audio (Opus, Vorbis, FLAC), which Safari's Media Source parses
// through AVStreamDataParser and Chromium's has none for. Only
// Safari-identity pages create it (StreamParserFactory::ParcCreateOggParser()).

#ifndef MEDIA_FORMATS_OGG_PARC_OGG_STREAM_PARSER_H_
#define MEDIA_FORMATS_OGG_PARC_OGG_STREAM_PARSER_H_

#include <stdint.h>

#include <memory>
#include <optional>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/callback.h"
#include "media/base/audio_codecs.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/audio_timestamp_helper.h"
#include "media/base/byte_queue.h"
#include "media/base/media_export.h"
#include "media/base/stream_parser.h"

namespace media {

// Follows AVStreamDataParser, as Safari's Media Source does: the first Opus,
// Vorbis or FLAC logical stream is the one audio track and other streams are
// ignored; samples are stamped by counting packet durations from 0 for the
// parser's life, not from granule positions; a chained stream's next link is
// a new init segment on the same timeline.
class MEDIA_EXPORT ParcOggStreamParser : public StreamParser {
 public:
  ParcOggStreamParser();
  ParcOggStreamParser(const ParcOggStreamParser&) = delete;
  ParcOggStreamParser& operator=(const ParcOggStreamParser&) = delete;
  ~ParcOggStreamParser() override;

  // StreamParser implementation.
  void Init(InitCB init_cb,
            NewConfigCB config_cb,
            NewBuffersCB new_buffers_cb,
            EncryptedMediaInitDataCB encrypted_media_init_data_cb,
            NewMediaSegmentCB new_segment_cb,
            EndMediaSegmentCB end_of_segment_cb,
            MediaLog* media_log) override;
  void Flush() override;
  bool GetGenerateTimestampsFlag() const override;
  [[nodiscard]] bool AppendToParseBuffer(
      base::span<const uint8_t> buf) override;
  [[nodiscard]] ParseStatus Parse(int max_pending_bytes_to_inspect) override;

 private:
  struct Page;

  // Returns the bytes consumed from `data`, 0 when more are needed, or -1 on
  // error.
  int ParsePage(base::span<const uint8_t> data);
  bool OnPage(const Page& page);
  bool OnPacket(std::vector<uint8_t> packet);
  bool OnHeaderPacket(base::span<const uint8_t> packet);
  bool OnIdentificationHeader(base::span<const uint8_t> packet);
  bool OnVorbisSetupHeader(base::span<const uint8_t> packet);
  bool EmitConfig();
  // Samples `packet` decodes to, or nullopt if it isn't a valid packet.
  std::optional<int> PacketFrames(base::span<const uint8_t> packet);
  std::optional<int> VorbisPacketFrames(base::span<const uint8_t> packet);
  bool SendBuffers();
  void ResetLogicalStream();

  InitCB init_cb_;
  NewConfigCB config_cb_;
  NewBuffersCB new_buffers_cb_;
  NewMediaSegmentCB new_segment_cb_;
  EndMediaSegmentCB end_of_segment_cb_;
  std::unique_ptr<MediaLog> media_log_;
  bool failed_ = false;

  ByteQueue queue_;
  int uninspected_pending_bytes_ = 0;

  // The logical stream that is the track, once its first page is seen.
  std::optional<uint32_t> serial_;
  bool stream_ended_ = false;
  std::optional<uint32_t> last_page_sequence_;
  std::vector<uint8_t> partial_packet_;

  AudioCodec codec_ = AudioCodec::kUnknown;
  std::vector<std::vector<uint8_t>> headers_;
  bool headers_complete_ = false;
  int channels_ = 0;
  int sample_rate_ = 0;
  int bits_per_sample_ = 0;
  int pre_skip_ = 0;
  // Vorbis block sizes, each mode's block flag, and the last block's size
  // (libavcodec's vorbis_parser.c, which gives AVStreamDataParser's
  // durations).
  int vorbis_block_sizes_[2] = {0, 0};
  std::vector<bool> vorbis_mode_long_;
  int vorbis_previous_block_size_ = 0;

  AudioDecoderConfig config_;
  std::unique_ptr<AudioTimestampHelper> timestamp_helper_;
  BufferQueue buffers_;
  bool in_media_segment_ = false;
};

}  // namespace media

#endif  // MEDIA_FORMATS_OGG_PARC_OGG_STREAM_PARSER_H_
