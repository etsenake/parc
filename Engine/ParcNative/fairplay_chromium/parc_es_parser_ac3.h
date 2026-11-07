// Installed by the reviewed overlay at
// //media/formats/mp2t/parc_es_parser_ac3.h (media, macOS). AC-3 (ATSC A/52
// stream type 0x81) and E-AC-3 (0x87) elementary streams in MPEG-2 TS, which
// Safari's Media Source parses through AVStreamDataParser; Mp2tStreamParser
// creates this parser only under Safari's identity
// (Mp2tStreamParser::ParcIgnoreDeclaredCodecs()).

#ifndef MEDIA_FORMATS_MP2T_PARC_ES_PARSER_AC3_H_
#define MEDIA_FORMATS_MP2T_PARC_ES_PARSER_AC3_H_

#include <stdint.h>

#include <memory>
#include <optional>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/callback.h"
#include "media/base/audio_decoder_config.h"
#include "media/base/media_export.h"
#include "media/base/media_log.h"
#include "media/formats/mp2t/es_parser.h"

namespace media {
class AudioTimestampHelper;
}

namespace media::mp2t {

// Emits each access unit as MP4StreamParser emits an 'ac-3' or 'ec-3'
// sample: one AC-3 syncframe, or an E-AC-3 independent substream 0 syncframe
// (or AC-3 core) with the syncframes that follow it up to the next one; key
// frames, clear, with no extra data.
class MEDIA_EXPORT ParcEsParserAc3 : public EsParser {
 public:
  using NewAudioConfigCB =
      base::RepeatingCallback<void(const AudioDecoderConfig&)>;

  ParcEsParserAc3(bool eac3,
                  const NewAudioConfigCB& new_audio_config_cb,
                  EmitBufferCB emit_buffer_cb,
                  MediaLog* media_log);

  ParcEsParserAc3(const ParcEsParserAc3&) = delete;
  ParcEsParserAc3& operator=(const ParcEsParserAc3&) = delete;

  ~ParcEsParserAc3() override;

  // EsParser implementation.
  void Flush() override;

 private:
  struct Syncframe {
    size_t size = 0;
    int sample_count = 0;
    int sample_rate = 0;
    uint8_t acmod = 0;
    uint8_t lfeon = 0;
    // Starts an access unit: every AC-3 syncframe, and an E-AC-3 independent
    // syncframe of substream 0.
    bool starts_access_unit = true;
    // E-AC-3 dependent substreams: their chanmap's locations beyond 5.1, in
    // the bit order of the 'dec3' box's chan_loc.
    uint16_t chan_loc = 0;
  };

  // EsParser implementation.
  bool ParseFromEsQueue() override;
  void ResetInternal() override;

  // The syncframe of this parser's codec that `data` starts with, if its
  // header reads as one.
  std::optional<Syncframe> ReadSyncframe(base::span<const uint8_t> data) const;

  // Signals the configuration of the access unit `first` starts, if it
  // changed. False if it isn't a valid configuration.
  bool UpdateAudioConfiguration(const Syncframe& first,
                                const std::vector<Syncframe>& dependents);

  bool flushing_ = false;
  const bool eac3_;
  const std::unique_ptr<MediaLog> media_log_;
  size_t parse_error_limit_ = 0;

  NewAudioConfigCB new_audio_config_cb_;
  EmitBufferCB emit_buffer_cb_;

  // Interpolated PTS for access units that don't have one.
  std::unique_ptr<AudioTimestampHelper> audio_timestamp_helper_;

  AudioDecoderConfig last_audio_decoder_config_;
};

}  // namespace media::mp2t

#endif  // MEDIA_FORMATS_MP2T_PARC_ES_PARSER_AC3_H_
