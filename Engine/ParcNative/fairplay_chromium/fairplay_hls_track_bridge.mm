#include "third_party/parc_fairplay/chromium/fairplay_hls_track_bridge.h"

#import <AVFoundation/AVFoundation.h>

#include <utility>

#include "third_party/parc_fairplay/core/fairplay_hls_media_selection_internal.h"
#include "third_party/parc_fairplay/core/fairplay_hls_player_internal.h"

namespace media {

namespace {

namespace fp = parc::fairplay;

mojom::FairPlayHlsTrackPtr ToMojo(const fp::HlsTrack& track) {
  auto result = mojom::FairPlayHlsTrack::New();
  result->key = track.key;
  result->id = track.id;
  result->kind = track.kind;
  result->label = track.label;
  result->language = track.language;
  result->enabled = track.enabled;
  result->index = track.index;
  result->type = track.type == fp::HlsTrackType::kAudio
                     ? mojom::FairPlayHlsTrackType::kAudio
                     : mojom::FairPlayHlsTrackType::kText;
  result->is_default = track.is_default;
  result->is_closed_captions = track.is_closed_captions;
  result->is_sdh = track.is_sdh;
  result->contains_only_forced_subtitles =
      track.contains_only_forced_subtitles;
  result->is_main_program_content = track.is_main_program_content;
  result->is_easy_to_read = track.is_easy_to_read;
  result->automatic = track.automatic;
  return result;
}

std::vector<mojom::FairPlayHlsTrackPtr> ToMojo(
    const std::vector<fp::HlsTrack>& tracks) {
  std::vector<mojom::FairPlayHlsTrackPtr> result;
  result.reserve(tracks.size());
  for (const fp::HlsTrack& track : tracks) {
    result.push_back(ToMojo(track));
  }
  return result;
}

mojom::FairPlayHlsCueType ToMojo(fp::HlsCue::Type type) {
  switch (type) {
    case fp::HlsCue::Type::kWebVttHeader:
      return mojom::FairPlayHlsCueType::kWebVttHeader;
    case fp::HlsCue::Type::kWebVtt:
      return mojom::FairPlayHlsCueType::kWebVtt;
    case fp::HlsCue::Type::kAdd:
      return mojom::FairPlayHlsCueType::kAdd;
    case fp::HlsCue::Type::kUpdate:
      return mojom::FairPlayHlsCueType::kUpdate;
    case fp::HlsCue::Type::kRemove:
      return mojom::FairPlayHlsCueType::kRemove;
  }
  return mojom::FairPlayHlsCueType::kAdd;
}

mojom::FairPlayHlsCueAlign ToMojo(fp::HlsCueAlign align) {
  switch (align) {
    case fp::HlsCueAlign::kNone:
      return mojom::FairPlayHlsCueAlign::kNone;
    case fp::HlsCueAlign::kStart:
      return mojom::FairPlayHlsCueAlign::kStart;
    case fp::HlsCueAlign::kMiddle:
      return mojom::FairPlayHlsCueAlign::kMiddle;
    case fp::HlsCueAlign::kEnd:
      return mojom::FairPlayHlsCueAlign::kEnd;
  }
  return mojom::FairPlayHlsCueAlign::kNone;
}

mojom::FairPlayHlsCuePtr ToMojo(const fp::HlsCue& cue) {
  auto result = mojom::FairPlayHlsCue::New();
  result->type = ToMojo(cue.type);
  result->cue_id = cue.cue_id;
  result->start = cue.start;
  result->end = cue.end;
  result->complete = cue.complete;
  result->text = cue.text;
  result->identifier = cue.identifier;
  result->settings = cue.settings;
  result->source_id = cue.source_id;
  result->original_start_time = cue.original_start_time;
  result->line = cue.line;
  result->position = cue.position;
  result->size = cue.size;
  result->base_font_size = cue.base_font_size;
  result->relative_font_size = cue.relative_font_size;
  result->font_name = cue.font_name;
  result->align = ToMojo(cue.align);
  result->position_align = ToMojo(cue.position_align);
  result->foreground_color = cue.foreground_color;
  result->background_color = cue.background_color;
  result->highlight_color = cue.highlight_color;
  result->prevent_line_wrapping = cue.prevent_line_wrapping;
  return result;
}

fp::HlsTextTrackMode FromMojo(mojom::FairPlayHlsTextTrackMode mode) {
  switch (mode) {
    case mojom::FairPlayHlsTextTrackMode::kDisabled:
      return fp::HlsTextTrackMode::kDisabled;
    case mojom::FairPlayHlsTextTrackMode::kHidden:
      return fp::HlsTextTrackMode::kHidden;
    case mojom::FairPlayHlsTextTrackMode::kShowing:
      return fp::HlsTextTrackMode::kShowing;
  }
  return fp::HlsTextTrackMode::kDisabled;
}

}  // namespace

FairPlayHlsTrackBridge::FairPlayHlsTrackBridge(
    mojom::FairPlayHlsPlayerClient* client,
    parc::fairplay::PostTask post_task)
    : client_(client), selection_(this, std::move(post_task)) {}

FairPlayHlsTrackBridge::~FairPlayHlsTrackBridge() = default;

void FairPlayHlsTrackBridge::Attach(
    parc::fairplay::FairPlayHlsPlayer::Impl* player) {
  if (attached_ || !player) {
    return;
  }
  AVPlayer* av_player = fp::HlsPlayerAVPlayer(player);
  AVPlayerItem* item = av_player.currentItem;
  if (!av_player || !item) {
    return;
  }
  attached_ = true;
  fp::HlsMediaSelectionAttach(selection_.impl(), av_player, item);
}

std::vector<mojom::FairPlayHlsTrackPtr>
FairPlayHlsTrackBridge::TakeTracksForInitialize() {
  initialized_ = true;
  last_sent_ = selection_.Tracks();
  return ToMojo(last_sent_);
}

void FairPlayHlsTrackBridge::SetAudioTrackEnabled(const std::string& key,
                                                  bool enabled) {
  selection_.SetAudioTrackEnabled(key, enabled);
}

void FairPlayHlsTrackBridge::SetTextTrackMode(
    const std::string& key,
    mojom::FairPlayHlsTextTrackMode mode) {
  selection_.SetTextTrackMode(key, FromMojo(mode));
}

void FairPlayHlsTrackBridge::WillSeek() {
  ++pending_seeks_;
  selection_.BeginSeeking();
}

void FairPlayHlsTrackBridge::DidSeek() {
  // WebKit ends the text track's seeking state once the last seek is done.
  if (pending_seeks_ > 0 && --pending_seeks_ == 0) {
    selection_.EndSeeking();
  }
}

void FairPlayHlsTrackBridge::OnTracksChanged(
    const std::vector<parc::fairplay::HlsTrack>& tracks) {
  // Before the Initialize reply the list is folded into it
  // (TakeTracksForInitialize reads the selection's latest). After it, the
  // selection's latest list goes out when it differs from the last one sent:
  // a report queued before the reply may be older than the reply's.
  if (!initialized_) {
    return;
  }
  std::vector<parc::fairplay::HlsTrack> current = selection_.Tracks();
  if (current == last_sent_) {
    return;
  }
  last_sent_ = current;
  client_->OnTracksChanged(ToMojo(current));
}

void FairPlayHlsTrackBridge::OnTextCues(
    const std::string& track_key,
    const std::vector<parc::fairplay::HlsCue>& cues) {
  std::vector<mojom::FairPlayHlsCuePtr> result;
  result.reserve(cues.size());
  for (const parc::fairplay::HlsCue& cue : cues) {
    result.push_back(ToMojo(cue));
  }
  client_->OnTextCues(track_key, std::move(result));
}

}  // namespace media
