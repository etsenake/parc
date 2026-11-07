// Native HLS audio and text tracks, exactly as Safari's AVFoundation player
// exposes them (fairplay_chromium/NATIVE_HLS.md). A port of WebKit's
// MediaPlayerPrivateAVFoundationObjC track code (tracksChanged,
// updateAudioTracks, processMediaSelectionOptions, setCurrentTextTrack, the
// legible output), MediaPlayerPrivateAVFoundation::configureInbandTracks,
// MediaSelectionGroupAVFObjC, AVTrackPrivateAVFObjCImpl,
// AudioTrackPrivateAVFObjC, InbandTextTrackPrivateAVFObjC and
// InbandTextTrackPrivateAVF.
//
// audioTracks come from the asset's audible media selection group (or, with
// none, the item's audio tracks); enabling one selects its option in the
// AVPlayerItem. textTracks come from the legible group: WebVTT subtitles,
// CEA-608/708 closed captions and other legible options. Their cues arrive
// through one AVPlayerItemLegibleOutput, for the one track whose mode picks
// it, as WebKit delivers them to InbandGenericTextTrack: WebVTT samples as
// ISO WebVTT cue boxes (HlsCue::Type::kWebVtt, which the page side parses as
// WebVTTParser::parseCueData does) and every other format as generic cues
// that are added open-ended and completed when the next one arrives.
//
// Engine-independent like the rest of the core: plain C++ header, ObjC++
// implementation. The player attaches its AVPlayer and item through
// fairplay_hls_media_selection_internal.h.
#pragma once

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "fairplay_types.h"

namespace parc::fairplay {

enum class HlsTrackType { kAudio, kText };

// TextTrack.mode (InbandTextTrackPrivate::Mode).
enum class HlsTextTrackMode { kDisabled, kHidden, kShowing };

// One audioTracks or textTracks entry with the values WebKit gives the DOM.
struct HlsTrack {
  HlsTrackType type = HlsTrackType::kAudio;
  // Unique and fixed for the track's life: what SetAudioTrackEnabled,
  // SetTextTrackMode and OnTextCues name. Not web-visible.
  std::string key;
  // The DOM id. Audio: the asset track's trackID when WebKit has one for the
  // option (the option AVFoundation had selected when the track was made),
  // else AVFoundation's option ID; the two can collide, and then Safari
  // shows two tracks with one id. Text: WebKit's running text track number,
  // from 0 in order of discovery.
  std::string id;
  // WebKit's kind keyword. Audio: "main", "alternative", "description" (sic,
  // WebKit's AudioTrack keyword) or "". Text: "subtitles", "captions" or
  // "forced" (WebKit's TextTrackKind has "forced").
  std::string kind;
  std::string label;     // The common metadata title in the user's languages.
  std::string language;  // extendedLanguageTag; "" for none or "und".
  // Audio only: AudioTrack.enabled.
  bool enabled = false;
  // TrackPrivateBase::trackIndex (an int): audio, its asset track's index
  // in the asset's tracks (-1 for an HLS streaming track) or else the
  // option's index in its group; text, the in-band index. The DOM lists
  // order by it, -1 last (AudioTrackList::append compares it as size_t;
  // TextTrackList::append); tracks are reported in that order.
  int64_t index = 0;
  // Text only, what HTMLMediaElement's caption preferences weigh
  // (InbandTextTrackPrivateAVFObjC).
  bool is_default = false;          // The legible group's defaultOption.
  bool is_closed_captions = false;  // AVMediaTypeClosedCaption (CEA-608/708).
  bool is_sdh = false;
  bool contains_only_forced_subtitles = false;
  bool is_main_program_content = false;
  bool is_easy_to_read = false;
  // Text only: the one track WebKit's automatic selection shows when none
  // is showing (HTMLMediaElement::configureTextTrackGroup scored by
  // CaptionUserPreferencesMediaAF from the system caption settings: display
  // mode, caption languages, SDH preference) for the enabled audio track.
  bool automatic = false;
  // Text only: TextTrack.inBandMetadataTrackDispatchType, "com.apple.streaming"
  // for the metadata track (InbandMetadataTextTrackPrivateAVF), else "".
  std::string in_band_metadata_dispatch_type;

  bool operator==(const HlsTrack&) const = default;
};

// GenericCueData::Alignment.
enum class HlsCueAlign { kNone, kStart, kMiddle, kEnd };

// One change to a text track's cues, in delivery order.
struct HlsCue {
  enum class Type {
    // The WebVTT file header (the sample description's vttC box plus two
    // line feeds, its bytes read as Latin-1, as WebKit does): the page side
    // parses it for regions and style sheets (parseWebVTTFileHeader).
    kWebVttHeader,
    // A WebVTT cue (ISOWebVTTCue): parsed on the page side as
    // WebVTTParser::parseCueData, then deduplicated or extended as
    // InbandGenericTextTrack::newCuesParsed.
    kWebVtt,
    // A generic cue (InbandGenericTextTrack::addGenericCue): start, end
    // (+infinity while open: the DOM cue ends at the media duration then),
    // text and layout below.
    kAdd,
    // A generic cue's new end time and completion (updateGenericCue).
    kUpdate,
    // A generic cue flushed by a seek or the output (removeGenericCue).
    kRemove,
  };
  Type type = Type::kAdd;
  // Generic cues: the cue's unique identifier (InbandGenericCueIdentifier).
  uint64_t cue_id = 0;
  double start = 0;  // Seconds.
  // Seconds; +infinity for an open generic cue. WebVTT: start plus the
  // sample's duration (NaN when the sample has none).
  double end = 0;
  bool complete = false;  // Generic: GenericCueData::Status::Complete.
  // Header: the header text. WebVTT: the payl box (cue text). Generic: the
  // content with <b>, <i> and <u> spans and direction marks, unescaped.
  std::string text;

  // WebVTT boxes: iden, sttg, vsid, ctim.
  std::string identifier;
  std::string settings;
  std::string source_id;
  std::string original_start_time;

  // Generic cue layout, -1 when unset (InbandGenericCue). Position is
  // already moved from AVFoundation's text centre by size / 2 as WebKit does.
  double line = -1;
  double position = -1;
  double size = -1;
  double base_font_size = 0;      // Percent of the video height.
  double relative_font_size = 0;  // Percent.
  std::string font_name;
  HlsCueAlign align = HlsCueAlign::kNone;
  HlsCueAlign position_align = HlsCueAlign::kNone;
  // 0xRRGGBBAA, as WebKit's SRGBA<uint8_t>.
  std::optional<uint32_t> foreground_color;
  std::optional<uint32_t> background_color;
  std::optional<uint32_t> highlight_color;
  bool prevent_line_wrapping = true;
};

// What a DataCue's value carries of a timed metadata item
// (SerializedPlatformDataCueValue): the page sees an object with "type",
// the other attributes, "locale", "key" and "data" (a string, number,
// boolean or ArrayBuffer; none for a date or no value).
struct HlsDataCueValue {
  std::optional<std::string> type;  // MIMEtype, or an IANA media-type dataType.
  // The item's other non-empty string extra attributes, keys lowercased.
  std::map<std::string, std::string> attributes;
  std::optional<std::string> locale;  // The item's locale identifier.
  std::optional<std::string> key;     // The item's key, when it is a string.
  enum class Kind { kNone, kString, kNumber, kBoolean, kData, kDate };
  Kind kind = Kind::kNone;
  std::string string_value;
  // kNumber, kBoolean (0 or 1), kDate (seconds since 1970; compared only).
  double number_value = 0;
  std::vector<uint8_t> data;

  bool operator==(const HlsDataCueValue&) const = default;
};

// One change to the metadata track's DataCues, in delivery order
// (InbandTextTrackPrivateClient's addDataCue, updateDataCue, removeDataCue):
// the page side finds the cue to update or remove by an open cue with an
// equal value, as InbandDataTextTrack does.
struct HlsDataCue {
  enum class Type { kAdd, kUpdate, kRemove };
  Type type = Type::kAdd;
  double start = 0;  // Seconds.
  double end = 0;    // Seconds; +infinity while open.
  // DataCue.type: the item's key space as WebKit names it ("org.id3",
  // "com.apple.quicktime.HLS"…), "" for another, nullopt without one.
  std::optional<std::string> cue_type;
  HlsDataCueValue value;
};

// Posted to the owner sequence, never inside a call into the selection.
class HlsMediaSelectionClient {
 public:
  // The whole list after any change: audio tracks then text tracks, each in
  // DOM order. Additions, removals and property changes are the difference
  // from the previous list (tracks match by key).
  virtual void OnTracksChanged(const std::vector<HlsTrack>& tracks) = 0;
  virtual void OnTextCues(const std::string& track_key, const std::vector<HlsCue>& cues) = 0;
  // Timed and date range metadata, as DataCue changes on the metadata track.
  virtual void OnDataCues(const std::string& track_key, const std::vector<HlsDataCue>& cues) {}

 protected:
  virtual ~HlsMediaSelectionClient() = default;
};

class HlsMediaSelection {
 public:
  // |client| must outlive the selection. Every method runs on one owner
  // sequence (the player's); |post_task| reaches it from any thread.
  HlsMediaSelection(HlsMediaSelectionClient* client, PostTask post_task);
  ~HlsMediaSelection();

  HlsMediaSelection(const HlsMediaSelection&) = delete;
  HlsMediaSelection& operator=(const HlsMediaSelection&) = delete;

  // AudioTrack.enabled, set by the page. Selects the track's option in the
  // audible group (or enables the item track); disabling the selected option
  // selects none. Stops WebKit's automatic choice for good.
  void SetAudioTrackEnabled(const std::string& key, bool enabled);
  // TextTrack.mode, set by the page or the element's automatic selection.
  // The legible output serves the first showing track, else the last hidden
  // one, else none (configureInbandTracks).
  void SetTextTrackMode(const std::string& key, HlsTextTrackMode mode);

  // The player calls these around seeks: BeginSeeking when a seek starts,
  // EndSeeking when the last pending seek finishes. Open generic cues are
  // flushed, and cues delivered meanwhile never get an end from the next one.
  void BeginSeeking();
  void EndSeeking();

  // The current list, as last reported.
  std::vector<HlsTrack> Tracks() const;

  class Impl;
  // For fairplay_hls_media_selection_internal.h.
  Impl* impl() const { return impl_.get(); }

 private:
  std::shared_ptr<Impl> impl_;
};

}  // namespace parc::fairplay
