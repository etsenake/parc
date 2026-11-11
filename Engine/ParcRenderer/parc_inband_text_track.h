// Copyright 2026 Parc contributors.
// An in-band text track of Safari's native HLS route on a Safari-identity
// document (third_party/parc_fairplay NATIVE_HLS.md, Tracks). M156 Blink
// creates no in-band text tracks; this is WebKit's InbandTextTrack and
// InbandGenericTextTrack for the tracks AVFoundation's legible group offers:
// the player's track appears in the element's textTracks as an in-band track,
// its mode goes back to the player, and its cues are made as WebKit makes
// them (WebVTT cues parsed from the ISO boxes, generic cues added open-ended
// and then updated or removed).
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_INBAND_TEXT_TRACK_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_INBAND_TEXT_TRACK_H_

#include <stdint.h>

#include <optional>
#include <string>
#include <vector>

#include "media/base/parc_inband_tracks.h"
#include "third_party/blink/renderer/core/core_export.h"
#include "third_party/blink/renderer/core/html/track/text_track.h"
#include "third_party/blink/renderer/core/html/track/vtt/vtt_cue.h"
#include "third_party/blink/renderer/core/html/track/vtt/vtt_parser.h"
#include "third_party/blink/renderer/platform/heap/collection_support/heap_hash_map.h"
#include "third_party/blink/renderer/platform/heap/garbage_collected.h"
#include "third_party/blink/renderer/platform/heap/member.h"
#include "third_party/blink/renderer/platform/wtf/casting.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"

namespace blink {

class DataCue;
class HTMLMediaElement;
class TextTrackCue;

class CORE_EXPORT ParcInbandTextTrack final : public TextTrack,
                                              public VTTParserClient {
 public:
  ParcInbandTextTrack(const media::ParcInbandTextTrack& info,
                      HTMLMediaElement& element,
                      media::ParcInbandTextTrackModeCB set_mode);
  ~ParcInbandTextTrack() override;

  const std::string& Key() const { return info_.key; }
  // The player's latest description: what WebKit's caption preferences weigh.
  const media::ParcInbandTextTrack& Info() const { return info_; }

  // A newer description of the same track (WebKit's InbandTextTrack follows
  // its private track's id, kind, label and language).
  void Update(const media::ParcInbandTextTrack& info);
  void SetModeCallback(media::ParcInbandTextTrackModeCB set_mode);

  // Changes to the cues, in order.
  void AddCues(const std::vector<media::ParcInbandTextCue>& cues);
  // Changes to the metadata track's DataCues, in order (WebKit's
  // InbandDataTextTrack: an add equal to an open cue or to a cue at the same
  // start is dropped, an open cue ends at the duration, updates and removals
  // find the open cue by its value).
  void AddDataCues(const std::vector<media::ParcInbandDataCue>& cues);
  // TextTrack: "com.apple.streaming" for the metadata track.
  String inBandMetadataTrackDispatchType() const override;

  // TextTrack: a mode change also goes to the player.
  void setMode(const V8TextTrackMode&) override;
  // The element's automatic selection shows the track WebKit's would: the
  // player scores the tracks by the system caption settings (display mode,
  // caption languages, SDH) and the enabled audio track, and marks that one
  // (configureTextTrackGroup). The group's default option weighs in there.
  bool IsDefault() const override { return info_.automatic; }

  // VTTParserClient: the header parse makes no cues.
  void NewCuesParsed() override {}
  void FileFailedToParse() override {}

  void Trace(Visitor*) const override;

 private:
  // What WebKit's TextTrackCue::isEqual compares besides the start time:
  // the cue type and cueContentsMatch (VTTCue's id, text, settings, position,
  // line, size and align; TextTrackCueGeneric's font and colours too).
  struct CueContents {
    bool generic = false;
    String id;
    String text;
    String settings;
    double line = -1;
    double position = -1;
    double size = -1;
    media::ParcInbandTextCue::Align align =
        media::ParcInbandTextCue::Align::kNone;
    double base_font_size = 0;
    double relative_font_size = 0;
    String font_name;
    std::optional<uint32_t> foreground_color;
    std::optional<uint32_t> background_color;
    bool prevent_line_wrapping = true;

    bool Matches(const CueContents& other) const;
  };

  class CueRecord final : public GarbageCollected<CueRecord> {
   public:
    explicit CueRecord(const CueContents& contents) : contents(contents) {}
    void Trace(Visitor*) const {}
    CueContents contents;
  };

  void AddDataCue(const media::ParcInbandDataCue& data);
  void UpdateDataCue(const media::ParcInbandDataCue& data);
  void RemoveDataCue(const media::ParcInbandDataCue& data);
  // InbandDataTextTrack::findIncompleteCue; forgets open cues the page
  // removed from the track (InbandDataTextTrack::removeCue).
  DataCue* FindIncompleteDataCue(const media::ParcDataCueValue& value);

  void ParseWebVttHeader(const std::string& header);
  void AddWebVttCue(const media::ParcInbandTextCue& data);
  void AddGenericCue(const media::ParcInbandTextCue& data);
  void UpdateGenericCue(const media::ParcInbandTextCue& data);
  void RemoveGenericCue(const media::ParcInbandTextCue& data);

  // InbandGenericTextTrack::updateCueFromCueData.
  void UpdateCueFromCueData(VTTCue& cue,
                            const media::ParcInbandTextCue& data);
  // An open generic cue ends at the media duration once there is one.
  double GenericCueEnd(double end) const;
  static CueContents GenericContents(const media::ParcInbandTextCue& data);

  // TextTrack::matchCue(cue, IgnoreDuration) and
  // InbandGenericTextTrack::cueToExtend over this track's cues.
  TextTrackCue* MatchCue(double start,
                         double end,
                         const CueContents& contents);
  TextTrackCue* CueToExtend(double start,
                            double end,
                            const CueContents& contents);
  const CueContents* ContentsOf(TextTrackCue* cue) const;

  media::ParcInbandTextTrack info_;
  media::ParcInbandTextTrackModeCB set_mode_;
  Member<HTMLMediaElement> element_;
  // Generic cues not yet complete, by the player's cue id.
  HeapHashMap<uint64_t, Member<VTTCue>> generic_cues_;
  // The contents of every cue this track made.
  HeapHashMap<Member<TextTrackCue>, Member<CueRecord>> records_;
  // DataCues still open (m_incompleteCueMap).
  HeapVector<Member<DataCue>> incomplete_data_cues_;
  // The DataCues this track added and still holds: TextTrack::cues() is null
  // while the track is disabled, where WebKit's hasCue still finds them.
  HeapVector<Member<DataCue>> data_cues_;
  VTTRegionMap regions_;
};

template <>
struct DowncastTraits<ParcInbandTextTrack> {
  static bool AllowFrom(const TextTrack& track) {
    return track.TrackType() == TextTrack::kInBand;
  }
};

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_INBAND_TEXT_TRACK_H_
