// Installed by the reviewed overlay at
// //media/formats/mp2t/parc_es_parser_mpeg_video.h (media). MPEG-1 video
// (ISO/IEC 11172-2, stream type 0x01) and MPEG-2 video (ISO/IEC 13818-2,
// 0x02) elementary streams in MPEG-2 TS, which Safari's Media Source parses
// through AVStreamDataParser; Mp2tStreamParser creates this parser only
// under Safari's identity (Mp2tStreamParser::ParcIgnoreDeclaredCodecs()).

#ifndef MEDIA_FORMATS_MP2T_PARC_ES_PARSER_MPEG_VIDEO_H_
#define MEDIA_FORMATS_MP2T_PARC_ES_PARSER_MPEG_VIDEO_H_

#include <stdint.h>

#include <optional>
#include <utility>
#include <vector>

#include "base/containers/span.h"
#include "base/memory/scoped_refptr.h"
#include "base/time/time.h"
#include "media/base/media_export.h"
#include "media/base/stream_parser_buffer.h"
#include "media/base/video_decoder_config.h"
#include "media/formats/mp2t/es_adapter_video.h"
#include "media/formats/mp2t/es_parser.h"

namespace media::mp2t {

// Emits each coded frame as AVStreamDataParser gives Safari's SourceBuffer
// a sample: from the sequence, GOP or picture header that precedes its
// picture (both fields of a field pair) up to the next one. Only an I-picture
// after a closed GOP's header is a key frame. The configuration is
// VideoCodec::kMPEG2 for both MPEG-1 and MPEG-2, with the sequence header and
// its extensions as extra data; VideoToolbox decodes it in the GPU process
// (ParcVideoToolboxMpegVideoDecoder).
class MEDIA_EXPORT ParcEsParserMpegVideo : public EsParser {
 public:
  ParcEsParserMpegVideo(EsAdapterVideo::NewVideoConfigCB new_video_config_cb,
                        EsAdapterVideo::EmitBufferCB emit_buffer_cb);

  ParcEsParserMpegVideo(const ParcEsParserMpegVideo&) = delete;
  ParcEsParserMpegVideo& operator=(const ParcEsParserMpegVideo&) = delete;

  ~ParcEsParserMpegVideo() override;

  // EsParser implementation.
  void Flush() override;

 private:
  // The fields of the latest sequence header and extension.
  struct Sequence {
    uint32_t width = 0;
    uint32_t height = 0;
    bool mpeg2 = false;
    uint32_t aspect_ratio_information = 0;
    uint32_t frame_rate_code = 0;
    uint32_t frame_rate_extension_n = 0;
    uint32_t frame_rate_extension_d = 0;
  };

  // EsParser implementation.
  bool ParseFromEsQueue() override;
  void ResetInternal() override;

  // Reads the start code at `pos` and the header after it, up to `end`.
  bool ReadUnit(int64_t pos, int64_t end);

  // Emits the access unit that runs up to `end`.
  bool EmitAccessUnit(int64_t end);

  // Reads temporal_reference and picture_coding_type of the picture header
  // at `pos`.
  bool ReadPictureHeader(int64_t pos);

  // Passes on the pictures waiting in `untimed_`.
  bool EmitUntimed();

  // Signals the configuration of `sequence_` with `sequence_headers` as extra
  // data, if it changed.
  bool UpdateVideoDecoderConfig(base::span<const uint8_t> sequence_headers);

  // The start code after `pos`, searching onward from `search_pos_`.
  std::optional<int64_t> FindStartCode(int64_t pos);

  EsAdapterVideo es_adapter_;
  bool flushing_ = false;

  // The start code of the unit being read, and where to look for the next.
  int64_t unit_pos_ = -1;
  int64_t search_pos_ = 0;

  // The access unit being assembled: where it starts, where its sequence
  // header and the headers after it start and end, its first and last
  // picture, and how many fields its pictures hold (a frame picture holds
  // two).
  int64_t access_unit_pos_ = -1;
  int64_t sequence_pos_ = -1;
  int64_t sequence_end_pos_ = -1;
  int64_t picture_pos_ = -1;
  int64_t last_picture_pos_ = -1;
  int fields_ = 0;
  bool closed_gop_ = false;
  bool has_gop_header_ = false;
  uint32_t temporal_reference_ = 0;
  uint32_t picture_coding_type_ = 0;

  std::optional<Sequence> sequence_;
  // The latest sequence header and the extensions and user data after it,
  // the configuration's extra data, and whether the next access unit
  // signals them.
  std::vector<uint8_t> sequence_headers_;
  bool sequence_changed_ = false;

  // Timestamps for pictures their PES packet leaves without one, as
  // AVStreamDataParser derives them: decode times a frame apart, and
  // presentation times by temporal_reference from the first picture of the
  // GOP.
  base::TimeDelta gop_pts_ = kNoTimestamp;
  int max_temporal_reference_ = -1;
  DecodeTimestamp last_dts_ = kNoDecodeTimestamp;
  // Pictures before the first timestamp, with their temporal_reference,
  // timed from the first timestamp of their GOP once it comes.
  std::vector<std::pair<scoped_refptr<StreamParserBuffer>, uint32_t>>
      untimed_;

  VideoDecoderConfig last_video_decoder_config_;
};

}  // namespace media::mp2t

#endif  // MEDIA_FORMATS_MP2T_PARC_ES_PARSER_MPEG_VIDEO_H_
