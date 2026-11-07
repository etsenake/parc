// Copyright 2026 Parc contributors.

#include "third_party/blink/renderer/core/html/media/parc_inband_text_track.h"

#include <cmath>
#include <limits>
#include <utility>

#include "base/containers/span.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_align_setting.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_position_align_setting.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_text_track_kind.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_text_track_mode.h"
#include "third_party/blink/renderer/bindings/core/v8/v8_union_autokeyword_double.h"
#include "third_party/blink/renderer/core/css/css_style_sheet.h"
#include "third_party/blink/renderer/core/dom/document.h"
#include "third_party/blink/renderer/core/html/media/html_media_element.h"
#include "third_party/blink/renderer/core/html/track/text_track_cue.h"
#include "third_party/blink/renderer/core/html/track/text_track_cue_list.h"
#include "third_party/blink/renderer/platform/bindings/exception_state.h"
#include "third_party/blink/renderer/platform/heap/collection_support/heap_vector.h"
#include "third_party/blink/renderer/platform/wtf/text/atomic_string.h"

namespace blink {

namespace {

using Align = media::ParcInbandTextCue::Align;

// InbandTextTrackPrivateAVF::startTimeVariance: a quarter second.
constexpr double kStartTimeVariance = 0.25;

V8TextTrackKind KindFor(const std::string& kind) {
  std::optional<V8TextTrackKind> parsed =
      V8TextTrackKind::Create(String::FromUtf8(kind));
  return parsed ? *parsed : V8TextTrackKind(V8TextTrackKind::Enum::kSubtitles);
}

media::ParcInbandTextTrackMode ModeFor(V8TextTrackMode::Enum mode) {
  switch (mode) {
    case V8TextTrackMode::Enum::kDisabled:
      return media::ParcInbandTextTrackMode::kDisabled;
    case V8TextTrackMode::Enum::kHidden:
      return media::ParcInbandTextTrackMode::kHidden;
    case V8TextTrackMode::Enum::kShowing:
      return media::ParcInbandTextTrackMode::kShowing;
  }
  return media::ParcInbandTextTrackMode::kDisabled;
}

// TextTrackCue::hasEquivalentStartTime.
bool EquivalentStartTimes(double a, double b) {
  return std::abs(std::abs(a) - std::abs(b)) <= kStartTimeVariance;
}

bool IsPercentage(double value) {
  return value >= 0 && value <= 100;
}

}  // namespace

bool ParcInbandTextTrack::CueContents::Matches(
    const CueContents& other) const {
  if (generic != other.generic || id != other.id || text != other.text ||
      settings != other.settings || line != other.line ||
      position != other.position || size != other.size ||
      align != other.align) {
    return false;
  }
  if (!generic) {
    return true;
  }
  // TextTrackCueGeneric::cueContentsMatch (no highlight colour there).
  return base_font_size == other.base_font_size &&
         relative_font_size == other.relative_font_size &&
         font_name == other.font_name &&
         foreground_color == other.foreground_color &&
         background_color == other.background_color &&
         prevent_line_wrapping == other.prevent_line_wrapping;
}

ParcInbandTextTrack::ParcInbandTextTrack(
    const media::ParcInbandTextTrack& info,
    HTMLMediaElement& element,
    media::ParcInbandTextTrackModeCB set_mode)
    : TextTrack(KindFor(info.kind),
                AtomicString(String::FromUtf8(info.label)),
                AtomicString(String::FromUtf8(info.language)),
                element,
                AtomicString(String::FromUtf8(info.id)),
                TextTrack::kInBand),
      info_(info),
      set_mode_(std::move(set_mode)),
      element_(&element) {
  // In-band data is loaded as it plays; nothing to wait for.
  SetReadinessState(kLoaded);
}

ParcInbandTextTrack::~ParcInbandTextTrack() = default;

void ParcInbandTextTrack::Update(const media::ParcInbandTextTrack& info) {
  if (info.id != info_.id) {
    SetId(String::FromUtf8(info.id));
  }
  if (info.kind != info_.kind) {
    SetKind(KindFor(info.kind));
  }
  if (info.label != info_.label) {
    SetLabel(AtomicString(String::FromUtf8(info.label)));
  }
  if (info.language != info_.language) {
    SetLanguage(AtomicString(String::FromUtf8(info.language)));
  }
  info_ = info;
}

void ParcInbandTextTrack::SetModeCallback(
    media::ParcInbandTextTrackModeCB set_mode) {
  set_mode_ = std::move(set_mode);
}

void ParcInbandTextTrack::setMode(const V8TextTrackMode& mode) {
  // InbandTextTrack::setMode: the DOM track first, then the player.
  const bool changed = this->mode().AsEnum() != mode.AsEnum();
  TextTrack::setMode(mode);
  if (changed && set_mode_) {
    set_mode_.Run(info_.key, ModeFor(mode.AsEnum()));
  }
}

void ParcInbandTextTrack::AddCues(
    const std::vector<media::ParcInbandTextCue>& cues) {
  for (const media::ParcInbandTextCue& cue : cues) {
    switch (cue.type) {
      case media::ParcInbandTextCue::Type::kWebVttHeader:
        ParseWebVttHeader(cue.text);
        break;
      case media::ParcInbandTextCue::Type::kWebVtt:
        AddWebVttCue(cue);
        break;
      case media::ParcInbandTextCue::Type::kAdd:
        AddGenericCue(cue);
        break;
      case media::ParcInbandTextCue::Type::kUpdate:
        UpdateGenericCue(cue);
        break;
      case media::ParcInbandTextCue::Type::kRemove:
        RemoveGenericCue(cue);
        break;
    }
  }
}

// InbandGenericTextTrack::parseWebVTTFileHeader: regions and style sheets.
void ParcInbandTextTrack::ParseWebVttHeader(const std::string& header) {
  auto* parser =
      MakeGarbageCollected<VTTParser>(this, element_->GetDocument());
  parser->ParseBytes(base::span<const char>(header));
  parser->Flush();
  HeapVector<Member<CSSStyleSheet>> style_sheets;
  parser->GetNewStyleSheets(style_sheets);
  // The player sends a track's header once; a track keeps its first sheets
  // (TextTrack::SetCSSStyleSheets takes them only once).
  if (!style_sheets.empty() && GetCSSStyleSheets().empty()) {
    SetCSSStyleSheets(std::move(style_sheets));
  }
  for (const auto& region : parser->RegionMap()) {
    regions_.Set(region.key, region.value);
  }
}

// WebVTTParser::parseCueData, then InbandGenericTextTrack::newCuesParsed.
void ParcInbandTextTrack::AddWebVttCue(const media::ParcInbandTextCue& data) {
  if (std::isnan(data.start)) {
    return;
  }
  // A sample without a duration (never seen from AVFoundation) leaves the
  // cue open.
  const double end = std::isnan(data.end)
                         ? std::numeric_limits<double>::infinity()
                         : data.end;
  CueContents contents;
  contents.id = String::FromUtf8(data.identifier);
  contents.text = String::FromUtf8(data.text);
  contents.settings = String::FromUtf8(data.settings);

  TextTrackCue* existing = CueToExtend(data.start, end, contents);
  if (!existing) {
    existing = MatchCue(data.start, end, contents);
  }
  if (existing) {
    if (existing->endTime() < end) {
      existing->setEndTime(end, IGNORE_EXCEPTION);
    }
    return;
  }

  VTTCue* cue =
      VTTCue::Create(element_->GetDocument(), data.start, end, contents.text);
  cue->setId(AtomicString(contents.id));
  cue->ParseSettings(&regions_, contents.settings);
  records_.Set(cue, MakeGarbageCollected<CueRecord>(contents));
  addCue(cue);
}

// InbandGenericTextTrack::addGenericCue.
void ParcInbandTextTrack::AddGenericCue(const media::ParcInbandTextCue& data) {
  if (!data.cue_id || generic_cues_.Contains(data.cue_id) ||
      std::isnan(data.start) || std::isnan(data.end)) {
    return;
  }
  VTTCue* cue = VTTCue::Create(element_->GetDocument(), data.start,
                               GenericCueEnd(data.end),
                               String::FromUtf8(data.text));
  UpdateCueFromCueData(*cue, data);
  CueContents contents = GenericContents(data);
  if (MatchCue(cue->startTime(), cue->endTime(), contents)) {
    return;
  }
  if (!data.complete) {
    generic_cues_.Set(data.cue_id, cue);
  }
  records_.Set(cue, MakeGarbageCollected<CueRecord>(contents));
  addCue(cue);
}

// InbandGenericTextTrack::updateGenericCue.
void ParcInbandTextTrack::UpdateGenericCue(
    const media::ParcInbandTextCue& data) {
  auto it = generic_cues_.find(data.cue_id);
  if (it == generic_cues_.end()) {
    return;
  }
  VTTCue* cue = it->value.Get();
  UpdateCueFromCueData(*cue, data);
  records_.Set(cue, MakeGarbageCollected<CueRecord>(GenericContents(data)));
  if (data.complete) {
    generic_cues_.erase(it);
  }
}

// InbandGenericTextTrack::removeGenericCue.
void ParcInbandTextTrack::RemoveGenericCue(
    const media::ParcInbandTextCue& data) {
  auto it = generic_cues_.find(data.cue_id);
  if (it == generic_cues_.end()) {
    return;
  }
  VTTCue* cue = it->value.Get();
  generic_cues_.erase(it);
  records_.erase(cue);
  if (cue->track() == this) {
    removeCue(cue, IGNORE_EXCEPTION);
  }
}

double ParcInbandTextTrack::GenericCueEnd(double end) const {
  // updateCueFromCueData: +infinity becomes the list's duration when valid
  // (still +infinity for a live stream).
  if (std::isinf(end) && end > 0) {
    const double duration = element_->duration();
    if (!std::isnan(duration)) {
      return duration;
    }
  }
  return end;
}

void ParcInbandTextTrack::UpdateCueFromCueData(
    VTTCue& cue,
    const media::ParcInbandTextCue& data) {
  cue.setStartTime(data.start);
  cue.setEndTime(GenericCueEnd(data.end), IGNORE_EXCEPTION);
  cue.setText(String::FromUtf8(data.text));
  // TextTrackCueGeneric's font size, font name and colours have no VTTCue
  // counterpart in Blink.
  if (data.position > 0 && IsPercentage(std::round(data.position))) {
    cue.setPosition(MakeGarbageCollected<V8UnionAutoKeywordOrDouble>(
                        std::round(data.position)),
                    IGNORE_EXCEPTION);
  }
  if (data.line > 0) {
    cue.setLine(
        MakeGarbageCollected<V8UnionAutoKeywordOrDouble>(std::round(data.line)));
  }
  if (data.size > 0 && IsPercentage(std::round(data.size))) {
    cue.setSize(std::round(data.size), IGNORE_EXCEPTION);
  }
  switch (data.position_align) {
    case Align::kStart:
      cue.setPositionAlign(
          V8PositionAlignSetting(V8PositionAlignSetting::Enum::kLineLeft));
      break;
    case Align::kMiddle:
      cue.setPositionAlign(
          V8PositionAlignSetting(V8PositionAlignSetting::Enum::kCenter));
      break;
    case Align::kEnd:
      cue.setPositionAlign(
          V8PositionAlignSetting(V8PositionAlignSetting::Enum::kLineRight));
      break;
    case Align::kNone:
      break;
  }
  switch (data.align) {
    case Align::kStart:
      cue.setAlign(V8AlignSetting(V8AlignSetting::Enum::kStart));
      break;
    case Align::kMiddle:
      cue.setAlign(V8AlignSetting(V8AlignSetting::Enum::kCenter));
      break;
    case Align::kEnd:
      cue.setAlign(V8AlignSetting(V8AlignSetting::Enum::kEnd));
      break;
    case Align::kNone:
      break;
  }
  cue.setSnapToLines(false);
}

ParcInbandTextTrack::CueContents ParcInbandTextTrack::GenericContents(
    const media::ParcInbandTextCue& data) {
  CueContents contents;
  contents.generic = true;
  contents.text = String::FromUtf8(data.text);
  contents.line = data.line;
  contents.position = data.position;
  contents.size = data.size;
  contents.align = data.align;
  contents.base_font_size = data.base_font_size;
  contents.relative_font_size = data.relative_font_size;
  contents.font_name = String::FromUtf8(data.font_name);
  contents.foreground_color = data.foreground_color;
  contents.background_color = data.background_color;
  contents.prevent_line_wrapping = data.prevent_line_wrapping;
  return contents;
}

const ParcInbandTextTrack::CueContents* ParcInbandTextTrack::ContentsOf(
    TextTrackCue* cue) const {
  auto it = records_.find(cue);
  return it == records_.end() ? nullptr : &it->value->contents;
}

TextTrackCue* ParcInbandTextTrack::MatchCue(double start,
                                            double end,
                                            const CueContents& contents) {
  if (start < 0 || end < 0) {
    return nullptr;
  }
  TextTrackCueList* list = cues();
  if (!list) {
    return nullptr;
  }
  // The list is in start time order.
  for (wtf_size_t i = 0; i < list->length(); ++i) {
    TextTrackCue* existing = list->AnonymousIndexedGetter(i);
    if (existing->startTime() > start + kStartTimeVariance) {
      return nullptr;
    }
    if (!EquivalentStartTimes(start, existing->startTime())) {
      continue;
    }
    const CueContents* existing_contents = ContentsOf(existing);
    if (existing_contents && existing_contents->Matches(contents)) {
      return existing;
    }
  }
  return nullptr;
}

TextTrackCue* ParcInbandTextTrack::CueToExtend(double start,
                                               double end,
                                               const CueContents& contents) {
  if (start < 0 || end < 0) {
    return nullptr;
  }
  TextTrackCueList* list = cues();
  if (!list || list->length() < 2) {
    return nullptr;
  }
  for (wtf_size_t i = 0; i < list->length(); ++i) {
    TextTrackCue* existing = list->AnonymousIndexedGetter(i);
    if (std::abs(start - existing->startTime()) > kStartTimeVariance) {
      continue;
    }
    if (std::abs(start - existing->endTime()) > kStartTimeVariance) {
      return nullptr;
    }
    const CueContents* existing_contents = ContentsOf(existing);
    if (existing_contents && existing_contents->Matches(contents)) {
      return existing;
    }
  }
  return nullptr;
}

void ParcInbandTextTrack::Trace(Visitor* visitor) const {
  visitor->Trace(element_);
  visitor->Trace(generic_cues_);
  visitor->Trace(records_);
  visitor->Trace(regions_);
  TextTrack::Trace(visitor);
  VTTParserClient::Trace(visitor);
}

}  // namespace blink
