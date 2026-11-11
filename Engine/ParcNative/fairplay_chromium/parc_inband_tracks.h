// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at //media/base/parc_inband_tracks.h.
// The in-band tracks of Safari's native HLS route, which the native HLS
// demuxer reports through DemuxerManager and WebMediaPlayerImpl to the
// element. Kept out of media_track.h so that changing them rebuilds only what
// uses them; the struct members are defined in media_track.cc.
#ifndef MEDIA_BASE_PARC_INBAND_TRACKS_H_
#define MEDIA_BASE_PARC_INBAND_TRACKS_H_

#include <stdint.h>

#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/functional/callback.h"
#include "media/base/media_export.h"

namespace media {

// An in-band text track of Safari's native HLS route (macOS; the
// FairPlay core's HlsTrack, third_party/parc_fairplay NATIVE_HLS.md).
struct MEDIA_EXPORT ParcInbandTextTrack {
  ParcInbandTextTrack();
  ParcInbandTextTrack(const ParcInbandTextTrack&);
  ParcInbandTextTrack(ParcInbandTextTrack&&);
  ParcInbandTextTrack& operator=(const ParcInbandTextTrack&);
  ParcInbandTextTrack& operator=(ParcInbandTextTrack&&);
  ~ParcInbandTextTrack();

  // Unique for the player; names the track in mode changes and cues.
  std::string key;
  // TextTrack's id, kind ("subtitles", "captions" or "forced"), label and
  // language, as WebKit gives them.
  std::string id;
  std::string kind;
  std::string label;
  std::string language;
  // The in-band position (TextTrackList orders in-band tracks by it).
  int64_t index = 0;
  // What WebKit's caption preferences weigh.
  bool is_default = false;
  bool is_closed_captions = false;
  bool is_sdh = false;
  bool contains_only_forced_subtitles = false;
  bool is_main_program_content = false;
  bool is_easy_to_read = false;
  // The one track WebKit's automatic selection shows when none is showing
  // (the player scores them by the system caption settings): the element's
  // automatic selection shows it (ParcInbandTextTrack::IsDefault).
  bool automatic = false;
  // TextTrack.inBandMetadataTrackDispatchType: "com.apple.streaming" for the
  // metadata track, else "".
  std::string in_band_metadata_dispatch_type;
};

// A DataCue's value (the FairPlay core's HlsDataCueValue: what WebKit's
// SerializedPlatformDataCueValue keeps of a timed metadata item).
struct MEDIA_EXPORT ParcDataCueValue {
  ParcDataCueValue();
  ParcDataCueValue(const ParcDataCueValue&);
  ParcDataCueValue(ParcDataCueValue&&);
  ParcDataCueValue& operator=(const ParcDataCueValue&);
  ParcDataCueValue& operator=(ParcDataCueValue&&);
  ~ParcDataCueValue();
  bool operator==(const ParcDataCueValue&) const;

  enum class Kind { kNone, kString, kNumber, kBoolean, kData, kDate };
  // The value object's "type" (MIMEtype, or an IANA dataType).
  std::optional<std::string> type;
  // Its other attributes, lowercase names, by name.
  std::vector<std::pair<std::string, std::string>> attributes;
  std::optional<std::string> locale;
  std::optional<std::string> key;
  // Its "data": a string, number, boolean or ArrayBuffer; none for a date
  // (compared by its seconds since 1970) or no value.
  Kind kind = Kind::kNone;
  std::string string_value;
  double number_value = 0;
  std::vector<uint8_t> data;
};

// One change to the metadata track's DataCues (InbandDataTextTrack's
// addDataCue, updateDataCue and removeDataCue; the cue to update or remove
// is the open one with an equal value).
struct MEDIA_EXPORT ParcInbandDataCue {
  ParcInbandDataCue();
  ParcInbandDataCue(const ParcInbandDataCue&);
  ParcInbandDataCue(ParcInbandDataCue&&);
  ParcInbandDataCue& operator=(const ParcInbandDataCue&);
  ParcInbandDataCue& operator=(ParcInbandDataCue&&);
  ~ParcInbandDataCue();

  enum class Type { kAdd, kUpdate, kRemove };
  Type type = Type::kAdd;
  // Seconds; the end is +infinity while the cue is open.
  double start = 0;
  double end = 0;
  // DataCue.type; nullopt without one.
  std::optional<std::string> cue_type;
  ParcDataCueValue value;
};

// TextTrack.mode, for the native HLS player.
enum class ParcInbandTextTrackMode { kDisabled, kHidden, kShowing };

// One change to an in-band text track's cues (the core's HlsCue).
struct MEDIA_EXPORT ParcInbandTextCue {
  enum class Type {
    kWebVttHeader,  // `text`: the WebVTT header (regions, style sheets).
    kWebVtt,        // A WebVTT cue: WebVTTParser::parseCueData.
    kAdd,           // Generic cues, by `cue_id`: InbandGenericTextTrack's
    kUpdate,        // addGenericCue, updateGenericCue and removeGenericCue.
    kRemove,
  };
  enum class Align { kNone, kStart, kMiddle, kEnd };

  ParcInbandTextCue();
  ParcInbandTextCue(const ParcInbandTextCue&);
  ParcInbandTextCue(ParcInbandTextCue&&);
  ParcInbandTextCue& operator=(const ParcInbandTextCue&);
  ParcInbandTextCue& operator=(ParcInbandTextCue&&);
  ~ParcInbandTextCue();

  Type type = Type::kAdd;
  uint64_t cue_id = 0;
  // Seconds. A generic cue's end is +infinity while it is open; a WebVTT
  // cue's is NaN when its sample has no duration.
  double start = 0;
  double end = 0;
  bool complete = false;
  std::string text;
  // WebVTT iden, sttg, vsid and ctim boxes.
  std::string identifier;
  std::string settings;
  std::string source_id;
  std::string original_start_time;
  // Generic cue layout; -1 when unset.
  double line = -1;
  double position = -1;
  double size = -1;
  double base_font_size = 0;
  double relative_font_size = 0;
  std::string font_name;
  Align align = Align::kNone;
  Align position_align = Align::kNone;
  // 0xRRGGBBAA.
  std::optional<uint32_t> foreground_color;
  std::optional<uint32_t> background_color;
  std::optional<uint32_t> highlight_color;
  bool prevent_line_wrapping = true;
};

// Tells the native HLS player a track's mode. Callable on the main
// thread; it posts to the player's thread and does nothing once it is gone.
using ParcInbandTextTrackModeCB =
    base::RepeatingCallback<void(const std::string& key,
                                 ParcInbandTextTrackMode mode)>;

// An audio track of Safari's native HLS route (the FairPlay core's
// HlsTrack), with the values WebKit gives the DOM.
struct MEDIA_EXPORT ParcInbandAudioTrack {
  ParcInbandAudioTrack();
  ParcInbandAudioTrack(const ParcInbandAudioTrack&);
  ParcInbandAudioTrack(ParcInbandAudioTrack&&);
  ParcInbandAudioTrack& operator=(const ParcInbandAudioTrack&);
  ParcInbandAudioTrack& operator=(ParcInbandAudioTrack&&);
  ~ParcInbandAudioTrack();

  // Unique for the player; names the track in enable calls.
  std::string key;
  // AudioTrack's id (can repeat, as in Safari), kind ("main", "alternative",
  // "description" or ""), label, language and enabled state.
  std::string id;
  std::string kind;
  std::string label;
  std::string language;
  bool enabled = false;
};

// Tells the native HLS player a page set AudioTrack.enabled; as
// ParcInbandTextTrackModeCB.
using ParcInbandAudioTrackEnabledCB =
    base::RepeatingCallback<void(const std::string& key, bool enabled)>;

// Where the in-band track calls go: DemuxerManager::Client
// (WebMediaPlayerImpl) and blink::MediaPlayerClient (the element). Each is
// ignored unless overridden.
class ParcInbandTrackSink {
 public:
  // The whole list of in-band text tracks, replacing the previous one (tracks
  // matched by key), with the way back to the player for their modes.
  virtual void ParcSetInbandTextTracks(
      const std::vector<ParcInbandTextTrack>& tracks,
      ParcInbandTextTrackModeCB set_mode) {}
  // Changes to one in-band text track's cues, in order.
  virtual void ParcAddInbandTextCues(
      const std::string& key,
      const std::vector<ParcInbandTextCue>& cues) {}
  // Changes to the metadata track's DataCues, in order.
  virtual void ParcAddInbandDataCues(
      const std::string& key,
      const std::vector<ParcInbandDataCue>& cues) {}
  // The whole list of the route's audio tracks, in DOM order, replacing the
  // previous one (matched by key), with the way back to the player for the
  // page's enable changes.
  virtual void ParcSetInbandAudioTracks(
      const std::vector<ParcInbandAudioTrack>& tracks,
      ParcInbandAudioTrackEnabledCB set_enabled) {}

 protected:
  virtual ~ParcInbandTrackSink() = default;
};

// The native HLS demuxer's sink: runs the callbacks DemuxerManager gives it,
// as ForwardingTrackManager does for Chromium's track calls.
class MEDIA_EXPORT ParcInbandTrackForwarder final : public ParcInbandTrackSink {
 public:
  ParcInbandTrackForwarder(
      base::RepeatingCallback<void(const std::vector<ParcInbandTextTrack>&,
                                   ParcInbandTextTrackModeCB)> set_tracks,
      base::RepeatingCallback<void(const std::string&,
                                   const std::vector<ParcInbandTextCue>&)>
          add_cues,
      base::RepeatingCallback<void(const std::string&,
                                   const std::vector<ParcInbandDataCue>&)>
          add_data_cues,
      base::RepeatingCallback<void(const std::vector<ParcInbandAudioTrack>&,
                                   ParcInbandAudioTrackEnabledCB)>
          set_audio_tracks);
  ParcInbandTrackForwarder(const ParcInbandTrackForwarder&) = delete;
  ParcInbandTrackForwarder& operator=(const ParcInbandTrackForwarder&) = delete;
  ~ParcInbandTrackForwarder() override;

  void ParcSetInbandTextTracks(const std::vector<ParcInbandTextTrack>& tracks,
                               ParcInbandTextTrackModeCB set_mode) override;
  void ParcAddInbandTextCues(
      const std::string& key,
      const std::vector<ParcInbandTextCue>& cues) override;
  void ParcAddInbandDataCues(
      const std::string& key,
      const std::vector<ParcInbandDataCue>& cues) override;
  void ParcSetInbandAudioTracks(
      const std::vector<ParcInbandAudioTrack>& tracks,
      ParcInbandAudioTrackEnabledCB set_enabled) override;

 private:
  const base::RepeatingCallback<void(const std::vector<ParcInbandTextTrack>&,
                                     ParcInbandTextTrackModeCB)>
      set_tracks_;
  const base::RepeatingCallback<void(const std::string&,
                                     const std::vector<ParcInbandTextCue>&)>
      add_cues_;
  const base::RepeatingCallback<void(const std::string&,
                                     const std::vector<ParcInbandDataCue>&)>
      add_data_cues_;
  const base::RepeatingCallback<void(const std::vector<ParcInbandAudioTrack>&,
                                     ParcInbandAudioTrackEnabledCB)>
      set_audio_tracks_;
};

}  // namespace media

#endif  // MEDIA_BASE_PARC_INBAND_TRACKS_H_
